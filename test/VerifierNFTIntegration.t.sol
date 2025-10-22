// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TicketNFT} from "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";

// @title VerifierNFTIntegrationTest
// @notice Integration tests ensuring NFT ownership is enforced alongside EIP-712 verification.
// @dev Mirrors off-chain signing flow described in the thesis to validate on-chain checks.
contract VerifierNFTIntegrationTest is Test {
    TicketVerifier internal verifier;
    TicketNFT internal ticketNFT;

    uint256 internal issuerPk;
    address internal issuer;
    address internal user;

    uint256 internal constant TICKET_ID = 1;
    bytes32 internal constant METADATA_HASH = keccak256("meta");

   function setUp() public {
    issuerPk = uint256(0xA11CE); // deterministic issuer private key for reproducible signatures
    issuer = vm.addr(issuerPk);
    user = address(0xBEEF); // ticket holder under test

    vm.startPrank(issuer);
    // Di baris ini, nama dan simbol diperlukan oleh constructor ERC721
    ticketNFT = new TicketNFT("Ticket", "TKT"); 
    
    // PERBAIKAN: Tambahkan METADATA_HASH di sini
    ticketNFT.mintTicket(user, TICKET_ID, METADATA_HASH); 

    // Constructor TicketVerifier Anda juga sepertinya membutuhkan 3 argumen
    verifier = new TicketVerifier("ElliptiCheck", "1", address(ticketNFT));
    vm.stopPrank();
}

    // @notice Builds the EIP-712 digest that must be signed by the issuer.
    // @dev Uses verifier storage for DOMAIN_SEPARATOR and TYPEHASH to stay aligned with contract state.
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
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    verifier.DOMAIN_SEPARATOR(),
                    structHash
                )
            );
    }

    // @notice Happy-path where the NFT owner presents a fresh signature before the deadline.
    function test_VerifyValidOwner() public {
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _digest(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool verified = verifier.verifyAccess(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH,
            signature
        );
        assertTrue(
            verified,
            "owner with valid NFT and signature must be accepted"
        );
    }

    // @notice Ensures signatures fail when the caller does not hold the corresponding NFT.
    function test_InvalidOwnerShouldRevert() public {
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 days;
        address impostor = address(0xCAFE);

        bytes32 digest = _digest(
            TICKET_ID,
            impostor,
            nonce,
            deadline,
            METADATA_HASH
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(bytes("not owner"));
        verifier.verifyAccess(
            TICKET_ID,
            impostor,
            nonce,
            deadline,
            METADATA_HASH,
            signature
        );
    }

    /// @notice Confirms replay protection still blocks reuse of the same signed payload.
    function test_ReplayStillFails() public {
        uint256 nonce = 3;
        uint256 deadline = block.timestamp + 2 hours;

        bytes32 digest = _digest(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

       verifier.verifyAccess(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH,
            signature
        );
        vm.expectRevert(bytes("replayed"));
        verifier.verifyAccess(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH,
            signature
        );
    }

    /// @notice Validates that expired permits continue to revert even with valid ownership.
    function test_ExpiredSignatureShouldRevert() public {
        uint256 nonce = 4;
        uint256 deadline = block.timestamp + 10;

        bytes32 digest = _digest(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.warp(deadline + 1); // fast-forward past the allowed window

        vm.expectRevert(bytes("expired"));
        verifier.verifyAccess(
            TICKET_ID,
            user,
            nonce,
            deadline,
            METADATA_HASH,
            signature
        );
    }
}
