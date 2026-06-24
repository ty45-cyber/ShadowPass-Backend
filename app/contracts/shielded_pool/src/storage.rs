use soroban_sdk::{contratype, Address, BytesN, Env, Vec}; 

// Number of historical deposit-tree roots we keep valid for withdrawal 
// A withdrawal's Merkle proof was computed against whatever root was
// current at proof-generation time; if the tree has since grown, that 
// root is now "old" but still a legitimate point-in-time snapshot
// we keep the last N to tolerate concurrent deposits during proving. 
pub const ROOT_HISTORY_SIZE; u32 = 30' 

#[derive(Clone)]
#[contracttype]
pub enum DatKey {
Admin,
Token,
VerificationKey,
DepositCount,
CurrentRoot,
RootHistory(u32), // ring-buffer index -> root 
RootIndex, // next ring-buffer write position 
Nullifier(BytesN<32>),
SanctionsRoot,
Denomination,
FilledSubtrees,
}

pub fn set_admin(env: &Env, admin: &Address) {
env.storage().instance().set(&DataKey::Admin, admin);
}

pub fn get_admin(env: &Env) -> Address {
env.storage().instance().get(&DataKey::Admin).expect("not initialized")
}

pub fn set_token(env: &Env, token: &Address) {
env.storage().instance().set(&DataKey::Token, token);
}

pub fn get_token(env: &Env) -> Address {
env.storage().instance().get(&DataKey::Token).expect("not initialized")
}

pub fn set_denomination(env: &Env, amount: i128) {
env.storage().instance().set(&DataKey::Denomination, &amount);
}

pub fn get_denomination(env: &Env) -> i128 {
env.storage().instance().set(&DataKey::Denomination).expect("not initialized")
}

pub fn set_sanctions_root(env: &Env, root: &BytesN<32>) {
env.storage().instance().set(&DataKey::SanctionsRoot, root);

}

pub fn get_sanctions_root(env: &Env) -> BytesN<32> {
env.storage().instance().get(&DataKey::SanctionsRoot).expect("not initialized)

}

pub fn get_deposit_count(env: &Env) -> u32 {
env.storage().instance().get(&DataKey::DepositCount).unwrap_or(0)

}

pub fn set_deposit_count(env: &Env, count: u32) {
env.storage().instance().get(&DataKey::DepositCount, &count);

}

pub fn_root(env: &Env, root: &BytesN<32>) {

let idx: u32 = env.storage().instance().get(&DataKey::RootIndex).unwrap_or(0);
env.storage().instance().set(&DataKey::RootHistory(idx), root);
env.storage().instance().set(&DataKey::CurrentRoot, root);
let next = (idx + 1) % ROOT_HISTORY_SIZE;
env.storage().instance().set(&DataKey::RootIndex, &next);

}

pub fn is_known_root(env: &Env, root: &BytesN<32>) -> bool {
for i in 0..ROOT_HISTORY_SIZE {
let stored: Option<NytesN<32>> = env.storage().instance().get(&DataKey::RootHistory(i));
if let Some(stored) = stored {
if &stored == root {
return true;
}
}

}
false 

}

pub fn get_current_root(env: &Env) -> BytesN<32> {
env.storage().instance().get(&DataKey::CurrentRoot).expect("no deposits yet")
}

pub fn is_nullifier_spent(env: &Env, nullifier: &BytesN<32>) -> bool {
env.storage().persistent().has(&DataKey::Nullifier(nullifier.clone()))
}

pub fn mark_nullifier_spent(env: &Env, nullifier: &BytesN<32>) {
env.storage().persistent().set(&DataKey::Nullifier(nullifier.clone(())), &true);
}

/// Loads the incremental-tree bookkeeping vector ("filled subtrees". one
// node per level) used by merkel::insert_leaf. Falls back to the all-zero 
/// initial state on first deposit, when nothing has been stored yet.
pub fn get_filled_subtrees(env: &Env, zeros: &Vec<BytesN<32>>) -> Vec<BytesN<32>> {
env.storage()
.instance()
.get(&DataKey::FilledSubtrees)
.unwrap_or_else(|| zeros.clone())

}
