# Referensi Algoritma ECDSA (Verify) — secp256k1

Diberikan:
- Parameter kurva secp256k1: (p, a, b, G, n, h=1)
- Kunci publik Q = d·G, d ∈ [1, n−1]
- Hash pesan `z` (di proyek ini = `keccak256("\x19\x01" || domainSeparator || structHash)`)
- Tanda tangan (r, s), masing-masing 256-bit

Langkah verifikasi (FIPS 186-5):
1. Pastikan 1 ≤ r ≤ n−1 dan 1 ≤ s ≤ n−1.
2. Hitung w = s^{-1} mod n.
3. Hitung u1 = (z · w) mod n, u2 = (r · w) mod n.
4. Hitung titik P = u1·G + u2·Q (penjumlahan & perkalian titik pada kurva).
5. Jika P = ∞, tolak.
6. Ambil v = x(P) mod n. Tanda tangan sah bila v == r.

Catatan Ethereum:
- Terapkan aturan **low-S** (EIP-2): s ≤ n/2.
- EIP-712: `z = keccak256("\x19\x01" || DOMAIN_SEPARATOR || structHash)`.

---
Perhitungan ECDSA melibatkan:

Modular inverse: w = s^(-1) mod n
Scalar multiplication: u1·G + u2·Q
Operasi pada kurva secp256k1

Di Solidity:

Tidak ada library BigInt bawaan
Operasi 256-bit manual sangat mahal gas
Risiko bug sangat tinggi

Solusi Ethereum:
Sediakan ecrecover() sebagai precompiled contract yang:

Cepat (gas efisien)
Aman (sudah diaudit ribuan kali)
Mudah dipakai (1 baris kode)