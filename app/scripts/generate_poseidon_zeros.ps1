$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appDir = Resolve-Path (Join-Path $scriptDir '..')
$modulePath = Join-Path $appDir 'circuits\node_modules\circomlibjs'
$modulePath = $modulePath -replace '\\', '/'

$nodeScript = @"
const { buildPoseidon } = require('${modulePath}');

buildPoseidon().then(poseidon => {
  const F = poseidon.F;
  const zeros = [0n];
  for (let i = 1; i < 20; i++) {
    zeros.push(F.toObject(poseidon([zeros[i-1], zeros[i-1]])));
  }
  zeros.forEach(z => console.log(z.toString(16).padStart(64, '0')));
}).catch(err => {
  console.error(err);
  process.exit(1);
});
"@

node -e $nodeScript
