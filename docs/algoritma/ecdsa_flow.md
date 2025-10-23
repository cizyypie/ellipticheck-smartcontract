Kontrak (lebih tepatnya **library**) yang kamu kirim ini 
* **Panitia (issuer)** punya *private key* (kunci rahasia) dan *public key* (alamat publik).
* Saat panitia membuat tiket, dia **menandatangani data tiket** dengan *private key*-nya → menghasilkan dua angka: **r** dan **s**.
* Saat pengguna datang ke pintu masuk (check-in), sistem akan:

  * Membaca data tiketnya (hash-nya = z),
  * Membaca tanda tangan (r, s),
  * Lalu memakai *public key* panitia (Q) untuk **memastikan tanda tangan itu benar**.

Nah, library `ECDSAVerify` inilah yang melakukan pengecekan itu.
Kalau hasilnya *benar*, artinya tiket memang resmi dari panitia.

---

## 🔍 Bagian-Bagian Library

### 1️⃣ Konstanta Kurva (Bagian atas)

```solidity
uint256 constant a = 0;
uint256 constant b = 7;
uint256 constant p = 0xFFFFFFFF....;
uint256 constant n = 0xFFFFFFFF....;
uint256 constant Gx = 5506626...;
uint256 constant Gy = 3267051...;
```

Bagian ini mendefinisikan **parameter matematis** dari kurva eliptik yang digunakan.
Nama kurvanya adalah **secp256k1**, kurva standar yang juga dipakai di Bitcoin dan Ethereum.

Kamu bisa anggap ini seperti “aturan main” kurva:

* `p`: batas besar angka yang boleh dipakai.
* `n`: ukuran grup titik pada kurva.
* `(Gx, Gy)`: titik awal (generator) yang jadi dasar semua operasi.
* `a` dan `b`: bentuk persamaan kurva (y² = x³ + 7).

> Dalam bahasa gampang: bagian ini seperti “aturan dan koordinat dasar” dunia tempat tanda tangan digital bekerja.

---

### 2️⃣ Struktur Titik

```solidity
struct ECPoint {
    uint256 x;
    uint256 y;
}
```

Satu titik di kurva eliptik direpresentasikan dengan dua koordinat: `x` dan `y`.

---

### 3️⃣ Fungsi Utama: `ecdsaverify`

```solidity
function ecdsaverify(uint256 z, uint256 r, uint256 s, ECPoint memory Q)
```

Inilah **jantung utama** library.
Fungsinya memeriksa apakah tanda tangan (r, s) **cocok** dengan pesan yang di-hash (`z`) dan public key si penandatangan (`Q`).

Langkah sederhananya begini:

1. **Cek angka valid atau tidak**

   ```solidity
   require(r > 0 && r < n);
   require(s > 0 && s < n);
   ```

   Jadi kalau nilainya aneh atau di luar batas, langsung ditolak.

2. **Hitung kebalikannya (inverse) dari `s`**
   Ini seperti membagi tapi versi “modular”, hasilnya disebut `sInv`.

3. **Hitung dua nilai penting:**

   ```solidity
   u1 = z * sInv mod n
   u2 = r * sInv mod n
   ```

   Dua angka ini jadi “bumbu utama” untuk mencari titik hasil (R) nanti.

4. **Hitung titik R di kurva**

   ```solidity
   R = u1*G + u2*Q
   ```

   Maksudnya:

   * Kalikan titik dasar `G` dengan `u1`
   * Kalikan public key `Q` dengan `u2`
   * Lalu tambahkan hasilnya (ini operasi khusus di kurva eliptik)

   Semua langkah di atas dilakukan pakai fungsi `ecMul()` dan `ecAdd()` yang ditulis manual di bawah.

5. **Cocokkan hasil akhirnya**

   ```solidity
   return (R.x mod n == r);
   ```

   Kalau sama, berarti tanda tangan **benar** → tiket asli.

---

### 4️⃣ Fungsi Tambahan: Operasi Kurva

#### a. `ecAdd`

Menambahkan dua titik di kurva → hasilnya titik baru.
Kalau kamu bayangkan titik di bidang, ini seperti “menggabungkan arah dua titik” sesuai aturan kurva eliptik.

#### b. `ecMul`

Mengalikan titik dengan angka `k` → sebenarnya mengulang penjumlahan titik `k` kali.
Misal 3 × G = G + G + G.

Fungsi ini pakai metode **double-and-add**, supaya cepat (standar di kriptografi eliptik).

#### c. `modInverse`

Fungsi kecil untuk cari kebalikan angka di dunia “modular” (semacam operasi pembagian versi matematika kurva).

---

## 💡 Ringkasannya

| Langkah | Nama Fungsi   | Artinya dalam Bahasa Sederhana       |
| ------- | ------------- | ------------------------------------ |
| 1       | `modInverse`  | Mencari nilai pembagi di dunia kurva |
| 2       | `ecMul`       | Mengalikan titik di kurva            |
| 3       | `ecAdd`       | Menjumlahkan dua titik di kurva      |
| 4       | `ecdsaverify` | Mengecek apakah tanda tangan cocok   |

---

## ✅ Kenapa Penting?

Library ini **tidak hanya penting secara teknis**, tapi juga secara **keamanan data**:

* Memastikan **tiket digital tidak bisa dipalsukan**,
* Menjamin **yang menandatangani benar-benar panitia**,
* Dan **semua dilakukan langsung di blockchain**, jadi transparan dan tidak bisa diubah.

Standar ini (ECDSA) adalah yang juga digunakan dalam:

* Tanda tangan transaksi Ethereum (setiap transaksi yang kamu kirim lewat MetaMask sebenarnya pakai ECDSA),
* Sistem keamanan modern, dan
* Digital signature di dokumen elektronik (*Stallings, 2023, ch.13* dan *NIST FIPS 186-5*).

---

## 🎯 Kesimpulan Super Sederhana

Kalau `TicketNFT` adalah **mesin pencetak tiketnya**,
maka `ECDSAVerify` ini adalah **alat untuk memeriksa keaslian tanda tangan panitia**.

Ibarat di dunia nyata:

> Kamu datang ke konser, petugas scan tiketmu.
> Mesin di gerbang (library ini) mengecek apakah cap tanda tangan panitianya asli.
> Kalau cocok → kamu boleh masuk.
> Kalau tidak → tiket palsu.

---
