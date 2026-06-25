# ShadowPass

**A shielded payment pool on Stellar where privacy is conditional on a cryptographic compliance proof — not unconditional anonymity.**

Built for [Stellar Hacks: Real-World ZK](https://dorahacks.io/hackathon/stellar-hacks-zk).

## The problem with privacy pools

Every transaction on Stellar (and every public blockchain) is fully transparent. For real-world payment rails — remittances, payroll, B2B settlement — this is a genuine liability: counterparties, amounts, and timing all leak to anyone watching the chain.

Privacy pools (Tornado Cash and its many descendants) solve this with zero-knowledge proofs, but they solve it *unconditionally*: anyone, including sanctioned actors, can use them, with no way to distinguish legitimate privacy from money laundering. That's exactly why Tornado Cash was sanctioned by the U.S. Treasury in 2022.

**ShadowPass makes privacy conditional on provable innocence.** To withdraw from the pool, you must submit a single ZK proof that does two things at once:

1. Proves you own a valid, unspent deposit in the pool (standard Merkle membership).
2. Proves your identity commitment is **not present** in a published sanctions Merkle tree (Merkle non-membership) — without revealing who you are.

Neither the pool operator nor any observer learns which deposit is yours. But the chain can verify, mathematically, that whoever withdrew was not on the sanctions list at the time of withdrawal. This is the cryptographic compliance pattern regulators have asked the industry for since the Tornado Cash sanctions: privacy that is provably bounded, not privacy that is unconditional.

## Why Stellar, why now

This wasn't really buildable on Stellar until a few months ago. Protocol 25 ("X-Ray", Jan 2026) shipped native BN254 curve operations and Poseidon/Poseidon2 hashing as Soroban host functions. Protocol 26 ("Yardstick", May 2026) added the additional BN254 host functions (scalar-field arithmetic, curve-membership checks) needed to make Groth16 pairing checks affordable inside Soroban's compute budget. Without these, a Groth16 verifier in pure Wasm would blow Soroban's CPU instruction limit for any circuit beyond a toy example.

## Architecture
circuits/          Circom circuits (Groth16) — Merkle membership + non-membership + nullifier

contracts/          Soroban smart contract (Rust) — pool, verifier, on-chain Merkle tree

scripts/            Trusted setup, proof encoding, deployment

frontend/           Vite/React — deposit/withdraw UI, client-side proving

**Circuit (`circuits/withdraw.circom`):** Given a secret note, proves in zero knowledge that (a) the note's commitment is a member of the deposits tree, (b) the note's identity commitment is *not* a member of the sanctions tree, and (c) the revealed nullifier was derived correctly from the secret — preventing double-spend without revealing which note was spent. The withdrawal recipient is bound into the proof so a relayer can't redirect funds.

**Contract (`contracts/shielded_pool/`):** Holds the pooled SAC token, maintains the on-chain incremental Merkle tree of deposits (Poseidon2 via Stellar's native host function), verifies Groth16 proofs via BN254 pairing checks (also native host functions), and tracks spent nullifiers to prevent reuse.

**Frontend:** Generates notes client-side, builds the Merkle trees by replaying on-chain deposit events (no trusted server), and runs proof generation entirely in-browser via snarkjs — secrets never leave the client.

## Honest scope: what's built vs. what's scaffolded

This was built solo in 8 days for a hackathon deadline. Being upfront about exactly where the line sits:

**Fully designed and implemented:**
- Circuit logic (Merkle membership + non-membership + nullifier derivation + recipient binding)
- Contract logic (deposit, withdraw, nullifier tracking, root history, Groth16 verification using Stellar's BN254 host functions)
- Client-side Merkle tree library matching the on-chain tree structure
- Proof generation pipeline (snarkjs, in-browser)
- Wallet integration (Freighter), contract invocation (deposit/withdraw), and on-chain event fetching — wired against confirmed Stellar SDK APIs

**Known correctness risks, flagged explicitly (see "Known engineering risks" below):**
- The sanctions Merkle tree is seeded with mock data for the demo. It is **not** connected to a real OFAC/sanctions data feed. We say this explicitly rather than implying otherwise.
- Trusted setup (`scripts/setup_circuit.sh`) is a single-contributor ceremony, appropriate for a hackathon demo, not a production multi-party computation.
- The address-to-field-element encoding (used to bind the withdrawal recipient into the proof) depends on a soroban-sdk API that may still be unstable — see below.

**Deliberately cut from scope (see "Why this scope" below):**
- Shielded withdrawal amounts — fixed denomination only, same pattern as the original Tornado Cash, to avoid UTXO note-splitting complexity in 8 days
- Shielded recipient address
- A real, maintained sanctions data oracle

## Why this scope

Fixed-denomination pools are the proven, shippable pattern. Variable-amount shielded pools require note-splitting/merging circuits that are a multi-week effort on their own — attempting that in 8 days solo would have meant a half-working proof system instead of a fully working, narrower one. We'd rather ship something real than something ambitious and broken.

## Known engineering risks (flagged, not hidden)

- **G1/G2 coordinate ordering** between snarkjs's export format and Soroban's expected byte layout is a common silent-failure point in every Circom-on-chain integration. `scripts/encode_proof.mjs` and `frontend/src/lib/stellar.js` both flag this explicitly in comments; it must be validated against a known-good test vector before trusting it in production.
- **BN254 host function API surface** (CAP-80) shipped within the last two months at time of writing. The exact Rust method names used in `verifier.rs` (`g1_mul`, `g1_add`, `g1_neg`, `pairing_check`) are modeled on a real reference implementation (the UltraHonk Soroban verifier) but should be checked against the live `soroban-sdk` docs for the exact version pinned in `Cargo.toml` before deploying.
- **Address-to-field-element encoding** (`lib.rs::address_to_field`, `WithdrawPanel.jsx::addressToField`) uses `Address::to_payload`, gated behind the `hazmat-address` soroban-sdk feature. As of this writing there's an open SDK issue (stellar/rs-soroban-sdk#1636) requesting exactly this capability, suggesting the API may be newer/less stable than the rest of the SDK surface used here. Both sides are written to hash the same raw 32-byte Ed25519 public key, but this has not been tested end-to-end against a real deployed contract.
- **Non-membership proof construction** (`frontend/src/lib/merkleTree.js`, `identityCommitmentToSlot`) uses a simplified hash-to-slot approach for the demo's small, static sanctions list. A production system would use a sorted-list bracketing scheme for rigorous non-membership regardless of list size.
- **`fetchDepositCommitments`** (`frontend/src/lib/stellar.js`) relies on `server.getEvents`, which RPC nodes retain for 7 days by default. Fine for a hackathon demo lifecycle; a long-running pool needs a persistent indexer instead.

## Running locally

```bash
# 1. Circuit + trusted setup
./scripts/setup_circuit.sh

# 2. Encode verification key for contract init
node scripts/encode_proof.mjs --vk build/verification_key.json

# 3. Build + deploy contract (requires stellar-cli + funded testnet identity)
./scripts/deploy.sh

# 4. Frontend
cd frontend
npm install
npm run dev
```

## License

MIT
