# Run from project root: .\scripts\fix_setup.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ROOT = "C:\Users\Hp\Desktop\ShadowPass backend\app"
$BUILD = "$ROOT\build"
$SNARKJS = "$ROOT\node_modules\snarkjs\build\cli.cjs"

function Log($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)  { Write-Host "    OK: $msg" -ForegroundColor Green }
function Err($msg) { Write-Host "    MISSING: $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Step 0: Show exactly what's in build/ right now
# ---------------------------------------------------------------------------
Log "Scanning build directory"
Write-Host ""

if (-not (Test-Path $BUILD)) {
    Write-Host "build/ does not exist at all - creating it" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $BUILD | Out-Null
}

$files = Get-ChildItem -Path $BUILD -File -ErrorAction SilentlyContinue
if ($files) {
    $files | ForEach-Object {
        $size = [math]::Round($_.Length / 1KB, 1)
        Write-Host ("  " + $_.Name + "  (" + $size + " KB)")
    }
} else {
    Write-Host "  (empty)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 1: Check what we actually have
# ---------------------------------------------------------------------------
Log "Checking required artifacts"

$hasR1CS   = Test-Path "$BUILD\withdraw.r1cs"
$hasPtau   = Test-Path "$BUILD\pot15_final.ptau"
$hasZkey0  = Test-Path "$BUILD\withdraw_0000.zkey"

if ($hasR1CS) { Ok "withdraw.r1cs" } else { Err "withdraw.r1cs - need to recompile circuit" }
if ($hasPtau) { Ok "pot15_final.ptau" } else { Err "pot15_final.ptau - need Powers of Tau" }
if ($hasZkey0) { Ok "withdraw_0000.zkey" } else { Err "withdraw_0000.zkey - g16s did not finish" }

# ---------------------------------------------------------------------------
# Step 2: Recompile circuit if missing
# ---------------------------------------------------------------------------
if (-not $hasR1CS) {
    Log "Recompiling circuit"
    $CIRCUITS = "$ROOT\circuits"

    if (-not (Test-Path "$CIRCUITS\node_modules\circomlib")) {
        Push-Location $CIRCUITS
        npm install circomlib circomlibjs
        Pop-Location
    }

    circom "$CIRCUITS\withdraw.circom" `
        --r1cs --wasm --sym `
        -l "$CIRCUITS\node_modules" `
        -o $BUILD

    if (-not (Test-Path "$BUILD\withdraw.r1cs")) {
        Write-Host "Circuit compile failed. Check circom is installed: circom --version" -ForegroundColor Red
        exit 1
    }
    Ok "Circuit compiled"
}

# ---------------------------------------------------------------------------
# Step 3: Powers of Tau if missing
# ---------------------------------------------------------------------------
if (-not $hasPtau) {
    Log "Running Powers of Tau phase 1"
    Push-Location $BUILD

    $e1 = [System.BitConverter]::ToString(
        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    ).Replace("-","")

    node $SNARKJS powersoftau new bn128 15 pot15_0000.ptau -v
    node $SNARKJS powersoftau contribute pot15_0000.ptau pot15_0001.ptau `
        --name="shadowpass" -v -e="$e1"
    node $SNARKJS powersoftau prepare phase2 pot15_0001.ptau pot15_final.ptau -v

    Pop-Location
    Ok "pot15_final.ptau ready"
}

# ---------------------------------------------------------------------------
# Step 4: Groth16 setup (produces withdraw_0000.zkey) - THE MISSING STEP
# ---------------------------------------------------------------------------
if (-not $hasZkey0) {
    Log "Running groth16 setup - this takes 5-15 min, do not close terminal"
    Write-Host "    Constraints: 10,202  |  ptau slots: 32,768  |  fits fine" -ForegroundColor Gray

    Push-Location $BUILD
    node $SNARKJS groth16 setup withdraw.r1cs pot15_final.ptau withdraw_0000.zkey
    Pop-Location

    if (-not (Test-Path "$BUILD\withdraw_0000.zkey")) {
        Write-Host "g16s failed - check output above for the real error" -ForegroundColor Red
        exit 1
    }
    Ok "withdraw_0000.zkey produced"
}

# ---------------------------------------------------------------------------
# Step 5: Phase 2 contribution (produce withdraw_final.zkey)
# ---------------------------------------------------------------------------
Log "Phase 2 contribution"

$e2 = [System.BitConverter]::ToString(
    [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
).Replace("-","")

Push-Location $BUILD
node $SNARKJS zkey contribute withdraw_0000.zkey withdraw_final.zkey `
    --name="shadowpass-circuit" -v -e="$e2"
Pop-Location

if (-not (Test-Path "$BUILD\withdraw_final.zkey")) {
    Write-Host "zkey contribute failed" -ForegroundColor Red
    exit 1
}
Ok "withdraw_final.zkey ready"

# ---------------------------------------------------------------------------
# Step 6: Export verification key
# ---------------------------------------------------------------------------
Log "Exporting verification key"

Push-Location $BUILD
node $SNARKJS zkey export verificationkey withdraw_final.zkey verification_key.json
Pop-Location

if (-not (Test-Path "$BUILD\verification_key.json")) {
    Write-Host "vkey export failed" -ForegroundColor Red
    exit 1
}
Ok "verification_key.json ready"

# ---------------------------------------------------------------------------
# Step 7: Copy wasm to frontend/public/circuit/
# ---------------------------------------------------------------------------
Log "Copying circuit artifacts to frontend"

$circuitPublic = "$ROOT\frontend\public\circuit"
New-Item -ItemType Directory -Force -Path $circuitPublic | Out-Null

$wasmSrc = "$BUILD\withdraw_js\withdraw.wasm"
if (Test-Path $wasmSrc) {
    Copy-Item $wasmSrc "$circuitPublic\withdraw.wasm" -Force
    Copy-Item "$BUILD\withdraw_final.zkey" "$circuitPublic\withdraw_final.zkey" -Force
    Ok "wasm + zkey copied to frontend/public/circuit/"
} else {
    Write-Host "withdraw.wasm not found at $wasmSrc" -ForegroundColor Yellow
    Write-Host "Check build/ for a withdraw_js subfolder" -ForegroundColor Yellow
    Get-ChildItem $BUILD -Recurse -Filter "*.wasm" | ForEach-Object { Write-Host "  Found: $($_.FullName)" }
}

# ---------------------------------------------------------------------------
# Step 8: Compute real Poseidon zero hashes
# ---------------------------------------------------------------------------
Log "Computing Poseidon zero hashes for merkle.rs"

$zeroScript = @"
const { buildPoseidon } = require('./circuits/node_modules/circomlibjs');
buildPoseidon().then(poseidon => {
    const F = poseidon.F;
    const zeros = [0n];
    for (let i = 1; i < 20; i++) {
        zeros.push(F.toObject(poseidon([zeros[i-1], zeros[i-1]])));
    }
    const lines = zeros.map(z => z.toString(16).padStart(64, '0'));
    console.log(lines.join('\n'));
}).catch(e => { console.error(e); process.exit(1); });
"@

Push-Location $ROOT
$zeroHexLines = node -e $zeroScript
Pop-Location

Write-Host ""
Write-Host "Zero hashes (paste into merkle.rs ZERO_HASHES_HEX):" -ForegroundColor Yellow
$zeroHexLines -split "`n" | ForEach-Object { Write-Host "    `"$_`"," }

# Auto-patch merkle.rs
$merkleRs = "$ROOT\contracts\shielded_pool\src\merkle.rs"
$content = Get-Content $merkleRs -Raw

$newConst = "const ZERO_HASHES_HEX: [&str; TREE_DEPTH as usize] = [`n"
$zeroHexLines -split "`n" | ForEach-Object {
    $newConst += "    `"$_`",`n"
}
$newConst += "];"

$pattern = 'const ZERO_HASHES_HEX[\s\S]*?\];'
if ($content -match $pattern) {
    $patched = $content -replace $pattern, $newConst
    Set-Content $merkleRs $patched -Encoding utf8
    Ok "merkle.rs patched with real zero hashes"
} else {
    Write-Host "Could not auto-patch merkle.rs - paste the lines above manually" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " CIRCUIT SETUP COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next: .\scripts\build_contract.ps1" -ForegroundColor Cyan
Write-Host ""