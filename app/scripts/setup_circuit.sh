#!/usr/bin/env bash
# ShadowPass: circuit compilation + Groth16 trusted setup.
#
# Produces, under build/:
#   withdraw.r1cs, withdraw_js/withdraw.wasm   — compiled circuit
#   withdraw_final.zkey                        — proving key (after phase-2 ceremony)
#   verification_key.json                      — public verification key
#
# Requires: circom (>=2.1.5), node + npm, snarkjs.
# This is a HACKATHON trusted setup — a single-contributor ceremony, not a
# production-grade multi-party computation. Say this explicitly in the demo;
# judges who know ZK will ask, and dodging the question reads worse than
# answering it directly.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
CIRCUITS_DIR="$ROOT_DIR/circuits"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "==> Installing circomlib + snarkjs (local, not global)"
npm install --no-save circomlib snarkjs

echo "==> Compiling withdraw.circom"
circom "$CIRCUITS_DIR/withdraw.circom" \
  --r1cs --wasm --sym \
  -l node_modules \
  -o "$BUILD_DIR"

echo "==> Circuit stats"
npx snarkjs r1cs info withdraw.r1cs

# Powers of Tau (universal, circuit-independent phase 1). Using a small
# existing ptau file is fine for a circuit this size (well under 2^15
# constraints expected); regenerate with a higher power if r1cs info above
# reports more constraints than 2^14.
PTAU_FILE="pot15_final.ptau"
if [ ! -f "$PTAU_FILE" ]; then
  echo "==> Running Powers of Tau ceremony (phase 1, single contributor — hackathon only)"
  npx snarkjs powersoftau new bn128 15 pot15_0000.ptau -v
  npx snarkjs powersoftau contribute pot15_0000.ptau pot15_0001.ptau \
    --name="shadowpass-hackathon-contribution" -v -e="$(head -c 64 /dev/urandom | base64)"
  npx snarkjs powersoftau prepare phase2 pot15_0001.ptau "$PTAU_FILE" -v
fi

echo "==> Groth16 phase 2 setup (circuit-specific)"
npx snarkjs groth16 setup withdraw.r1cs "$PTAU_FILE" withdraw_0000.zkey
npx snarkjs zkey contribute withdraw_0000.zkey withdraw_final.zkey \
  --name="shadowpass-circuit-contribution" -v -e="$(head -c 64 /dev/urandom | base64)"

echo "==> Exporting verification key"
npx snarkjs zkey export verificationkey withdraw_final.zkey verification_key.json

echo "==> Done. Artifacts in $BUILD_DIR"
echo "    Next: node $ROOT_DIR/scripts/encode_proof.mjs --vk-only"
echo "    to produce the Soroban-encoded VerificationKey for contract init."