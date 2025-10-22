// Run: npx ts-node --esm scripts/sign_eip712.ts
// or:  node --loader ts-node/esm scripts/sign_eip712.ts

import { secp256k1 } from "@noble/curves/secp256k1"; 
import { keccak_256 } from "@noble/hashes/sha3"; 

// Helper: convert string/number to Uint8Array
function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  return Uint8Array.from(Buffer.from(clean, "hex"));
}
function toHex(bytes: Uint8Array): string {
  return "0x" + Buffer.from(bytes).toString("hex");
}

// Demo: fixed data like in the contract
const name = "ElliptiCheck";
const version = "1";
const chainId = 31337;
const verifyingContract = "0x0000000000000000000000000000000000000000";

const ticketId = 1n;
const owner = "0xBEEF000000000000000000000000000000000000";
const nonce = 1n;
const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
const metadataHash = keccak_256(Buffer.from("meta"));

// Compute domain separator
const domainTypeHash = keccak_256(
  Buffer.from("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);
const domainSeparator = keccak_256(
  Buffer.concat([
    domainTypeHash,
    keccak_256(Buffer.from(name)),
    keccak_256(Buffer.from(version)),
    Buffer.from(chainId.toString(16).padStart(64, "0"), "hex"),
    hexToBytes(verifyingContract),
  ])
);

// Compute struct hash
const typeHash = keccak_256(
  Buffer.from(
    "TicketAccess(uint256 ticketId,address owner,uint256 nonce,uint256 deadline,bytes32 metadataHash)"
  )
);
const structHash = keccak_256(
  Buffer.concat([
    typeHash,
    Buffer.from(ticketId.toString(16).padStart(64, "0"), "hex"),
    hexToBytes(owner),
    Buffer.from(nonce.toString(16).padStart(64, "0"), "hex"),
    Buffer.from(deadline.toString(16).padStart(64, "0"), "hex"),
    metadataHash,
  ])
);

// Compute digest = keccak256("\x19\x01" || domainSeparator || structHash)
const prefix = Uint8Array.from([0x19, 0x01]);
const digest = keccak_256(Buffer.concat([prefix, domainSeparator, structHash]));

// Sign using Anvil default key
const privateKey =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"; // demo only
const signature = secp256k1.sign(digest, hexToBytes(privateKey));

// Extract r, s, v
const r = signature.r.toString(16).padStart(64, "0");
const s = signature.s.toString(16).padStart(64, "0");
const v = (signature.recovery + 27).toString(16).padStart(2, "0"); 
const sigHex = "0x" + r + s + v;

console.log("Digest:    " + toHex(digest));
console.log("r:         0x" + r);
console.log("s:         0x" + s);
console.log("v:         " + (signature.recovery + 27)); // Log decimal 27/28
console.log("Signature: " + sigHex);