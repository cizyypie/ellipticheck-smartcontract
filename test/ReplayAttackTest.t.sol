// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";
import "../src/ECDSAVerify.sol";

/**
 * @title ReplayAttackTest
 * @notice Penetration testing untuk memastikan sistem mencegah:
 *         - Basic replay attack (menggunakan QR yang sama 2x)
 *         - Deadline expiration bypass
 *         - Concurrent verification (race condition)
 *         - Cross-event replay
 *         - Digest reuse attack
 */
contract ReplayAttackTest is Test {
    TicketNFT public ticketNFT;
    TicketVerifier public verifier;

    address public organizer = makeAddr("organizer");
    address public buyer = makeAddr("buyer");
    address public verifier1 = makeAddr("verifier1");
    address public verifier2 = makeAddr("verifier2");

    uint256 public buyerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;

    uint256 public eventId1;
    uint256 public eventId2;
    uint256 public ticketId1;
    uint256 public ticketId2;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(organizer);
        ticketNFT = new TicketNFT();
        verifier = new TicketVerifier(address(ticketNFT));
        ticketNFT.setVerifier(address(verifier));

        // Create two events
        eventId1 = ticketNFT.createEvent(
            "Concert A",
            "2025-12-31",
            "Stadium A",
            0.1 ether,
            100
        );

        eventId2 = ticketNFT.createEvent(
            "Concert B",
            "2025-12-31",
            "Stadium B",
            0.1 ether,
            100
        );
        vm.stopPrank();

        // Set buyer address from private key
        buyer = vm.addr(buyerPrivateKey);

        // Mint tickets for both events
        vm.deal(buyer, 1 ether);
        
        vm.startPrank(buyer);
        ticketId1 = ticketNFT.mintTicket{value: 0.1 ether}(eventId1, buyer);
        ticketId2 = ticketNFT.mintTicket{value: 0.1 ether}(eventId2, buyer);
        vm.stopPrank();
    }

    // ============= HELPER FUNCTIONS =============

    function _getPublicKey(uint256 privateKey) internal pure returns (uint256 Qx, uint256 Qy) {
        uint256 Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240;
        uint256 Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424;

        ECDSAVerify.ECPoint memory G = ECDSAVerify.ECPoint(Gx, Gy);
        ECDSAVerify.ECPoint memory Q = ECDSAVerify.ecMul(privateKey, G);
        
        return (Q.x, Q.y);
    }

    function _signMessage(uint256 privateKey, bytes32 digest) 
        internal 
        pure 
        returns (uint256 r, uint256 s, uint256 Qx, uint256 Qy) 
    {
        (Qx, Qy) = _getPublicKey(privateKey);

        uint256 k = uint256(keccak256(abi.encodePacked(digest, privateKey))) % 
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        
        if (k == 0) k = 1;

        uint256 Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240;
        uint256 Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424;
        ECDSAVerify.ECPoint memory kG = ECDSAVerify.ecMul(k, ECDSAVerify.ECPoint(Gx, Gy));
        r = kG.x % 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 kInv = _modInverse(k, n);
        uint256 z = uint256(digest);
        s = mulmod(kInv, addmod(z, mulmod(r, privateKey, n), n), n);

        uint256 HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
        if (s > HALF_N) {
            s = n - s;
        }

        return (r, s, Qx, Qy);
    }

    function _modInverse(uint256 a, uint256 m) internal pure returns (uint256) {
        return _modExp(a, m - 2, m);
    }

    function _modExp(uint256 base, uint256 exponent, uint256 modulus) internal pure returns (uint256 result) {
        result = 1;
        base = base % modulus;
        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = mulmod(result, base, modulus);
            }
            exponent = exponent >> 1;
            base = mulmod(base, base, modulus);
        }
        return result;
    }

    function _buildDigest(
        uint256 ticketId,
        address owner,
        uint256 deadline,
        bytes32 metadataHash
    ) internal view returns (bytes32) {
        bytes32 TYPEHASH = keccak256(
            "TicketAccess(uint256 ticketId,address owner,uint256 deadline,bytes32 metadataHash)"
        );

        bytes32 structHash = keccak256(
            abi.encode(TYPEHASH, ticketId, owner, deadline, metadataHash)
        );

        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                verifier.DOMAIN_SEPARATOR(),
                structHash
            )
        );
    }

    // ============= REPLAY ATTACK TESTS =============

    /// @notice TEST 1: Basic replay attack - use same QR twice
    function test_CannotReplayUsedTicket() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // First verification - should succeed
        bool result1 = verifier.verifyAccess(req, sig);
        assertTrue(result1, "First verification should succeed");

        // Second verification with SAME signature - should FAIL (Replayed)
        vm.expectRevert(TicketVerifier.Replayed.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 2: Expired signature should be rejected
    function test_ExpiredSignatureRejected() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Fast forward past deadline
        vm.warp(deadline + 1);

        // Should revert - expired
        vm.expectRevert(TicketVerifier.Expired.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 3: Concurrent verification race condition
    function test_RaceConditionPrevention() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Simulate two verifiers trying to verify simultaneously
        // First one succeeds
        vm.prank(verifier1);
        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result, "First verifier should succeed");

        // Second one should fail (digest already used)
        vm.prank(verifier2);
        vm.expectRevert(TicketVerifier.Replayed.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 4: Cannot reuse digest across different tickets
    function test_CannotReuseSameDigestForDifferentTickets() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        // Use SAME digest structure for two different tickets
        bytes32 digest1 = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest1);

        TicketVerifier.VerificationRequest memory req1 = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Verify first ticket
        bool result = verifier.verifyAccess(req1, sig);
        assertTrue(result, "First ticket verification should succeed");

        // Try to reuse SAME signature for different ticket (even if digest is different)
        // This should fail because ticketId is different, thus digest is different
        bytes32 digest2 = _buildDigest(ticketId2, buyer, deadline, metadataHash);
        
        // The digest will be different, so signature will be invalid
        TicketVerifier.VerificationRequest memory req2 = TicketVerifier.VerificationRequest({
            ticketId: ticketId2,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        // Should revert - signature invalid for different ticket
        vm.expectRevert(TicketVerifier.InvalidSignature.selector);
        verifier.verifyAccess(req2, sig);
    }

    /// @notice TEST 5: Cannot verify ticket that's already marked as used
    function test_CannotVerifyAlreadyUsedTicket() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // First verification
        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result);

        // Verify ticket is now marked as used in TicketNFT
        assertTrue(ticketNFT.isTicketUsed(ticketId1), "Ticket should be marked as used");

        // Create NEW signature with DIFFERENT metadata (to bypass digest check)
        bytes32 newMetadataHash = keccak256("new metadata");
        bytes32 newDigest = _buildDigest(ticketId1, buyer, deadline, newMetadataHash);
        (uint256 r2, uint256 s2, uint256 Qx2, uint256 Qy2) = _signMessage(buyerPrivateKey, newDigest);

        TicketVerifier.VerificationRequest memory newReq = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: newMetadataHash
        });

        TicketVerifier.SignatureData memory newSig = TicketVerifier.SignatureData({
            r: r2,
            s: s2,
            Qx: Qx2,
            Qy: Qy2
        });

        // Should fail because ticket is already used
        // Note: This will fail at markTicketAsUsed with TicketAlreadyUsed error
        vm.expectRevert();
        verifier.verifyAccess(newReq, newSig);
    }

    /// @notice TEST 6: Different metadata creates different digest (anti-collision)
    function test_DifferentMetadataCreatesDifferentDigest() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadata1 = keccak256("metadata1");
        bytes32 metadata2 = keccak256("metadata2");

        bytes32 digest1 = _buildDigest(ticketId1, buyer, deadline, metadata1);
        bytes32 digest2 = _buildDigest(ticketId1, buyer, deadline, metadata2);

        // Digests should be different
        assertTrue(digest1 != digest2, "Different metadata should produce different digests");
    }

    /// @notice TEST 7: Verify usedDigest mapping is properly tracked
    function test_UsedDigestMappingTracking() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Before verification, digest should not be used
        assertFalse(verifier.usedDigest(digest), "Digest should not be used before verification");

        // Verify
        verifier.verifyAccess(req, sig);

        // After verification, digest should be marked as used
        assertTrue(verifier.usedDigest(digest), "Digest should be marked as used after verification");
    }

    /// @notice TEST 8: Time-based replay - verify at different times with same signature
    function test_CannotReuseSignatureAfterDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(ticketId1, buyer, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyerPrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: ticketId1,
            owner: buyer,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Verify before deadline - should succeed
        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result, "Verification before deadline should succeed");

        // Warp to after deadline
        vm.warp(deadline + 1);

        // Create new ticket for testing
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 newTicketId = ticketNFT.mintTicket{value: 0.1 ether}(eventId1, buyer);

        // Try to use similar signature structure after deadline
        bytes32 newDigest = _buildDigest(newTicketId, buyer, deadline, metadataHash);
        (uint256 r2, uint256 s2, uint256 Qx2, uint256 Qy2) = _signMessage(buyerPrivateKey, newDigest);

        TicketVerifier.VerificationRequest memory newReq = TicketVerifier.VerificationRequest({
            ticketId: newTicketId,
            owner: buyer,
            deadline: deadline, // Same old deadline
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory newSig = TicketVerifier.SignatureData({
            r: r2,
            s: s2,
            Qx: Qx2,
            Qy: Qy2
        });

        // Should revert - expired deadline
        vm.expectRevert(TicketVerifier.Expired.selector);
        verifier.verifyAccess(newReq, newSig);
    }
}
