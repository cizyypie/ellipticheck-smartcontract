// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ECDSAVerify
/// @notice Implementasi manual algoritma ECDSA (secp256k1) untuk verifikasi tanda tangan digital
/// @dev Library untuk verifikasi signature dengan curve secp256k1
library ECDSAVerify {
    // KONSTANTA KURVA ELIPTIK SECP256K1
    uint256 constant a = 0;
    uint256 constant b = 7;
    uint256 constant p =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant n =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // ADD: Half curve order for malleability protection
    uint256 constant HALF_N =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    uint256 constant Gx =
        55066263022277343669578718895168534326250603453777594175500187360389116729240;
    uint256 constant Gy =
        32670510020758816978083085130507043184471273380659243275938904335757337482424;

    struct ECPoint {
        uint256 x;
        uint256 y;
    }

    /// @notice Verifikasi signature ECDSA secara matematis
    /// @param z Hash pesan (digest dalam bentuk uint256)
    /// @param r Komponen r dari signature
    /// @param s Komponen s dari signature
    /// @param Q Public key dari penandatangan
    /// @return valid True jika signature valid
    function ecdsaverify(
        uint256 z,
        uint256 r,
        uint256 s,
        ECPoint memory Q
    ) internal pure returns (bool valid) {
        require(r > 0 && r < n, "invalid r");

        // Restrict s to lower half of curve to prevent signature malleability
        require(s > 0 && s <= HALF_N, "invalid s - malleable signature");

        require(isOnCurve(Q), "public key not on curve");

        // 1. Hitung s⁻¹ (mod n)
        uint256 sInv = modInverse(s, n);

        // 2. Hitung u1 = z·s⁻¹ mod n, u2 = r·s⁻¹ mod n
        uint256 u1 = mulmod(z, sInv, n);
        uint256 u2 = mulmod(r, sInv, n);

        // 3. Hitung titik R = u1·G + u2·Q
        ECPoint memory R = ecAdd(ecMul(u1, ECPoint(Gx, Gy)), ecMul(u2, Q));

        if (R.x == 0 && R.y == 0) return false;

        // 4. Signature valid jika Rx mod n == r
        return (addmod(R.x, 0, n) == r);
    }

    /// @notice Konversi public key (x,y) ke address Ethereum
    /// @dev Address = last 20 bytes of keccak256(x || y)
    /// @param Q Public key dalam bentuk ECPoint
    /// @return addr Address Ethereum yang sesuai
    function publicKeyToAddress(
        ECPoint memory Q
    ) internal pure returns (address addr) {
        bytes32 hash = keccak256(abi.encodePacked(Q.x, Q.y));
        addr = address(uint160(uint256(hash)));
    }

    /// @notice Cek apakah titik Q berada di kurva y² = x³ + 7 (mod p)
    function isOnCurve(ECPoint memory Q) internal pure returns (bool) {
        if (Q.x == 0 && Q.y == 0) return false;
        if (Q.x >= p || Q.y >= p) return false;

        uint256 lhs = mulmod(Q.y, Q.y, p);
        uint256 rhs = addmod(mulmod(mulmod(Q.x, Q.x, p), Q.x, p), b, p);
        return lhs == rhs;
    }

    /// @notice Penjumlahan titik di kurva eliptik
    function ecAdd(
        ECPoint memory P,
        ECPoint memory Q
    ) internal pure returns (ECPoint memory R) {
        if (P.x == 0 && P.y == 0) return Q;
        if (Q.x == 0 && Q.y == 0) return P;
        if (P.x == Q.x && addmod(P.y, Q.y, p) == 0) return ECPoint(0, 0);

        uint256 lambda;

        if (P.x == Q.x && P.y == Q.y) {
            // Point doubling
            if (P.y == 0) return ECPoint(0, 0);
            uint256 twoPy = addmod(P.y, P.y, p);
            if (twoPy == 0) return ECPoint(0, 0);
            uint256 num = mulmod(3, mulmod(P.x, P.x, p), p);
            uint256 den = modInverse(twoPy, p);
            lambda = mulmod(num, den, p);
        } else {
            // Point addition
            uint256 diffX = addmod(Q.x, p - P.x, p);
            if (diffX == 0) return ECPoint(0, 0);
            uint256 num = addmod(Q.y, p - P.y, p);
            uint256 den = modInverse(diffX, p);
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

    /// @notice Perkalian skalar (double-and-add)
    function ecMul(
        uint256 k,
        ECPoint memory P
    ) internal pure returns (ECPoint memory R) {
        k = k % n;
        R = ECPoint(0, 0);
        ECPoint memory addend = P;

        while (k != 0) {
            if ((k & 1) != 0) {
                R = ecAdd(R, addend);
            }
            addend = ecAdd(addend, addend);
            k >>= 1;
        }
    }

    /// @notice Modular inverse (Fermat's Little Theorem)
    function modInverse(uint256 k, uint256 m) internal pure returns (uint256) {
        require(m != 0, "modInverse: MODULUS_IS_ZERO");
        require(k % m != 0, "modInverse: NOT_INVERTIBLE");
        return modExp(k, m - 2, m);
    }

    /// @notice Modular exponentiation
    function modExp(
        uint256 base,
        uint256 e,
        uint256 m
    ) private pure returns (uint256 result) {
        result = 1 % m;
        uint256 baseModM = base % m;
        while (e != 0) {
            if ((e & 1) != 0) result = mulmod(result, baseModM, m);
            baseModM = mulmod(baseModM, baseModM, m);
            e >>= 1;
        }
    }
}
