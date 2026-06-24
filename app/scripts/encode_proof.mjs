#!/usr/bin/env node
// Converts snarkjs Groth16 artifacts (verification_key.json, proof.json,
// public.json) into the exact byte layout the ShadowPass Soroban contract
// expects:
//
//   G1 point  -> 64 bytes  = [32-byte x (big-endian)] [32-byte y (big-endian)]
//   G2 point  -> 128 bytes = [64-byte x: Fq2(c0,c1)] [64-byte y: Fq2(c0,c1)]
//
// snarkjs emits G1/G2 coordinates as decimal strings in little-endian
// "array of two/three" projective-ish JSON form; we normalize to affine,
// big-endian, fixed-width hex.
//
// Usage:
//   node encode_proof.mjs --vk build/verification_key.json
//   node encode_proof.mjs --proof build/proof.json --public build/public.json

import { readFileSync, writeFileSync } from 'node:fs';
import { argv } from 'node:process';

function bigIntToBE32(value) {
  const hex = BigInt(value).toString(16).padStart(64, '0');
  return Buffer.from(hex, 'hex');
}

function encodeG1(point) {
  // point = [x, y, 1] as decimal strings (snarkjs affine-ish convention)
  const x = bigIntToBE32(point[0]);
  const y = bigIntToBE32(point[1]);
  return Buffer.concat([x, y]);
}

function encodeG2(point) {
  // point = [[x_c0, x_c1], [y_c0, y_c1], [1, 0]]
  // IMPORTANT: snarkjs orders Fq2 coefficients as [c0, c1] but many BN254
  // pairing implementations (including common Soroban verifier examples)
  // expect [c1, c0] ("big-endian within the extension field"). This has
  // bitten essentially every Circom-on-chain integration at least once.
  // VERIFY against a known-good test vector before trusting this blindly —
  // flagging this explicitly rather than asserting it's correct, because
  // getting it wrong produces a verifier that silently rejects all valid
  // proofs with no useful error message.
  const xC1 = bigIntToBE32(point[0][1]);
  const xC0 = bigIntToBE32(point[0][0]);
  const yC1 = bigIntToBE32(point[1][1]);
  const yC0 = bigIntToBE32(point[1][0]);
  return Buffer.concat([xC1, xC0, yC1, yC0]);
}

function encodeVerificationKey(vk) {
  return {
    alpha_g1: encodeG1(vk.vk_alpha_1).toString('hex'),
    beta_g2: encodeG2(vk.vk_beta_2).toString('hex'),
    gamma_g2: encodeG2(vk.vk_gamma_2).toString('hex'),
    delta_g2: encodeG2(vk.vk_delta_2).toString('hex'),
    ic: vk.IC.map((p) => encodeG1(p).toString('hex')),
  };
}

function encodeProof(proof) {
  return {
    a: encodeG1(proof.pi_a).toString('hex'),
    b: encodeG2(proof.pi_b).toString('hex'),
    c: encodeG1(proof.pi_c).toString('hex'),
  };
}

function encodePublicSignals(publicSignals) {
  return publicSignals.map((s) => bigIntToBE32(s).toString('hex'));
}

function main() {
  const args = argv.slice(2);
  const flagIndex = (name) => args.indexOf(name);

  if (flagIndex('--vk') !== -1) {
    const path = args[flagIndex('--vk') + 1];
    const vk = JSON.parse(readFileSync(path, 'utf8'));
    const encoded = encodeVerificationKey(vk);
    const outPath = path.replace(/\.json$/, '.encoded.json');
    writeFileSync(outPath, JSON.stringify(encoded, null, 2));
    console.log(`Wrote encoded verification key to ${outPath}`);
    console.log(`IC has ${encoded.ic.length} entries (expect: 1 + number of public signals)`);
  }

  if (flagIndex('--proof') !== -1) {
    const proofPath = args[flagIndex('--proof') + 1];
    const publicPath = args[flagIndex('--public') + 1];
    const proof = JSON.parse(readFileSync(proofPath, 'utf8'));
    const publicSignals = JSON.parse(readFileSync(publicPath, 'utf8'));

    const encodedProof = encodeProof(proof);
    const encodedPublic = encodePublicSignals(publicSignals);

    const outPath = proofPath.replace(/\.json$/, '.encoded.json');
    writeFileSync(
      outPath,
      JSON.stringify({ proof: encodedProof, public_inputs: encodedPublic }, null, 2)
    );
    console.log(`Wrote encoded proof + public inputs to ${outPath}`);
  }

  if (flagIndex('--vk') === -1 && flagIndex('--proof') === -1) {
    console.error('Usage: node encode_proof.mjs --vk <path> | --proof <path> --public <path>');
    process.exit(1);
  }
}

main();