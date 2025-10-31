// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ECDSAVerify {
    uint256 constant a = 0;
    uint256 constant b = 7;
    uint256 constant p =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant n =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 constant Gx =
        55066263022277343669578718895168534326250603453777594175500187360389116729240;
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
    function ecAdd(
        ECPoint memory P,
        ECPoint memory Q
    ) internal pure returns (ECPoint memory R) {
        // Titik nol
        if ((P.x == 0 && P.y == 0) && (Q.x == 0 && Q.y == 0)) {
            return ECPoint(0, 0);
        }
        if (P.x == 0 && P.y == 0) return Q;
        if (Q.x == 0 && Q.y == 0) return P;

        // Jika x sama dan y berlawanan (P == -Q) → titik tak berhingga
        if (P.x == Q.x && addmod(P.y, Q.y, p) == 0) {
            return ECPoint(0, 0);
        }

        uint256 lambda;

        if (P.x == Q.x && P.y == Q.y) {
            // Doubling (P == Q)
            if (P.y == 0) {
                return ECPoint(0, 0);
            }
            uint256 num = addmod(mulmod(3, mulmod(P.x, P.x, p), p), a, p);
            uint256 den = modInverse(addmod(P.y, P.y, p), p);
            lambda = mulmod(num, den, p);
        } else {
            // Penjumlahan titik berbeda
            uint256 num = addmod(Q.y, p - P.y, p);
            uint256 diff = addmod(Q.x, p - P.x, p);

            // Tambahkan ini → mencegah modInverse(0,p)
            if (diff == 0) {
                return ECPoint(0, 0);
            }

            uint256 den = modInverse(diff, p);
            lambda = mulmod(num, den, p);
        }

        uint256 xr = addmod(
            mulmod(lambda, lambda, p),
            p - addmod(P.x, Q.x, p),
            p
        );
        uint256 yr = addmod(
            mulmod(lambda, addmod(P.x, p - xr, p), p),
            p - P.y,
            p
        );
        R = ECPoint(xr, yr);
    }

    function ecMul(
        uint256 k,
        ECPoint memory P
    ) internal pure returns (ECPoint memory R) {
        R = ECPoint(0, 0);
        ECPoint memory addend = P;
        while (k != 0) {
            if ((k & 1) != 0) R = ecAdd(R, addend);
            addend = ecAdd(addend, addend);
            k >>= 1;
        }
    }

    function modInverse(
        uint256 k,
        uint256 m
    ) internal pure returns (uint256) {
        require(m != 0, "modInverse: MODULUS_IS_ZERO");
        uint256 result;
        assembly {
            // Extended Euclidean Algorithm for modular inverse
            // s_i+1 = s_i-1 - q_i * s_i
            // t_i+1 = t_i-1 - q_i * t_i
            // r_i+1 = r_i-1 - q_i * r_i
            
            // We are solving for k * x = 1 (mod m)
            // Initialize s = [0, 1], t = [1, 0], r = [m, k]
            let s0 := 0
            let s1 := 1
            let t0 := 1
            let t1 := 0
            let r0 := m
            let r1 := k

            let temp_s := s0
            let temp_t := t0
            let temp_r := r0
            
            let q := 0
            
            // The loop condition is `r1 != 0`
            for { } iszero(iszero(r1)) { } {
                q := div(r0, r1)

                // Update r: r_i+1 = r_i-1 - q_i * r_i
                temp_r := r1
                r1 := sub(r0, mul(q, r1))
                r0 := temp_r

                // Update s: s_i+1 = s_i-1 - q_i * s_i
                temp_s := s1
                // We use signed division and check for negative values
                // to correctly handle subtraction.
                s1 := sub(s0, mul(q, s1))
                s0 := temp_s

                // Update t: t_i+1 = t_i-1 - q_i * t_i
                temp_t := t1
                // We don't actually need t for the inverse, s is enough.
                // This saves gas.
            }
            
            // After the loop, gcd(k, m) is in r0. It must be 1.
            if iszero(eq(r0, 1)) {
                revert(0, 0) // revert if not invertible
            }
            
            // The inverse is s0 mod m. s0 can be negative.
            // if s0 < 0, result = m + s0, else result = s0
            // slt(x, y) is 1 if x < y (signed), 0 otherwise.
            if slt(s0, 0) {
                result := add(m, s0)
            } {
                result := s0
            }
        }
        return result;
    }
}