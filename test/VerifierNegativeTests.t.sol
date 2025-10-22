// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TicketVerifier} from "../src/TicketVerifier.sol";
import {TicketNFT} from "../src/TicketNFT.sol";

/// @title VerifierNegativeTests
/// @notice Pengujian cabang logika gagal untuk meningkatkan branch coverage.
contract VerifierNegativeTests is Test {
    TicketVerifier internal verifier;
    TicketNFT internal nft;

    // --- State Variables ---
    uint256 internal issuerPk;
    address internal issuer;
    address internal owner;

    uint256 internal constant TICKET_ID = 1;
    bytes32 internal constant METADATA_HASH = keccak256("ConcertTicket");

    // --- Setup ---
    function setUp() public {
        issuerPk = uint256(0xA11CE);
        issuer = vm.addr(issuerPk);
        owner = address(0xBEEF);

        nft = new TicketNFT("ElliptiCheck NFT", "ECT");

        // !! PERBAIKAN UTAMA DI SINI !!
        // Kita "menjadi" issuer SEBELUM membuat kontrak Verifier.
        vm.prank(issuer);

        // Sekarang, saat Verifier dibuat, `msg.sender`-nya adalah `issuer`.
        // Kontrak Verifier akan mencatat `issuer` sebagai pemilik/issuer yang sah.
        verifier = new TicketVerifier("ElliptiCheck", "1", address(nft));

        // Hentikan prank setelah selesai membuat verifier.
        vm.stopPrank();

        // Transfer kepemilikan NFT ke issuer agar ia bisa minting.
        nft.transferOwnership(issuer);

        // Minta issuer untuk minting tiket.
        vm.prank(issuer);
        nft.mintTicket(owner, TICKET_ID, METADATA_HASH);
        vm.stopPrank();
    }

    // --- Helper Function ---
    function _digest(
        uint256 ticketId,
        address ticketOwner,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                verifier.TICKET_ACCESS_TYPEHASH(),
                ticketId,
                ticketOwner,
                nonce,
                deadline,
                METADATA_HASH
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

    // --- Negative Tests ---

    function test_InvalidSignatureShouldRevert() public {
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;

        uint256 impostorPk = uint256(0xDEAD);
        bytes32 digest = _digest(TICKET_ID, owner, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(impostorPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        // !! PERBAIKAN TEKS ERROR !!
        // Sesuaikan dengan error yang sebenarnya dilempar oleh kontrak.
        vm.expectRevert(bytes("invalid signer"));
        verifier.verifyAccess(
            TICKET_ID,
            owner,
            nonce,
            deadline,
            METADATA_HASH,
            badSig
        );
    }

    function test_ReplayShouldRevert() public {
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _digest(TICKET_ID, owner, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory validSig = abi.encodePacked(r, s, v);

        // Panggilan pertama sekarang akan BERHASIL karena `issuer` sudah dikenali.
        verifier.verifyAccess(
            TICKET_ID,
            owner,
            nonce,
            deadline,
            METADATA_HASH,
            validSig
        );

        // Panggilan kedua akan GAGAL dengan benar karena replay.
        vm.expectRevert(bytes("replayed"));
        verifier.verifyAccess(
            TICKET_ID,
            owner,
            nonce,
            deadline,
            METADATA_HASH,
            validSig
        );
    }

    function test_ExpiredDeadlineShouldRevert() public {
        uint256 nonce = 3;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _digest(TICKET_ID, owner, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        bytes memory validSig = abi.encodePacked(r, s, v);

        vm.warp(deadline + 1);

        vm.expectRevert(bytes("expired"));
        verifier.verifyAccess(
            TICKET_ID,
            owner,
            nonce,
            deadline,
            METADATA_HASH,
            validSig
        );
    }
}
