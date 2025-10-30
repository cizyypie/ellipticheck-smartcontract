// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ECDSAVerify {
    uint256 constant a = 0;
    uint256 constant b = 7;
    uint256 constant p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 constant Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240;
    uint256 constant Gy =
        32670510020758816978083085130507043184471273380659243275938904335757337482424;

    struct ECPoint {
        uint256 x;
        uint256 y;
    }

    /// z hash pesan, r komponen r, s komponen s, Q public key signer
    /// return valid true jika tanda tangan valid (r == x_R mod n)
    function ecdsaverify(
        uint256 z,
        uint256 r,
        uint256 s,
        ECPoint memory Q
    ) internal pure returns (bool valid) {
        require(r > 0 && r < n, "invalid r"); //validasi rentang nilai tanda tangan
        require(s > 0 && s < n, "invalid s"); //untuk menolak tanda tangan palsu diluar kurva

        uint256 sInv = modInverse(s, n); //menghitung invrs dari s, langkah awal verifikasi ecdsa
        uint256 u1 = mulmod(z, sInv, n); //u1 u2 Kombinasi linier faktor verifikasi, menggabungkan pesan n tanda tangan  
        uint256 u2 = mulmod(r, sInv, n); //u1 = z·s⁻¹ mod n | u2 = r·s⁻¹ mod n

        ECPoint memory R = ecAdd(ecMul(u1, ECPoint(Gx, Gy)), ecMul(u2, Q)); //Menghitung titik hasil di kurva (R')
                                                             //Melakukan perhitungan geometrik ECDSA

        if (R.x == 0 && R.y == 0) return false; 
        return (addmod(R.x, 0, n) == r); //Membandingkan hasil tanda tangan
                                        //Menentukan tanda tangan valid atau tidak
    }

    // =============== Operasi kurva eliptik ===============
    function ecAdd(ECPoint memory P, ECPoint memory Q)
        internal
        pure
        returns (ECPoint memory R)
    {
        if (P.x == 0 && P.y == 0) return Q;
        if (Q.x == 0 && Q.y == 0) return P;

        uint256 lambda;
        if (P.x == Q.x) {
            lambda = mulmod(3 * mulmod(P.x, P.x, p) + a, modInverse(2 * P.y, p), p);
        } else {
            lambda = mulmod(addmod(Q.y, p - P.y, p), modInverse(addmod(Q.x, p - P.x, p), p), p);
        }

        uint256 xr = addmod(mulmod(lambda, lambda, p), p - addmod(P.x, Q.x, p), p);
        uint256 yr = addmod(mulmod(lambda, addmod(P.x, p - xr, p), p), p - P.y, p);
        R = ECPoint(xr, yr);
    }

    function ecMul(uint256 k, ECPoint memory P) internal pure returns (ECPoint memory R){
        R = ECPoint(0, 0);
        ECPoint memory addend = P;
        while (k != 0) {
            if ((k & 1) != 0) R = ecAdd(R, addend);
            addend = ecAdd(addend, addend);
            k >>= 1;
        }
    }

    function modInverse(uint256 a_, uint256 m) internal pure returns (uint256) {
        if (a_ == 0 || a_ == m || m == 0) return 0;
        int256 t1;
        int256 t2 = 1;
        uint256 r1 = m;
        uint256 r2 = a_;
        while (r2 != 0) {
            uint256 q = r1 / r2;
            (r1, r2) = (r2, r1 - q * r2);
            (t1, t2) = (t2, t1 - int256(q) * t2);
        }
        if (t1 < 0) t1 += int256(m);
        return uint256(t1);
    }
}
