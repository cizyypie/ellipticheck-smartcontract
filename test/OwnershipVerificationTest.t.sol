// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";
import "../src/ECDSAVerify.sol";

/**
 * @title OwnershipVerificationTest
 * @notice  testing untuk memastikan sistem tidak bisa di-bypass dengan:
 *         - Forged signatures
 *         - Wrong owner's signature
 *         - Invalid public keys
 *         - Signature malleability
 */
contract OwnershipVerificationTest is Test {
    TicketNFT public ticketNFT;
    TicketVerifier public verifier;

    address public organizer = makeAddr("organizer");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public attacker = makeAddr("attacker");

    uint256 public buyer1PrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public buyer2PrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    uint256 public attackerPrivateKey = 0x3333333333333333333333333333333333333333333333333333333333333333;

    uint256 public eventId;
    uint256 public buyer1TicketId;
    uint256 public buyer2TicketId;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(organizer);
        ticketNFT = new TicketNFT();
        verifier = new TicketVerifier(address(ticketNFT));
        ticketNFT.setVerifier(address(verifier));

        // Create event
        eventId = ticketNFT.createEvent(
            "Test Concert",
            "2026-06-09",
            "Stadium",
            0.1 ether,
            100
        );
        vm.stopPrank();

        // Set addresses from private keys
        buyer1 = vm.addr(buyer1PrivateKey);
        buyer2 = vm.addr(buyer2PrivateKey);
        attacker = vm.addr(attackerPrivateKey);

        // Mint tickets
        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        buyer1TicketId = ticketNFT.mintTicket{value: 0.1 ether}(eventId, buyer1);

        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        buyer2TicketId = ticketNFT.mintTicket{value: 0.1 ether}(eventId, buyer2);
    }

    // ============= HELPER FUNCTIONS =============

    function _getPublicKey(uint256 privateKey) internal pure returns (uint256 Qx, uint256 Qy) {
        // secp256k1 generator point
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
        // Get public key
        (Qx, Qy) = _getPublicKey(privateKey);

        // For testing: create deterministic k (DO NOT use in production)
        uint256 k = uint256(keccak256(abi.encodePacked(digest, privateKey))) % 
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        
        if (k == 0) k = 1; // Ensure k is not zero

        // Calculate r (x-coordinate of k*G)
        uint256 Gx = 55066263022277343669578718895168534326250603453777594175500187360389116729240;
        uint256 Gy = 32670510020758816978083085130507043184471273380659243275938904335757337482424;
        ECDSAVerify.ECPoint memory kG = ECDSAVerify.ecMul(k, ECDSAVerify.ECPoint(Gx, Gy));
        r = kG.x % 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

        // Calculate s = k^-1 * (z + r*privateKey) mod n
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 kInv = _modInverse(k, n);
        uint256 z = uint256(digest);
        s = mulmod(kInv, addmod(z, mulmod(r, privateKey, n), n), n);

        // Ensure s is in lower half (anti-malleability)
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

    // ============= ATTACK TESTS =============

    /// @notice TEST 1: Attacker tries to use completely forged signature
    function test_CannotVerifyWithForgedSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("fake metadata");

        // Attacker creates random signature values
        uint256 fakeR = 12345;
        uint256 fakeS = 67890;
        uint256 fakeQx = 11111;
        uint256 fakeQy = 22222;

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: fakeR,
            s: fakeS,
            Qx: fakeQx,
            Qy: fakeQy
        });

        // Should revert - forged signature cannot pass verification
        vm.expectRevert(); // Will revert with "public key not on curve" or InvalidPublicKey
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 2: Attacker tries to steal and reuse someone else's signature
    function test_CannotUseAnotherUsersSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        // Buyer1 creates valid signature for their ticket
        bytes32 digest1 = _buildDigest(buyer1TicketId, buyer1, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyer1PrivateKey, digest1);
        
        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer2TicketId,
            owner: buyer2,  // buyer2 claiming ownership
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,  // Using buyer1's signature!
            s: s,
            Qx: Qx,  // buyer1's public key
            Qy: Qy
        });

        // Should revert - public key doesn't match buyer2's address
        vm.expectRevert(TicketVerifier.InvalidPublicKey.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 3: Attacker provides wrong public key
    function test_CannotVerifyWithWrongPublicKey() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(buyer1TicketId, buyer1, deadline, metadataHash);
        
        // Sign with buyer1's private key
        (uint256 r, uint256 s, , ) = _signMessage(buyer1PrivateKey, digest);
        
        // But provide buyer2's public key (WRONG!)
        (uint256 wrongQx, uint256 wrongQy) = _getPublicKey(buyer2PrivateKey);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: wrongQx,
            Qy: wrongQy
        });

        // Should revert - public key doesn't match owner
        vm.expectRevert(TicketVerifier.InvalidPublicKey.selector);
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 4: Signature malleability attack (high-s value)
    function test_SignatureMalleabilityPrevention() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(buyer1TicketId, buyer1, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyer1PrivateKey, digest);

        // Calculate malleable signature: s' = n - s
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 malleableS = n - s;

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: malleableS, // Using high-s value
            Qx: Qx,
            Qy: Qy
        });

        // Should revert - malleable signature rejected
        vm.expectRevert("invalid s - malleable signature");
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 5: Invalid curve point attack
    function test_CannotVerifyWithInvalidCurvePoint() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(buyer1TicketId, buyer1, deadline, metadataHash);
        (uint256 r, uint256 s, , ) = _signMessage(buyer1PrivateKey, digest);

        // Create point NOT on the curve
        uint256 invalidX = 1;
        uint256 invalidY = 1;

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: invalidX,
            Qy: invalidY
        });

        // Should revert - point not on curve (can be either error message)
        vm.expectRevert();  // Accept any revert
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 6: Zero signature values
    function test_CannotVerifyWithZeroSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        (uint256 Qx, uint256 Qy) = _getPublicKey(buyer1PrivateKey);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: 0, // ZERO!
            s: 0, // ZERO!
            Qx: Qx,
            Qy: Qy
        });

        // Should revert - invalid r or s
        vm.expectRevert("invalid r");
        verifier.verifyAccess(req, sig);
    }

    /// @notice TEST 7: Valid signature verification (baseline)
    function test_ValidSignaturePassesVerification() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("metadata");

        bytes32 digest = _buildDigest(buyer1TicketId, buyer1, deadline, metadataHash);
        (uint256 r, uint256 s, uint256 Qx, uint256 Qy) = _signMessage(buyer1PrivateKey, digest);

        TicketVerifier.VerificationRequest memory req = TicketVerifier.VerificationRequest({
            ticketId: buyer1TicketId,
            owner: buyer1,
            deadline: deadline,
            metadataHash: metadataHash
        });

        TicketVerifier.SignatureData memory sig = TicketVerifier.SignatureData({
            r: r,
            s: s,
            Qx: Qx,
            Qy: Qy
        });

        // Should succeed
        bool result = verifier.verifyAccess(req, sig);
        assertTrue(result, "Valid signature should pass");

        // Verify ticket is marked as used
        assertTrue(ticketNFT.isTicketUsed(buyer1TicketId), "Ticket should be marked as used");
    }
}
