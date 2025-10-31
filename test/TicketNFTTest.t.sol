// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketNFT.sol";

contract TicketNFTTest is Test {
    TicketNFT nft;
    address issuer = address(this);
    address buyer = address(0xBEEF);

    function setUp() public {
        nft = new TicketNFT("ElliptiCheck Ticket", "ECT");
    }

    function test_MintTicket_Succeeds() public {
        bytes32 meta = keccak256("seat-A12");
        uint256 tokenId = nft.mintTicket(buyer, 1001, meta);

        assertEq(nft.ownerOf(tokenId), buyer, "Owner mismatch");
        assertEq(nft.ticketMetadata(tokenId), meta, "Metadata mismatch");
        assertEq(nft.totalSupply(), 1);
    }

    function test_MintTicket_RevertsIfNotOwner() public {
        bytes32 meta = keccak256("seat-B10");
        vm.prank(buyer);
        vm.expectRevert("Ownable: caller is not the owner");
        nft.mintTicket(buyer, 1002, meta);
    }

    function test_Event_Emitted_OnMint() public {
        bytes32 meta = keccak256("seat-C22");
        vm.expectEmit(true, true, true, true);
        emit TicketMinted(1, buyer, 2001, meta);
        nft.mintTicket(buyer, 2001, meta);
    }

    event TicketMinted(
        uint256 indexed ticketId,
        address indexed owner,
        uint256 eventId,
        bytes32 metadataHash
    );
}
