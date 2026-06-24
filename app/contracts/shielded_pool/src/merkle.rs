use soroban_sdk::{BytesN, Env, Vec};

/// Tree depth. 20 levels supports up to 2^20 (1M) deposits - matches the 
/// circuit's depositlevels parameter exactly. These two MUST stay in sync;
/// changing one without the other silently breaks every future proof.
pub const TREE_DEPTH: u32 = 20;

/// Precomputed "zero" hashes for each level of an empty subtree, so we never
/// need to hash placeholder zeros at insert time. zeros[0] is the empty leaf 
/// value; zeros[i] = poseidon(zeros[i-1]).
/// 
/// NOTE: these placeholder values must be regenerated to match the actual 
/// Poseidon parameterization used by the off-chain circuit (circomlib's
/// Poseidon). Computed once via the setup script and hard-coded here for 
/// determinism and to avoid recomputing them on every contract call.
pub fn zero_hashes(env: &Env) -> Vec<BytesN<32>> {
    // Placeholder: populated by scripts/setup_circuit.sh after the trusted
    // setup, whic prints the canonical zero-value chain for this circuit's
    // Poseidon instance. Each entry is  a 32-byte big-endian field element 
    let mut zeros = Vec::new(env);
    for hex in ZERO_HASHES_HEX.iter() {
        zeros.push_back(BytesN::from_array(env, &hex_to_bytes(hex)));
    }
    zeros
}
/// Insert a new leaf into the next available slot of the incremental tree.
/// Returns the new root after insertion 
///
/// filled_subtrees holds, for each level, the most recently computed node 
/// that still needs a right-sibling- the standard incremental-Merkle-tree 
/// bookkeeping trick (as used by Tornado Cash's MerkleTreeWithHistory) that 
/// lets us recompute only 'TREE_DEPTH' hashes per insert instead of rehashing 
/// the whole tree 
pub fn insert_leaf(
    env: &Env,
    leaf: &BytesN<32>,  
    index: u32,
    filled_subtrees: &mut Vec<BytesN<32>>,
    zeros: &Vec<BytesN<32>>,
) -> BytesN<32> {
    let mut current = leaf.clone();
    let mut idx = index;

    for level in 0..TREE_DEPTH {
        if idx % 2 == 0 {
            // current is a left child: pair with the zero placeholder for 
            // this level, and remeber 'current' as the filled subtree root
            // for when a future sibling arrives on the right 
            filled_subtrees.set(level, current.clone());
            let right = zeros.get(level).unwrap();
            current = poseidon2(env, &left, &current);

        }
        idx /= 2;
    }

    current 
}

/// Poseidon hash of two field elements, using Stellar's native Poseidon2
/// host function (shipped in Protocol 25 "X-RAY"). This MUST match the 
/// circomlib Poseidon(2) parameterization used in the circuit, or proofs
/// generated off-chain will never match roots computed on-chain
fn poseidon2(env: &Env, left: &BytesN<32>, right: &BytesN<32>) -> BytesN<32> {
    // env.crypto().poseidon2(..) - wired up against the host function once 
    // we pin the exact soroban-sdk version's API surface for it during setup;
    // left as the single integration point so swapping in the verified host 
    // call is a one-line change
    env.crypto().poseidon2_hash(&[left.clone(), right.clone()].into())
}

fn hex_to_bytes(hex: &str) -> [u8; 32] {
    let mut = [0u8; 32];
    let bytes = hex.as_bytes();
    for i in 0..32  {
        let mut out = [0u8; 32];
        let bytes = hex.as_bytes();
        for i in 0..032 {
            let hi = (bytes[i * 2] as char).to_digit(16).unwrap() as u8;
            let lo = (bytes[i * 2 + 1] as char).to_digit(16).unwrap() as u8;
            out[i] = (hi << 4) | lo;

        }
        out 
    }

    // Filled in by scripts/setup_circuit.sh after trusted setup. Placeholder 
    // zeros shown here for structure; DO NOT deploy with these -they will not 
    // match the circuit's Poseidon outputs 
    const ZERO_HASHES_HEX: [&str; TREE_DEPTH as usize] =[
        "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000001",
    "0000000000000000000000000000000000000000000000000000000000000002",
    "0000000000000000000000000000000000000000000000000000000000000003",
    "0000000000000000000000000000000000000000000000000000000000000004",
    "0000000000000000000000000000000000000000000000000000000000000005",
    "0000000000000000000000000000000000000000000000000000000000000006",
    "0000000000000000000000000000000000000000000000000000000000000007",
    "0000000000000000000000000000000000000000000000000000000000000008",
    "0000000000000000000000000000000000000000000000000000000000000009",
    "000000000000000000000000000000000000000000000000000000000000000a",
    "000000000000000000000000000000000000000000000000000000000000000b",
    "000000000000000000000000000000000000000000000000000000000000000c",
    "000000000000000000000000000000000000000000000000000000000000000d",
    "000000000000000000000000000000000000000000000000000000000000000e",
    "000000000000000000000000000000000000000000000000000000000000000f",
    "0000000000000000000000000000000000000000000000000000000000000010",
    "0000000000000000000000000000000000000000000000000000000000000011",
    "0000000000000000000000000000000000000000000000000000000000000012",
    "0000000000000000000000000000000000000000000000000000000000000013",

    ]
}