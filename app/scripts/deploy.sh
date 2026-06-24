#!/usr/bin/env bash
# Build and deploy the ShadowPass shielded pool contract to Stellar testnet.
#
# Prerequisites:
#   - stellar-cli installed (https://developers.stellar.org/docs/tools/cli)
#   - A funded testnet identity: `stellar keys generate deployer --network testnet`
#     then fund via https://lab.stellar.org/account/fund or `stellar keys fund deployer --network testnet`
#   - scripts/setup_circuit.sh already run, verification_key.encoded.json present

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$ROOT_DIR/contracts/shielded_pool"
BUILD_DIR="$ROOT_DIR/build"
NETWORK="${STELLAR_NETWORK:-testnet}"
DEPLOYER="${STELLAR_DEPLOYER_IDENTITY:-deployer}"

echo "==> Building contract (release profile)"
cd "$CONTRACT_DIR"
stellar contract build

WASM_PATH="$CONTRACT_DIR/target/wasm32-unknown-unknown/release/shielded_pool.wasm"
if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: expected wasm at $WASM_PATH, got nothing. Check the build output above."
  exit 1
fi

echo "==> Deploying to $NETWORK"
CONTRACT_ID=$(stellar contract deploy \
  --wasm "$WASM_PATH" \
  --source "$DEPLOYER" \
  --network "$NETWORK")

echo "==> Deployed: $CONTRACT_ID"
echo "$CONTRACT_ID" > "$BUILD_DIR/contract_id.txt"

if [ ! -f "$BUILD_DIR/verification_key.encoded.json" ]; then
  echo "WARNING: no encoded verification key found at $BUILD_DIR/verification_key.encoded.json"
  echo "Run scripts/setup_circuit.sh and scripts/encode_proof.mjs --vk first, then re-run init manually:"
  echo "  stellar contract invoke --id $CONTRACT_ID --source $DEPLOYER --network $NETWORK -- initialize ..."
  exit 0
fi

echo "==> NOTE: the actual 'initialize' invocation requires the token contract"
echo "    address (your SAC), a chosen denomination, and a sanctions Merkle root"
echo "    computed by a separate off-chain script (not included in this scaffold —"
echo "    see docs/README.md 'Known Gaps' for what's stubbed vs. real)."
echo ""
echo "    Example shape (fill in real values before running):"
echo ""
cat <<'EOF'
stellar contract invoke \
  --id $CONTRACT_ID \
  --source $DEPLOYER \
  --network $NETWORK \
  -- \
  initialize \
  --admin $DEPLOYER \
  --token <SAC_TOKEN_CONTRACT_ID> \
  --denomination 1000000000 \
  --verification_key file://build/verification_key.encoded.json \
  --sanctions_root <SANCTIONS_MERKLE_ROOT_HEX>
EOF