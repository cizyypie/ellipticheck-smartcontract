// Referensi ECDSA verify (secp256k1) untuk penelitian akademik.
// Mengikuti FIPS 186-5 + aturan low-S (EIP-2).

import { secp256k1 } from "@noble/curves/secp256k1.js";

// Helper function untuk mengubah Hex menjadi Byte Array
function hexToBytes(hex: string): Uint8Array {
  // Menghapus prefix '0x' jika ada
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;

  if (h.length % 2 !== 0) {
    throw new Error("Invalid hex string: must have an even number of characters.");
  }
  
  const bytes = new Uint8Array(h.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    const j = i * 2;
    bytes[i] = parseInt(h.substring(j, j + 2), 16);
    if (isNaN(bytes[i])) {
      throw new Error("Invalid hex string: contains non-hex characters.");
    
  }
  return bytes;
}

export function ecdsaVerify(
  digestHex: string,
  rHex: string,
  sHex: string,
  pubkeyHex: string
): boolean {
  try {
    // 1. Gabungkan r dan s menjadi satu signature heksadesimal.
    const signatureHex = rHex.padStart(64, '0') + sHex.padStart(64, '0');

    // 2. Konversi SEMUA input dari hex string ke Uint8Array.
    const signatureBytes = hexToBytes(signatureHex);
    const digestBytes = hexToBytes(digestHex);
    const pubkeyBytes = hexToBytes(pubkeyHex);

    // 3. Panggil fungsi verify dengan argumen Uint8Array.
    // Opsi { strict: true } tetap digunakan untuk memeriksa aturan low-S (EIP-2)
    const isValid = secp256k1.verify(
      signatureBytes,
      digestBytes,
      pubkeyBytes
    );

    return isValid;
  } catch (error) {
    console.error("Verification failed:", error);
    return false;
  }
}