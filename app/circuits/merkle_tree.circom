pragma circom  2.1.5;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/comparators.circom";

// Proves that 'leaf' is a member of a Merkle tree with the given 'root',
// Using a Poseidon hash at every level.  'pathElements' is the sibling at 
// each level, 'pathIndices' is 0/1 indicating whether the current node is 
// the left or right child at that level 
// 
// This single template is reused for both: 
// - the deposits tree (proving membership: depositor IS in the pool)
// - the sanctions tree (proving non-membership: identity is NOT banned)
// Non-membership is enforced at the call site by comparingthe computed
// root against a *known-empty-leaf* root variant - see withdraw.circom.
template MerkleTreeChecker(levels) {
    signal input leaf;
    signal input root;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal hashes[levels + 1];
    hashes[0] <== leaf;

    component selectors[levels];
    component hashers[levels];

    for (var i = 0; i < levels; i++) {
        // pathIndices[i] must be structly 0 or 1
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        selectors[i] = MultiMux1(2);
        selectors[i].c[0][0] <== hashes[i];
        selectors[i].c[0][1] <== pathElements[i];
        selectors[i].c[1][0] <== pathElements[i];
        selectors[i].c[1][1] <== hashes[i];
        selectors[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== selectors[i].out[0];
        hashers[i].inputs[1] <== selectors[i].out[1];

        hashes[i + 1] <== hashers[i].out;

    }

    root === hashes[levels];
}