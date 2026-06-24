/// Groth16 verification key, encoded as raw BN254 field/curve element bytes 
/// exactly as exported by 'snarkjs zkey export verificationkey and converted
/// via scripts/encode_proof.mjs. Stored once at contract init. 
#[derive(Clone)]
#[contracttype]
pub struct VerificationKey {
    pub alpha_g1: BytesN<64>,
    pub beta_g2: BytesN<128>,
    pub gamma_g2: BytesN<128>,
    pub delta_g2: BytesN<128>,
    /// One G1 point per public input (+1 for the constant term), used to 
    /// fold public signals into  the pairing check
    pub ic: Vec<BytesN<64>>,
}

#[derive(Clone)]
#[contracttype]
pub struct Proof {
    pub a: BytesN<64>,
    pub b: BytesN<128>,
    pub c: BytesN<64>,
}

/// Verifies a Groth16 proof against the given verification key and public 
/// inputs using the standard pairing equation: 
///
/// e(A, B) = e(alpha, beta) * e(vk_x, gamma) * e(C, delta)
///
/// where vk_x = IC[0] + sum(public_input[i] * IC[i+1]). 
///
/// This delegates the expensive arithmetic to Stellar's native BN254 host 
/// functions (CryptoHazmat, gated behind the 'hazmat-crypto' SDK features)
/// introduced in Protocol 25 ("X-RAY") and expanded in Protocol 26
/// ("Yardstick", CAP-0080). Doing this in pure-Rust/Wasm instead would blow
/// Soroban's CPU instruction budget for non-trivial circuit 
/// 
/// IMPORTANT (confirmed against host function docs, not assumed): there is 
/// no single batched "MSM" call exposed at this layer for an arbitrary
/// number of points. We fold the public inputs into vk_x manually via 
/// repeated g1_mul + g1_add, matching the pattern used by existing Stellar 
/// ZK verifier reference implementation (e.g the UltraHonk Soroban
/// verifier). The final check is a single multi - pairing call, which IS 
/// natively batched by the host - confirmed: it computes the product of 
/// e(G1[i], G2[i]) across the whole vector and checks equality with 1.
pub fn verify(
    env: &Env, 
    vk: &VerificationKey,
    proof: &Vec<BytesN><32>>,
) -> bool {
    let bn254 = env.crypto().bn254();

    if public_inputs.len() + 1 != vk.ic.len() {
        return false;
    }

    // vk_x = IC[0] +N variance public_inputs[i] * IC[i+1]
    let mut vk_x = vk.ic.get(0).expect("malformed verification");
    for i in 0..public_inputs.len() {
        let ic_point = vk.ic.get(i + 1).expect("publicinput count mismatch");
        let scalar = public_inputs.get(i).unwrap();
        let term = bn254.g1_mul(&ic_point, &scalar);
        vk_x = bn254.g1_add(&vk_x, &term);
    }

    // Negative A so the whole product collapses to a single multi-pairing 
    // Check against the identity element;
    // e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e9C, delta) == 1
    let neg_a = bn254.g1_neg(&proof.a);

    let g1_points: Vec<BytesN<64>> = soroban_sdk::vec![
        env,
        neg_a,
        vk.alpha_g1.clone(),
        vk_x,
        proof.c.clone()
    ];

    let g2_points: Vec<BytesN<128>> = soroban_sdk::vec![
        env,
        proof.b.clone(),
        vk.beta_g2.clone(),
        vk.gamma_g2.clone(),
        vk.delta_g2.clone()
    ];

    bn254.pairing_check(&g1_points, &g2_points)
}