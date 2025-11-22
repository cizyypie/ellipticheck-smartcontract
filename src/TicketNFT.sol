// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title TicketNFT
/// @notice Kontrak NFT untuk tiket event dengan metadata terstruktur
/// @dev Menggunakan ERC-721 standard dengan metadata on-chain
contract TicketNFT is ERC721, Ownable {
    //STRUKTUR DATA
    struct TicketMetadata {
        string eventName;       // Nama event
        string eventDate;       // Tanggal event
        string eventLocation;   // Lokasi event
        uint256 price;          // Harga tiket (dalam wei)
        uint256 totalSupply;    // Total tiket untuk event ini
        bool isActive;          // Status event aktif/tidak
    }

    struct Ticket {
        uint256 eventId;        // ID event terkait
        uint256 ticketNumber;   // Nomor tiket dalam event
        uint256 mintedAt;       // Timestamp mint
        bool isUsed;            // Status sudah digunakan/belum
    }

    //STATE VARIABLES
    uint256 private _tokenIdCounter;
    uint256 private _eventIdCounter;

    mapping(uint256 => TicketMetadata) public events;           // eventId => metadata
    mapping(uint256 => Ticket) public tickets;                  // tokenId => ticket info
    mapping(uint256 => uint256) public eventTicketCount;        // eventId => jumlah tiket terjual
    mapping(uint256 => string) private _tokenURIs;              // tokenId => URI metadata

    //EVENTS
    event EventCreated(
        uint256 indexed eventId,
        string eventName,
        uint256 totalSupply,
        uint256 price
    );

    event TicketMinted(
        uint256 indexed tokenId,
        uint256 indexed eventId,
        address indexed owner,
        uint256 ticketNumber
    );

    event TicketUsed(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 timestamp
    );

    // ⚠️ CUSTOM ERRORS
    error EventNotActive();
    error SoldOut();
    error InsufficientPayment();
    error TicketAlreadyUsed();
    error InvalidEventId();

    //CONSTRUCTOR
    constructor() ERC721("EventTicket", "ETIX") Ownable(msg.sender) {
        _tokenIdCounter = 1;
        _eventIdCounter = 1;
    }

    //FASE 1: ORGANIZER CREATE EVENT & MINTING TICKETS
    
    /// @notice Organizer membuat event baru
    /// @param eventName Nama event
    /// @param eventDate Tanggal event
    /// @param eventLocation Lokasi event
    /// @param price Harga tiket
    /// @param totalSupply Total jumlah tiket
    function createEvent(
        string calldata eventName,
        string calldata eventDate,
        string calldata eventLocation,
        uint256 price,
        uint256 totalSupply
    ) external onlyOwner returns (uint256 eventId) {
        eventId = _eventIdCounter++;

        events[eventId] = TicketMetadata({
            eventName: eventName,
            eventDate: eventDate,
            eventLocation: eventLocation,
            price: price,
            totalSupply: totalSupply,
            isActive: true
        });

        emit EventCreated(eventId, eventName, totalSupply, price);
    }

    /// @notice Mint tiket NFT untuk pembeli
    /// @param eventId ID event yang ingin dibeli tiketnya
    /// @param to Address pembeli
    function mintTicket(uint256 eventId, address to) external payable returns (uint256 tokenId) {
        TicketMetadata memory eventData = events[eventId];

        // Validasi
        if (!eventData.isActive) revert EventNotActive();
        if (eventTicketCount[eventId] >= eventData.totalSupply) revert SoldOut();
        if (msg.value < eventData.price) revert InsufficientPayment();

        // Mint NFT
        tokenId = _tokenIdCounter++;
        uint256 ticketNumber = eventTicketCount[eventId] + 1;

        tickets[tokenId] = Ticket({
            eventId: eventId,
            ticketNumber: ticketNumber,
            mintedAt: block.timestamp,
            isUsed: false
        });

        eventTicketCount[eventId]++;
        _safeMint(to, tokenId);

        emit TicketMinted(tokenId, eventId, to, ticketNumber);
    }

    //FUNGSI HELPER & GETTER

    /// @notice Tandai tiket sudah digunakan (dipanggil oleh TicketVerifier)
    /// @param tokenId ID tiket yang digunakan
    function markTicketAsUsed(uint256 tokenId) external {
        if (tickets[tokenId].isUsed) revert TicketAlreadyUsed();
        tickets[tokenId].isUsed = true;
        emit TicketUsed(tokenId, ownerOf(tokenId), block.timestamp);
    }

    /// @notice Cek apakah tiket sudah digunakan
    function isTicketUsed(uint256 tokenId) external view returns (bool) {
        return tickets[tokenId].isUsed;
    }

    /// @notice Get detail event
    function getEvent(uint256 eventId) external view returns (TicketMetadata memory) {
        if (eventId == 0 || eventId >= _eventIdCounter) revert InvalidEventId();
        return events[eventId];
    }

    /// @notice Get detail tiket
    function getTicket(uint256 tokenId) external view returns (Ticket memory) {
        return tickets[tokenId];
    }

    /// @notice Set token URI untuk metadata
    function setTokenURI(uint256 tokenId, string calldata uri) external onlyOwner {
        _tokenURIs[tokenId] = uri;
    }

    /// @notice Override tokenURI untuk mengembalikan metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _tokenURIs[tokenId];
    }

    /// @notice Toggle status event aktif/tidak aktif
    function toggleEventStatus(uint256 eventId) external onlyOwner {
        events[eventId].isActive = !events[eventId].isActive;
    }

    /// @notice Withdraw dana dari penjualan tiket
    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }
}