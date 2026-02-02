// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";
import "../src/ECDSAVerify.sol";

/**
 * @title UnauthorizedAcceptanceTest
 * @notice Unit testing untuk unauthorized acceptance prevention.
 *
 * Fungsi yang diuji dan check yang di-target:
 *
 * 1. TicketVerifier.verifyAccess()
 *    - line 72: ownerOf(ticketId) != req.owner → revert NotOwner()
 *
 * 2. TicketVerifier._verifySignature()
 *    - line 122: publicKeyToAddress(Q) != owner → revert InvalidPublicKey()
 *
 * 3. ECDSAVerify.ecdsaverify()
 *    - line 42: r == 0 || r >= n           → revert "invalid r"
 *    - line 45: s == 0 || s > HALF_N       → revert "invalid s - malleable signature"
 *    - line 47: isOnCurve(Q) == false      → revert "public key not on curve"
 *
 * 4. TicketNFT.markTicketAsUsed()
 *    - line 155: msg.sender != verifier    → revert Unauthorized()
 */
contract UnauthorizedAcceptanceTest is Test {
    // ========================= CONTRACTS =========================
    TicketNFT public ticketNFT;
    TicketVerifier public verifier;

    // ========================= ADDRESSES =========================
    address public organizer = makeAddr("organizer");

    uint256 public constant BUYER_A_KEY = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public constant BUYER_B_KEY = 0x2222222222222222222222222222222222222222222222222222222222222222;
    address public buyerA;
    address public buyerB;

    // ========================= STATE =========================
    uint256 public eventId;
    uint256 public ticketA; // milik buyerA
    uint256 public ticketB; // milik buyerB

    // ========================= SETUP =========================
    function setUp() public {
        // Deploy
        vm.startPrank(organizer);
        ticketNFT = new TicketNFT();
        verifier = new TicketVerifier(address(ticketNFT));
        ticketNFT.setVerifier(address(verifier));

        eventId = ticketNFT.createEvent("Concert", "2025-12-31", "Stadium", 0.1 ether, 100);
        vm.stopPrank();

        // Mint tickets
        buyerA = vm.addr(BUYER_A_KEY);
        buyerB = vm.addr(BUYER_B_KEY);

        vm.deal(buyerA, 1 ether);
        vm.prank(buyerA);
        ticketA = ticketNFT.mintTicket{value: 0.1 ether}(eventId, buyerA);

        vm.deal(buyerB, 1 ether);
        vm.prank(buyerB);
        ticketB = ticketNFT.mintTicket{value: 0.1 ether}(eventId, buyerB);
    }

    // ========================= HELPERS =========================

    function _getPublicKey(uint256 privKey) internal pure returns (uint256 Qx, uint256 Qy) {
        ECDSAVerify.ECPoint memory G = ECDSAVerify.ECPoint(
            55066263022277343669578718895168534326250603453777594175500187360389116729240,
            32670510020758816978083085130507043184471273380659243275938904335757337482424
        );
        ECDSAVerify.ECPoint memory Q = ECDSAVerify.ecMul(privKey, G);
        return (Q.x, Q.y);
    }

    function _sign(uint256 privKey, bytes32 digest) internal pure returns (uint256 r, uint256 s, uint256 Qx, uint256 Qy) {
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

        (Qx, Qy) = _getPublicKey(privKey);

        uint256 k = uint256(keccak256(abi.encodePacked(digest, privKey))) % n;
        if (k == 0) k = 1;

        ECDSAVerify.ECPoint memory kG = ECDSAVerify.ecMul(k, ECDSAVerify.ECPoint(
            55066263022277343669578718895168534326250603453777594175500187360389116729240,
            32670510020758816978083085130507043184471273380659243275938904335757337482424
        ));
        r = kG.x % n;

        uint256 kInv = _modExp(k, n - 2, n);
        s = mulmod(kInv, addmod(uint256(digest), mulmod(r, privKey, n), n), n);
        if (s > HALF_N) s = n - s;
    }

    function _modExp(uint256 base, uint256 exp, uint256 mod) internal pure returns (uint256 result) {
        result = 1;
        base = base % mod;
        while (exp > 0) {
            if (exp % 2 == 1) result = mulmod(result, base, mod);
            exp >>= 1;
            base = mulmod(base, base, mod);
        }
    }

    function _buildDigest(uint256 tId, address owner, uint256 deadline, bytes32 metaHash) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("TicketAccess(uint256 ticketId,address owner,uint256 deadline,bytes32 metadataHash)"),
            tId, owner, deadline, metaHash
        ));
        return keccak256(abi.encodePacked("\x19\x01", verifier.DOMAIN_SEPARATOR(), structHash));
    }

    // =============================================================
    // UNIT TEST: TicketVerifier.verifyAccess()
    // Target: line 72 - ownerOf(ticketId) != req.owner → NotOwner()
    // =============================================================

    /// @notice Positif: verifyAccess diterima ketika req.owner == ownerOf(ticketId)
    function test_verifyAccess_AcceptedWhenOwnerMatches() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketA, buyerA, deadline, metaHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _sign(BUYER_A_KEY, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,  // buyerA == ownerOf(ticketA) ✅
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r, s: s, Qx: Qx, Qy: Qy
        });

        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result);
    }

    /// @notice Negatif: verifyAccess revert ketika req.owner bukan ownerOf(ticketId)
    function test_verifyAccess_RevertNotOwnerWhenOwnerMismatch() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");

        // Sign dengan buyerB tapi claim ticketA (milik buyerA)
        bytes32 digest = _buildDigest(ticketA, buyerB, deadline, metaHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _sign(BUYER_B_KEY, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerB,   // buyerB != ownerOf(ticketA) ❌
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r, s: s, Qx: Qx, Qy: Qy
        });

        vm.expectRevert(TicketVerifier.NotOwner.selector);
        verifier.verifyAccess(req, sig);
    }

    // =============================================================
    // UNIT TEST: TicketVerifier._verifySignature()
    // Target: line 122 - publicKeyToAddress(Q) != owner → InvalidPublicKey()
    // =============================================================

    /// @notice Positif: verifyAccess diterima ketika public key sesuai owner
    function test_verifySignature_AcceptedWhenPublicKeyMatchesOwner() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketA, buyerA, deadline, metaHash);

        // Sign dengan BUYER_A_KEY → public key dari buyerA
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _sign(BUYER_A_KEY, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r, s: s, Qx: Qx, Qy: Qy  // Public key = buyerA ✅
        });

        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result);
    }

    /// @notice Negatif: verifyAccess revert ketika public key dari private key yang berbeda
    function test_verifySignature_RevertInvalidPublicKeyWhenKeyMismatch() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketA, buyerA, deadline, metaHash);

        // Sign dengan BUYER_A_KEY untuk r, s
        (uint256 r, uint256 s, , ) = _sign(BUYER_A_KEY, digest);

        // Tapi pakai public key dari BUYER_B_KEY
        (uint256 wrongQx, uint256 wrongQy) = _getPublicKey(BUYER_B_KEY);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r, s: s,
            Qx: wrongQx, Qy: wrongQy  // Public key = buyerB ❌
        });

        vm.expectRevert(TicketVerifier.InvalidPublicKey.selector);
        verifier.verifyAccess(req, sig);
    }

    // =============================================================
    // UNIT TEST: ECDSAVerify.ecdsaverify()
    // Target: line 42 - r == 0 || r >= n → "invalid r"
    // =============================================================

    /// @notice Negatif: verifyAccess revert ketika r == 0
    function test_ecdsaverify_RevertInvalidRWhenZero() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");

        (uint256 Qx, uint256 Qy) = _getPublicKey(BUYER_A_KEY);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: 0,           // r == 0 ❌
            s: 12345,
            Qx: Qx, Qy: Qy
        });

        vm.expectRevert("invalid r");
        verifier.verifyAccess(req, sig);
    }

    /// @notice Negatif: verifyAccess revert ketika r >= n (curve order)
    function test_ecdsaverify_RevertInvalidRWhenGeN() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

        (uint256 Qx, uint256 Qy) = _getPublicKey(BUYER_A_KEY);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: n,           // r == n ❌
            s: 12345,
            Qx: Qx, Qy: Qy
        });

        vm.expectRevert("invalid r");
        verifier.verifyAccess(req, sig);
    }

    // =============================================================
    // UNIT TEST: ECDSAVerify.ecdsaverify()
    // Target: line 45 - s == 0 || s > HALF_N → "invalid s - malleable signature"
    // =============================================================

    /// @notice Negatif: verifyAccess revert ketika s == 0
    function test_ecdsaverify_RevertInvalidSWhenZero() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");

        (uint256 Qx, uint256 Qy) = _getPublicKey(BUYER_A_KEY);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: 12345,
            s: 0,           // s == 0 ❌
            Qx: Qx, Qy: Qy
        });

        vm.expectRevert("invalid s - malleable signature");
        verifier.verifyAccess(req, sig);
    }

    /// @notice Negatif: verifyAccess revert ketika s > HALF_N (signature malleability)
    function test_ecdsaverify_RevertInvalidSWhenAboveHalfN() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketA, buyerA, deadline, metaHash);

        // Sign valid dulu untuk dapatkan s yang benar
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _sign(BUYER_A_KEY, digest);

        // Flip s → n - s (selalu > HALF_N)
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 malleableS = n - s;

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig2 = TicketVerifier.SignatureData({
            r: r,
            s: malleableS,  // s > HALF_N ❌
            Qx: Qx, Qy: Qy
        });

        vm.expectRevert("invalid s - malleable signature");
        verifier.verifyAccess(req, sig2);
    }

    // =============================================================
    // UNIT TEST: ECDSAVerify.ecdsaverify()
    // Target: line 47 - isOnCurve(Q) == false → "public key not on curve"
    // =============================================================

    /// @notice Negatif: verifyAccess revert ketika Q bukan titik di curve secp256k1
    function test_ecdsaverify_RevertNotOnCurveWhenInvalidPoint() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: 12345,
            s: 67890,
            Qx: 1,          // (1, 1) bukan titik di secp256k1 ❌
            Qy: 1
        });

        // Revert bisa "public key not on curve" atau InvalidPublicKey
        // tergantung urutan check — pakai expectRevert() tanpa selector
        vm.expectRevert();
        verifier.verifyAccess(req, sig);
    }

    /// @notice Negatif: verifyAccess revert ketika Q == (0, 0) (point at infinity)
    function test_ecdsaverify_RevertNotOnCurveWhenZeroPoint() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metaHash = keccak256("metadata");

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketA,
            owner: buyerA,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: 12345,
            s: 67890,
            Qx: 0,          // (0, 0) = point at infinity ❌
            Qy: 0
        });

        vm.expectRevert();
        verifier.verifyAccess(req, sig);
    }

    // =============================================================
    // UNIT TEST: TicketNFT.markTicketAsUsed()
    // Target: line 155 - msg.sender != verifier → Unauthorized()
    // =============================================================

    /// @notice Positif: markTicketAsUsed berhasil ketika dipanggil dari address verifier
    function test_markTicketAsUsed_AcceptedWhenCalledByVerifier() public {
        vm.prank(address(verifier)); // msg.sender == verifier ✅
        ticketNFT.markTicketAsUsed(ticketA);

        assertTrue(ticketNFT.isTicketUsed(ticketA));
    }

    /// @notice Negatif: markTicketAsUsed revert ketika dipanggil dari address bukan verifier
    function test_markTicketAsUsed_RevertUnauthorizedWhenCalledByOther() public {
        address randomCaller = makeAddr("random");

        vm.prank(randomCaller); // msg.sender != verifier ❌
        vm.expectRevert(TicketNFT.Unauthorized.selector);
        ticketNFT.markTicketAsUsed(ticketA);
    }

    /// @notice Negatif: markTicketAsUsed revert ketika dipanggil dari owner (bukan verifier)
    function test_markTicketAsUsed_RevertUnauthorizedWhenCalledByOwner() public {
        vm.prank(buyerA); // msg.sender == buyerA (owner), bukan verifier ❌
        vm.expectRevert(TicketNFT.Unauthorized.selector);
        ticketNFT.markTicketAsUsed(ticketA);
    }

    /// @notice Negatif: markTicketAsUsed revert ketika dipanggil dari organizer (bukan verifier)
    function test_markTicketAsUsed_RevertUnauthorizedWhenCalledByOrganizer() public {
        vm.prank(organizer); // msg.sender == organizer, bukan verifier ❌
        vm.expectRevert(TicketNFT.Unauthorized.selector);
        ticketNFT.markTicketAsUsed(ticketA);
    }
}
