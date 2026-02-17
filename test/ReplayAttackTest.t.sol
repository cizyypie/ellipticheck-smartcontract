// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";
import "../src/ECDSAVerify.sol";

/**
 * @title ReplayAttackTest
 * @notice Unit testing untuk replay attack prevention.
 *
 * Fungsi yang diuji dan check yang di-target:
 *
 * 1. TicketVerifier.verifyAccess()
 *    - line 71: block.timestamp > req.deadline → revert Expired()
 *    - line 76: usedDigest[digest] == true   → revert Replayed()
 *
 * 2. TicketNFT.markTicketAsUsed()
 *    - line 156: tickets[tokenId].isUsed == true → revert TicketAlreadyUsed()
 *
 * 3. TicketNFT._update() (transfer)
 *    - line 87: tickets[tokenId].isUsed == true  → revert CannotTransferUsedTicket()
 */
contract ReplayAttackTest is Test {
    // ========================= CONTRACTS =========================
    TicketNFT public ticketNFT;
    TicketVerifier public verifier;

    // ========================= ADDRESSES =========================
    address public organizer = makeAddr("organizer");
    uint256 public constant BUYER_PRIVATE_KEY = 0x1111111111111111111111111111111111111111111111111111111111111111;
    address public buyer;

    // ========================= STATE =========================
    uint256 public eventId;
    uint256 public ticketId;

    // ========================= SETUP =========================
    function setUp() public {
        // Deploy
        vm.startPrank(organizer);
        ticketNFT = new TicketNFT();
        verifier = new TicketVerifier(address(ticketNFT));
        ticketNFT.setVerifier(address(verifier));

        // Create event
        eventId = ticketNFT.createEvent("Concert", "2025-12-31", "Stadium", 0.1 ether, 100);
        vm.stopPrank();

        // Mint ticket
        buyer = vm.addr(BUYER_PRIVATE_KEY);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        ticketId = ticketNFT.mintTicket{value: 0.1 ether}(eventId, buyer);
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

    /// Buat request + signature yang valid untuk ticketId tertentu
    function _createValidVerification(uint256 tId, address owner, uint256 privKey, uint256 deadline)
        internal view
        returns (TicketVerifier.VerificationRequest memory, TicketVerifier.SignatureData memory)
    {
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(tId, owner, deadline, metaHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _sign(privKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: tId,
            owner: owner,
            deadline: deadline,
            metadataHash: metaHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r, s: s, Qx: Qx, Qy: Qy
        });

        return (req, sig);
    }

    // =============================================================
    // UNIT TEST: TicketVerifier.verifyAccess()
    // Target: line 71 - block.timestamp > req.deadline → Expired()
    // =============================================================

    /// @notice Positif: verifyAccess diterima selama masih sebelum deadline
    function test_verifyAccess_AcceptedBeforeDeadline() public {
        uint256 deadline = block.timestamp + 40 seconds;
        (TicketVerifier.VerificationRequest memory req, TicketVerifier.SignatureData memory sig) = _createValidVerification(ticketId, buyer, BUYER_PRIVATE_KEY, deadline);

        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result);
    }

    /// @notice Negatif: verifyAccess revert tepat saat timestamp == deadline + 1
    function test_verifyAccess_RevertExpiredAtDeadlinePlusOne() public {
        uint256 deadline = block.timestamp + 40 seconds;
        (TicketVerifier.VerificationRequest memory req, TicketVerifier.SignatureData memory sig) = _createValidVerification(ticketId, buyer, BUYER_PRIVATE_KEY, deadline);

        vm.warp(deadline + 1); // Mundur 1 detik setelah deadline

        vm.expectRevert(TicketVerifier.Expired.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice Negatif: verifyAccess revert jauh setelah deadline berlalu
    function test_verifyAccess_RevertExpiredLongAfterDeadline() public {
        uint256 deadline = block.timestamp + 40 seconds;
        (TicketVerifier.VerificationRequest memory req, TicketVerifier.SignatureData memory sig) = _createValidVerification(ticketId, buyer, BUYER_PRIVATE_KEY, deadline);

        vm.warp(deadline + 1 days); // Mundur 1 hari setelah deadline

        vm.expectRevert(TicketVerifier.Expired.selector);
        verifier.verifyAccess(req, sig);
    }

    // =============================================================
    // UNIT TEST: TicketVerifier.verifyAccess()
    // Target: line 76 - usedDigest[digest] == true → Replayed()
    // =============================================================

    /// @notice Positif: usedDigest false sebelum pertama kali verifikasi
    function test_verifyAccess_DigestUnusedBeforeFirstVerify() public {
        uint256 deadline = block.timestamp + 40 seconds;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketId, buyer, deadline, metaHash);

        // Sebelum verify, digest belum dipakai
        assertFalse(verifier.usedDigest(digest));
    }

    /// @notice Positif: usedDigest berubah true setelah verifikasi berhasil
    function test_verifyAccess_DigestMarkedUsedAfterVerify() public {
        uint256 deadline = block.timestamp + 40 seconds;
        bytes32 metaHash = keccak256("metadata");
        bytes32 digest = _buildDigest(ticketId, buyer, deadline, metaHash);

        (TicketVerifier.VerificationRequest memory req, TicketVerifier.SignatureData memory sig) = _createValidVerification(ticketId, buyer, BUYER_PRIVATE_KEY, deadline);
        verifier.verifyAccess(req, sig);

        // Setelah verify, digest harus true
        assertTrue(verifier.usedDigest(digest));
    }

    /// @notice Negatif: verifyAccess revert ketika digest yang sama dipakai kedua kali
    function test_verifyAccess_RevertReplayedOnSecondCall() public {
        uint256 deadline = block.timestamp + 40 seconds;
        (TicketVerifier.VerificationRequest memory req, TicketVerifier.SignatureData memory sig) = _createValidVerification(ticketId, buyer, BUYER_PRIVATE_KEY, deadline);

        // Pertama: berhasil
        verifier.verifyAccess(req, sig);

        // Kedua: revert Replayed
        vm.expectRevert(TicketVerifier.Replayed.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice Negatif: digest berbeda ketika metadataHash berbeda (tidak bisa dimanipulasi)
    function test_verifyAccess_DifferentMetadataProducesDifferentDigest() public {
        uint256 deadline = block.timestamp + 40 seconds;

        bytes32 digest1 = _buildDigest(ticketId, buyer, deadline, keccak256("metadata_A"));
        bytes32 digest2 = _buildDigest(ticketId, buyer, deadline, keccak256("metadata_B"));

        // Digest harus berbeda
        assertNotEq(digest1, digest2);
    }

    // =============================================================
    // UNIT TEST: TicketNFT.markTicketAsUsed()
    // Target: line 156 - tickets[tokenId].isUsed == true → TicketAlreadyUsed()
    // =============================================================

    /// @notice Positif: isUsed false sebelum ticket digunakan
    function test_markTicketAsUsed_TicketUnusedAfterMint() public {
        assertFalse(ticketNFT.isTicketUsed(ticketId));
    }

    /// @notice Positif: isUsed berubah true setelah markTicketAsUsed dipanggil
    function test_markTicketAsUsed_MarkedTrueByVerifier() public {
        vm.prank(address(verifier));
        ticketNFT.markTicketAsUsed(ticketId);

        assertTrue(ticketNFT.isTicketUsed(ticketId));
    }

    /// @notice Negatif: markTicketAsUsed revert ketika ticket sudah isUsed == true
    function test_markTicketAsUsed_RevertTicketAlreadyUsed() public {
        // Mark pertama kali
        vm.prank(address(verifier));
        ticketNFT.markTicketAsUsed(ticketId);

        // Mark kedua kali → revert
        vm.prank(address(verifier));
        vm.expectRevert(TicketNFT.TicketAlreadyUsed.selector);
        ticketNFT.markTicketAsUsed(ticketId);
    }

    // =============================================================
    // UNIT TEST: TicketNFT._update() (transfer)
    // Target: line 87 - tickets[tokenId].isUsed == true → CannotTransferUsedTicket()
    // =============================================================

    /// @notice Positif: transfer berhasil ketika ticket belum digunakan
    function test_update_TransferSuccessWhenUnused() public {
        address recipient = makeAddr("recipient");

        vm.prank(buyer);
        ticketNFT.transferFrom(buyer, recipient, ticketId);

        // Ownership pindah
        assertEq(ticketNFT.ownerOf(ticketId), recipient);
    }

    /// @notice Negatif: transfer revert ketika ticket sudah isUsed == true
    function test_update_RevertCannotTransferUsedTicket() public {
        address recipient = makeAddr("recipient");

        // Mark ticket as used
        vm.prank(address(verifier));
        ticketNFT.markTicketAsUsed(ticketId);

        // Coba transfer → revert
        vm.prank(buyer);
        vm.expectRevert(TicketNFT.CannotTransferUsedTicket.selector);
        ticketNFT.transferFrom(buyer, recipient, ticketId);
    }
}
