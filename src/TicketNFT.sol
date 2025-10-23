// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TicketNFT is ERC721, Ownable {
    uint256 private _tokenCounter;
    mapping(uint256 => bytes32) public ticketMetadata;

    event TicketMinted(
        uint256 indexed ticketId,
        address indexed owner,
        uint256 eventId,
        bytes32 metadataHash
    );

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) Ownable(msg.sender) {
        _tokenCounter = 0;
    }

    /// @notice Mencetak tiket baru dan menyimpan hash metadata
    function mintTicket(
        address to,
        uint256 eventId,
        bytes32 metadataHash
    ) external onlyOwner returns (uint256) {
        _tokenCounter++;
        uint256 newTicketId = _tokenCounter;

        _safeMint(to, newTicketId);
        ticketMetadata[newTicketId] = metadataHash;

        emit TicketMinted(newTicketId, to, eventId, metadataHash);
        return newTicketId;
    }

    /// @notice Mengembalikan total tiket yang sudah dibuat
    function totalSupply() public view returns (uint256) {
        return _tokenCounter;
    }
}
