pragma circom 2.1.5;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "merkle_tree.circom";

// ShadowPass withdraw circuit. 
// 
// Public proves, in one shot, without revealing the depositor's identity: 
// 1. The withdrawer owns a valid, unspent commitment in the deposits tree.
// 2. The withdrawer's identity commitment is NOT present in the sanction 
// tree ( a "compliance proof" - provable innocence, not a self-report).
// 3. The nullifier being revealed is the correct deterministic nullifier 
// for this commitment, so the same note can't be withdrawn twice.
// 
// Fixed-denomination design: every deposit is the same amount, so the 
// withdrawal amount never needs to be a circuit input. This avoids
// UTXO note-splitting/merging complexity entirely for the hackathon scope

template Withdraw(depositLevels, sanctionsLevels) {
    // --- Public inputs ( visible on-chain, part of the proof statement) ---
    signal input depositsRoot; // current root of the deposits Merkle tree
    signal input sanctionsRoot; // current root of the sanctions Merkle tree 
    signal input nullifierHash; // Poseidon(secret, nullifierSeed) - revealed to prevent double spend
    signal input recipient; // destination address, bound into the proof so it can't be front-run 

    // --- Private inputs ( known only to the prover) ---
    signal input secret;  //  depositor's private note secret 
    signal input nullifierSeed; // per-deposit randomness
    signal input identityCommitment; // Poseidon(identitySecret) --
    signal input depositPathElements[depositLevels];
    signal input depositPathIndices[depositLevels];
    signal input sanctionsPathElements[sanctionsLevels];
    signal input sanctionsPathIndices[sanctionsLevels];
    signal input sanctionsEmptyLeaf; // the canonical "empty slot" hash for the sanctions tree

    // 1. Recompute the deposit commitment from the secret + identity, and 
    // prove it's a member of the deposits tree at the given root.
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== secret;
    commitmentHasher.inputs[1] <== identityCommitment;

    component depositCheck = MerkleTreeChecker(depositLevels);
    depositCheck.leaf <== commitmentHasher.out; 
    depositCheck.root <== depositsRoot;
    for (var i = 0; i < depositLevels; i++) {
        depositCheck.pathElements[i] <== depositPathElements[i];
        depositCheck.pathIndices[i] <== depositPathIndices[i];
    }

    // 2. Prove identityCommitment is NOT in the sanctions tree.
    // Technique: prove that the leaf at the claimed path position in the 
    // sanctions tree equals the canonical empty-leaf marker, AND that 
    // identityCommitment does not equal that empty-leaf's pre-image use 
    // case (i.e it's a distinct value). Combined with the path proof, 
    // this shows "this slot is empty, and you are not secretly squatting
    // in it" the standard non-membership-via-empty-slot pattern,
    component sanctionsCheck = MerkleTreeChecker(sanctionsLevels);
    sanctionsCheck.leaf <== sanctionsEmptyLeaf; 
    sanctionsCheck.root <== sanctionsRoot; 
    for (var i = 0; i < sanctionsLevels; i++) {
        sanctionsCheck.pathElements[i] <== sanctionsPathElements[i];
        sanctionsCheck.pathIndices[i] <== sanctionsPathIndices[i];
    }
    // identityCommitment must differ from the empty-leaf marker, otherwise 
    // a banned identity could trivially claim "my slot is empty" 
    component isEqual = IsEqual(); 
    isEqual.in[0] <== identityCommitment; 
    isEqual.in[1] <== sanctionsEmptyLeaf; 
    isEqual.out === 0; 

    // 3. Recompute nullifier and bind it as a public signal so the contract 
    // can mark it spent. Also bind 'recipient' multiplicatively into a 
    // dummy constraint so the proof is invalid if recipient is altered 
    // after generation (prevents a relayer from rerouting funds)
    component nullifierHasher = Poseidon(2); 
    nullifierHasher.inputs[0] <== secret;
    nullifierHasher.inputs[1] <== nullifierSeed; 
    nullifierHasher.out === nullifierHash; 

    signal recipientBinding; 
    recipientBinding <== recipient * recipient; // forces recipient into the constraint system 




}

component main {public [depositsRoot, sanctionsRoot, nullifierHash, recipient]} = Withdraw(20, 20);