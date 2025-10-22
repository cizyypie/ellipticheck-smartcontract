// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketVerifier.sol";
import "../src/TicketNFT.sol";

/// @title VerifierTest
/// @notice Pengujian EIP-712 + ECDSA di kontrak TicketVerifier.sol
contract VerifierTest is Test {
    TicketVerifier verifier;
    TicketNFT ticketNFT;
    uint256 issuerPk;
    address issuer;

    function setUp() public {
        issuerPk = uint256(0xA11CE); // contoh private key issuer
        issuer = vm.addr(issuerPk);  // hasil address issuer

        // 🚀 Deploy kontrak NFT dulu
        vm.startPrank(issuer);
        ticketNFT = new TicketNFT("ElliptiTicket", "ETKT");
        verifier = new TicketVerifier("ElliptiCheck", "1", address(ticketNFT));
        vm.stopPrank();

        // 🧾 Mint contoh tiket ke owner dummy (biar ownerOf() valid)
        address owner = address(0xBEEF);
        vm.prank(issuer);
        ticketNFT.mintTicket(owner, 1, keccak256("meta"));
    }

    // Fungsi bantu digest EIP-712
    function _digest(
        uint256 ticketId,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 metadataHash
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                verifier.TICKET_ACCESS_TYPEHASH(),
                ticketId,
                owner,
                nonce,
                deadline,
                metadataHash
            )
        );
        return keccak256(
            abi.encodePacked("\x19\x01", verifier.DOMAIN_SEPARATOR(), structHash)
        );
    }

    function test_VerifyValidThenReplay() public {
        uint256 ticketId = 1;
        address owner = address(0xBEEF);
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 3600;
        bytes32 metadataHash = keccak256("meta");

        bytes32 digest = _digest(ticketId, owner, nonce, deadline, metadataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        bool ok = verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
        assertTrue(ok, "Signature valid must pass");

        vm.expectRevert(bytes("replayed"));
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
    }

    function test_Expired() public {
        uint256 ticketId = 1;
        address owner = address(0xBEEF);
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 5;
        bytes32 metadataHash = keccak256("meta");

        bytes32 digest = _digest(ticketId, owner, nonce, deadline, metadataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(deadline + 1);
        vm.expectRevert(bytes("expired"));
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
    }
}
