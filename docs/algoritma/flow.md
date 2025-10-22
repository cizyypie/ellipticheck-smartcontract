
# 🔐 ElliptiCheck – Flow Verifikasi Tanda Tangan ECDSA (EIP-712)

Diagram ini menjelaskan dua level penggunaan algoritma **Elliptic Curve Digital Signature Algorithm (ECDSA)**  
pada sistem ElliptiCheck:  
1️⃣ Level protokol blockchain (OpenZeppelin ERC-721 / transaksi NFT)  
2️⃣ Level aplikasi penelitian (verifikasi tiket EIP-712 tanpa library eksternal)



## 🧩 1. Arsitektur Sistem

```mermaid
flowchart TD

A[🎟️ TicketNFT.sol<br>ERC-721 (OpenZeppelin)] -->|Mint Tiket NFT| B[👤 Pemilik Tiket (User Wallet)]
B -->|Mengajukan Akses Event| C[💻 Off-chain Issuer Signer<br>(sign_eip712.ts)]
C -->|Menandatangani Data Terstruktur<br>(EIP-712 digest)| D[📜 TicketVerifier.sol<br>(ECDSA Manual + Nonce + Expiry)]
D -->|Verifikasi Tanda Tangan dengan ecrecover()| E[(Ethereum Virtual Machine)]
E -->|Valid| F[✅ Emit TicketUsed Event<br>Mark Used Digest]
E -->|Invalid / Replay / Expired| G[❌ Revert Error]

````

---

## 🧠 2. Penjelasan Tahapan

| Langkah | Komponen                            | Proses                               | Penjelasan Teknis                                                                                                       |
| ------- | ----------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| ①       | **TicketNFT.sol**                   | Mint NFT tiket untuk user            | Kontrak berbasis OpenZeppelin ERC-721, menggunakan ECDSA *default* Ethereum untuk autentikasi transaksi (`msg.sender`). |
| ②       | **sign_eip712.ts**                  | Penandatanganan data tiket off-chain | Skrip Node.js membentuk `digest` sesuai EIP-712, lalu menandatangani dengan kunci privat *issuer*.                      |
| ③       | **TicketVerifier.sol**              | Verifikasi tanda tangan tiket        | Kontrak membaca `(r, s, v)` dan `digest`, lalu memverifikasi dengan `ecrecover()` (ECDSA bawaan EVM).                   |
| ④       | **EVM (Precompiled Contract 0x01)** | Proses matematika ECDSA              | Menjalankan operasi kurva eliptik secp256k1 untuk mengembalikan alamat publik dari tanda tangan.                        |
| ⑤       | **Nonce & Expiry Check**            | Anti replay protection               | Mencegah penggunaan ulang signature atau penggunaan setelah `deadline` kedaluwarsa.                                     |
| ⑥       | **Event TicketUsed**                | Logging hasil sukses                 | Menandai tiket terpakai & mencatat waktu verifikasi di blockchain.                                                      |

---

## 🧬 3. Ringkasan Level ECDSA

| Level                          | Letak                                    | Tujuan                                              | Implementasi                          |
| ------------------------------ | ---------------------------------------- | --------------------------------------------------- | ------------------------------------- |
| **Blockchain Level (Default)** | Transaksi `mintTicket()` di ERC-721      | Menjamin transaksi autentik & sah                   | ECDSA bawaan EVM (`msg.sender`)       |
| **Aplikasi Level (Custom)**    | `verifyAccess()` di `TicketVerifier.sol` | Menjamin tiket valid, belum replay, & belum expired | Manual EIP-712 digest + `ecrecover()` |

---

## 🧾 4. Kesimpulan Teknis

> Algoritma **ECDSA** di proyek ElliptiCheck diterapkan melalui dua lapisan:
>
> * Lapisan **protokol (Ethereum)** untuk autentikasi transaksi NFT.
> * Lapisan **aplikasi (verifikasi tiket)** yang menggunakan `ecrecover()` sebagai fungsi kriptografi bawaan EVM.
>
> Dengan pendekatan ini, sistem dapat memastikan integritas, autentikasi, dan non-repudiation
> tanpa menulis ulang perhitungan matematika kurva eliptik yang berat secara gas dan kompleks secara implementasi.

---

## 📚 Referensi Teknis

* [Ethereum Yellow Paper – ECDSA and secp256k1 Verification (2019)](https://ethereum.github.io/yellowpaper/paper.pdf)
* [NIST FIPS 186-5 Digital Signature Standard (2023)](https://doi.org/10.6028/NIST.FIPS.186-5)
* [OpenZeppelin ERC-721 Documentation](https://docs.openzeppelin.com/contracts/4.x/api/token/erc721)

```

---