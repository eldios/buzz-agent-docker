#!/usr/bin/env node
// Mint a NIP-OA auth tag: the owner attestation a Buzz relay with
// BUZZ_REQUIRE_RELAY_MEMBERSHIP=true and BUZZ_ALLOW_NIP_OA_AUTH=true needs
// to admit an agent key whose owner is a relay member.
//
// Spec (block/buzz docs/nips/NIP-OA.md): the tag is
//   ["auth", "<owner-pubkey-hex>", "<conditions>", "<sig-hex>"]
// where <sig-hex> is a BIP-340 Schnorr signature over
//   SHA256("nostr:agent-auth:" + <agent-pubkey-hex> + ":" + <conditions>)
// produced with the owner's secret key.
//
// Dependencies: npm install --no-save @noble/curves @noble/hashes
//
// Usage:
//   node mint-auth-tag.mjs --generate
//     Generate a fresh agent keypair (hex secret + pubkey).
//
//   OWNER_SECRET_HEX=<64-hex> node mint-auth-tag.mjs <agent-pubkey-hex> [conditions]
//     Mint the tag. The owner secret is read from the environment only,
//     never from argv, so it cannot leak into shell history or ps output.
//     Keys are hex; convert an nsec/npub with any NIP-19 tool first.

import { schnorr } from "@noble/curves/secp256k1.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex, hexToBytes, utf8ToBytes } from "@noble/hashes/utils.js";

const HEX64 = /^[0-9a-f]{64}$/;

function die(msg) {
  console.error(msg);
  process.exit(1);
}

const args = process.argv.slice(2);

if (args[0] === "--generate") {
  const secret = schnorr.utils.randomSecretKey();
  console.log(JSON.stringify({
    agent_secret_hex: bytesToHex(secret),
    agent_pubkey_hex: bytesToHex(schnorr.getPublicKey(secret)),
  }, null, 2));
  process.exit(0);
}

const agentPubkey = (args[0] ?? "").toLowerCase();
const conditions = args[1] ?? "";
const ownerSecret = (process.env.OWNER_SECRET_HEX ?? "").toLowerCase();

if (!HEX64.test(agentPubkey)) {
  die("usage: mint-auth-tag.mjs --generate | <agent-pubkey-hex> [conditions] (OWNER_SECRET_HEX in env)");
}
if (!HEX64.test(ownerSecret)) {
  die("OWNER_SECRET_HEX must be a 64-char hex secret key");
}
if (/\s/.test(conditions)) {
  die("conditions must not contain whitespace");
}

const preimage = `nostr:agent-auth:${agentPubkey}:${conditions}`;
const message = sha256(utf8ToBytes(preimage));
const sig = schnorr.sign(message, hexToBytes(ownerSecret));
const ownerPubkey = bytesToHex(schnorr.getPublicKey(hexToBytes(ownerSecret)));

if (!schnorr.verify(sig, message, hexToBytes(ownerPubkey))) {
  die("self-verification failed");
}

console.log(JSON.stringify(["auth", ownerPubkey, conditions, bytesToHex(sig)]));
