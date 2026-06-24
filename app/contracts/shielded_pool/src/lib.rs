#![no_std]

mod merkle;
mod storage;
mod verifier;

use soroban_sdk::{contract, contracterror, contractimpl, token, Address, BytesN, Env, Vec};
use verifier::{Proof, Verification};

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    AlreadyInitialized = 1,
    NotInitialized = 2,
    NullifierAlreadySpent = 3,
    UknownDepositRoot = 4,
    InvalidProof = 5,
    SanctionsRootMismatch = 6,
    PoolFull = 7,
}

#[contract]
pub struct ShieldPool;

#[contractimpl]
impl ShieldPool {
    // One-time setup. denomination is the fixed deposit/withdraw amount 
    // in the token's smallest unit- every note in this pool is worth
    // exactly this much, which is what lets withdrawals stay anonymous 
    // (no amount-based correlation between deposits and withdrawals)
    pub fn initialize(
        env: Env, 
        admin: Address,
        token: Address,
        denomination: i128,
        verification_key: VerificationKey, 
        sanctions_root: BytesN<32>,
    ) -> Result<(), Error> {
        if env.storage().instance().has(&storage::DataKey::Admin) {
            return Err(Error::AlreadyInitialized);
        }
        admin.require_auth();

        storage::set_admin(&env, &admin);
        storage::set_token(&env, &token);
        storage::set_denomination(&env, denomination);
        storage::set_sanctions_root(&env, &sanctions_root);
        env.storage()
        .instance()
        .set(&storage::DataKey::VerifcationKey, &verification_key);
        env.storage().instance().set(&storage::DataKey::DepositCount, &0u32);

        // Seed the filled subtrees bookkeeping vector with zero placeholders 
        // and push the empty tree's root as the first known-valid root, so 
        // a withdrawal proof generated against an "empty pool" root concept 
        // is well-defined (not strictly needed since you can't withdraw
        // before any deposit exists, but keeps root history consistent)
        let zeros = merkle::zero_hashes(&env);
        let empty_root = zeros.get(merkle::TREE_DEPTH - 1).unwrap();
        storage::push_root(&env, &empty_root);

        Ok(())
    }

    /// Deposit the fixed denomination and insert commitment (a public 
    /// Poseidon hash computed off-chain as Poseidon(secret, identityCommitment))
    /// depositor's identity or the eventual recipient - only that *some*
    /// valid note now exists in the pool
    pub fn deposit(env: Env, depositor: Address, commitment: BytesN<32>) -> Result<u32, Error> {
        depositor.require_auth();

        let token_addr = storage::get_token(&env);
        let denomination = storage::get_denomination(&env);
        let token_client = token::Client::new(&env, &token_addr);
        token_client.transfer(&depositor, &env.current_contract_address(), &denomination);

        let index = storage::get_deposit_count(&env);
        let denomination = storage::get_denomination(&env);
        let token_client = token::Client::new(&env, &token_addr);
        token_client.transfer(&depositor, &env.current_contract_address(), &denomination);

        let index = storage::get_deposit_count(&env);
        let zeros = merkle::zero_hashes(&env);
        let mut filled_subtrees = storage;:get_filled_subtrees(&env, &zeros);
        let new_root = merkle::insert_leaf(&env, &commitment, index, &mut filled_subtrees &zeros);
        storage::set_filled_subtrees(&env, &filled_subtrees);

        storage::push_root(&env, &new_root);
        storage::set_deposit_count(&env, index + 1);

        env.events()
        .publish((soroban_sdk::symbol_short!("deposit"), index), commitment);

        Ok(index)
    }

    /// Withdraw the fixed denomination to recipient, proving via ZK proof 
    /// that the caller owns an unspent note in the pool AND that their 
    /// identity commitment is not present in the proof itself ( see
    /// circuits/withdraw.circom),  so a relayer or front-runner cannot 
    /// intercept a valid proof and redirect funds to a different address
    pub fn withdraw(
        env: Env, 
        proof: Proof, 
        deposits_root: BytesN<32>,
        nullifier_hash: BytesN<32>,
        recipient: Address,
    ) -> Result<(), Error> {
        if storage::is_nullifier_spent(&env, &nullifier_hash) {
            return Err(Error::NullifierAlreadySpent);
        }
        if !storage::is_known_root(&env, &deposits_root) {
            return Err(Err::UnknownDepositRoot);
        }

        let sanctions_root = storage::get_sanctions_root(&env);
        let vk: VerificationKey = env 
        .storage()
        .instance()
        .get(&storage::DataKey::VerificationKey)
        .ok_or(Error::NotInitialized)?;

        // Public inputs must match the circuits declared public signal 
        // order exactly: [depositsRoot, sancttionsRoot, nullifierHash, recipient]
        let recipient_field = address_to_FIELD(&ENV, &recipient);
        let public_inputs: Vec<BytesN<32>> = soroban_sdk::vec![
            &env,
            deposits_root.clone(),
            sanctions_root,
            nullifier_hash.clone(),
            recipient_field
        ];

        let valid = verifier::verify(&env, &vk, &proof, &public_inputs);
        if !valid {
            return Err(Error::InvalidProof);
        }

        storage::mark_nullifier_spent(&env, &nullifier_hash);

        let token_addr = storage::get_token(&env);
        let denomination = storage::get_denomination(&env);
        let token_client = token::Client::new(&env, &token_addr);
        token_client.transfer(&env.current_contract_address(), &recipient, &denomination);

        env.events()
        .publish((soroban_sdk::symbol_short!("withdraw"),), nullifier_hash);

        Ok(())
    }

    pub fn current_deposits_root(env: Env) -> BytesN<32> {
        storage::get_current_root(&env)
    }
    pub fn is_spent(env: Env, nullifier_hash: BytesN<32>) -> bool {
        storage::is_nullifier_spent(&env, &nullifier_hash)
    }
}

/// Folds a Stellar Address into a single BN254 field element so it can be 
/// passed as a circuit public input. Uses the address's XDR byte  
/// representation hashed down to 32 bytes - the circuit and contract must 
/// derive this identically, so this function is the canonical reference 
/// implementation that scripts/encode_proof.mjs mirrors off-chain.
fn address_to_field(env: &Env, address: &Address) -> BytesN<32> {
    let bytes = address.to_xdr(env);
    env.crypto().sha256(&bytes).into()
}