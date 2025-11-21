// get-public-key.mjs
import { secp256k1 } from '@noble/curves/secp256k1';

// Ambil dari .env atau ganti langsung
const privateKeyHex = process.env.PRIVATE_KEY || 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

const cleanPrivateKey = privateKeyHex.replace('0x', '');
const privateKey = BigInt('0x' + cleanPrivateKey);

const publicKey = secp256k1.getPublicKey(privateKey, false);

const qx = publicKey.slice(1, 33);
const qy = publicKey.slice(33, 65);

const qxHex = '0x' + Buffer.from(qx).toString('hex');
const qyHex = '0x' + Buffer.from(qy).toString('hex');

console.log('Public Key Coordinates:');
console.log('Qx:', qxHex);
console.log('Qy:', qyHex);