// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract TicketNFT is ERC721, Ownable {
    using Strings for uint256;
    
    // STRUCTS
    struct TicketMetadata {
        string eventName;
        string eventDate;
        string eventLocation;
        uint256 price;
        uint256 totalSupply;
        bool isActive;
    }

    struct Ticket {
        uint256 eventId;
        uint256 ticketNumber;
        uint256 mintedAt;
        bool isUsed;
    }

    // STATE VARIABLES
    uint256 private _tokenIdCounter = 1;
    uint256 private _eventIdCounter = 1;

    mapping(uint256 => TicketMetadata) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => uint256) public eventTicketCount;

    address public verifier;

    // EVENTS
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

    // ERRORS
    error EventNotActive();
    error SoldOut();
    error InsufficientPayment();
    error TicketAlreadyUsed();
    error InvalidEventId();
    error Unauthorized();

    // CONSTRUCTOR
    constructor() ERC721("ElliptiCheck", "ELC") Ownable(msg.sender) {}

    // SET VERIFIER
    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
    }


    // EVENT CREATION
    function createEvent(
        string calldata eventName,
        string calldata eventDate,
        string calldata eventLocation,
        uint256 price,
        uint256 totalSupply
    ) external onlyOwner returns (uint256 eventId) {
        eventId = _eventIdCounter++;

        events[eventId] = TicketMetadata(
            eventName,
            eventDate,
            eventLocation,
            price,
            totalSupply,
            true
        );

        emit EventCreated(eventId, eventName, totalSupply, price);
    }

    // MINTING
    function mintTicket(uint256 eventId, address to)
        external
        payable
        returns (uint256 tokenId)
    {
        TicketMetadata memory e = events[eventId];
        if (!e.isActive) revert EventNotActive();
        if (eventTicketCount[eventId] >= e.totalSupply) revert SoldOut();
        if (msg.value < e.price) revert InsufficientPayment();

        tokenId = _tokenIdCounter++;
        uint256 ticketNumber = ++eventTicketCount[eventId];

        tickets[tokenId] = Ticket(
            eventId,
            ticketNumber,
            block.timestamp,
            false
        );

        _safeMint(to, tokenId);

        emit TicketMinted(tokenId, eventId, to, ticketNumber);
    }

    // MARK TICKET USED
    function markTicketAsUsed(uint256 tokenId) external {
        if (msg.sender != verifier) revert Unauthorized();
        if (tickets[tokenId].isUsed) revert TicketAlreadyUsed();

        tickets[tokenId].isUsed = true;

        emit TicketUsed(tokenId, ownerOf(tokenId), block.timestamp);
    }

    // SIMPLIFIED TOKEN URI - MINIMAL METADATA TO AVOID STACK ISSUES
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireOwned(tokenId);
        
        Ticket memory ticket = tickets[tokenId];
        TicketMetadata memory eventData = events[ticket.eventId];

        // Generate SVG image
        string memory svg = _generateSVG(tokenId, ticket, eventData);
        
        // Encode SVG to base64
        string memory svgBase64 = Base64.encode(bytes(svg));

        // Build complete JSON metadata
        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                eventData.eventName,
                ' - Ticket #',
                ticket.ticketNumber.toString(),
                '","description":"Event ticket for ',
                eventData.eventName,
                ' on ',
                eventData.eventDate,
                '","image":"data:image/svg+xml;base64,',
                svgBase64,
                '","attributes":[',
                '{"trait_type":"Event","value":"',
                eventData.eventName,
                '"},',
                '{"trait_type":"Date","value":"',
                eventData.eventDate,
                '"},',
                '{"trait_type":"Location","value":"',
                eventData.eventLocation,
                '"},',
                '{"trait_type":"Ticket Number","value":"',
                ticket.ticketNumber.toString(),
                '"},',
                '{"trait_type":"Status","value":"',
                ticket.isUsed ? 'Used' : 'Active',
                '"}',
                ']}'
            )
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            )
        );
    }

    // Generate beautiful SVG ticket image
    function _generateSVG(
        uint256 tokenId,
        Ticket memory ticket,
        TicketMetadata memory eventData
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg width="400" height="600" xmlns="http://www.w3.org/2000/svg">',
                '<defs>',
                '<linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" style="stop-color:rgb(147,51,234);stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:rgb(79,70,229);stop-opacity:1" />',
                '</linearGradient>',
                '</defs>',
                '<rect width="400" height="600" fill="url(#grad)" rx="20"/>',
                '<rect x="20" y="20" width="360" height="560" fill="white" rx="15" opacity="0.95"/>',
                '<text x="200" y="80" font-family="Arial" font-size="28" font-weight="bold" text-anchor="middle" fill="#7c3aed">',
                eventData.eventName,
                '</text>',
                '<text x="200" y="140" font-family="Arial" font-size="18" text-anchor="middle" fill="#4b5563">',
                unicode"📅 ",
                eventData.eventDate,
                '</text>',
                '<text x="200" y="180" font-family="Arial" font-size="16" text-anchor="middle" fill="#6b7280">',
                unicode"📍 ",
                eventData.eventLocation,
                '</text>',
                '<rect x="50" y="220" width="300" height="2" fill="#e5e7eb"/>',
                '<text x="200" y="280" font-family="Arial" font-size="48" font-weight="bold" text-anchor="middle" fill="#7c3aed">',
                '#',
                ticket.ticketNumber.toString(),
                '</text>',
                '<text x="200" y="320" font-family="Arial" font-size="14" text-anchor="middle" fill="#9ca3af">',
                'TICKET NUMBER',
                '</text>',
                '<rect x="50" y="360" width="300" height="2" fill="#e5e7eb"/>',
                '<text x="200" y="420" font-family="Arial" font-size="12" text-anchor="middle" fill="#6b7280">',
                'Token ID: #',
                tokenId.toString(),
                '</text>',
                '<text x="200" y="450" font-family="Arial" font-size="16" font-weight="bold" text-anchor="middle" fill="',
                ticket.isUsed ? '#ef4444' : '#10b981',
                '">',
                ticket.isUsed ? unicode'✓ USED' : unicode'✓ ACTIVE',
                '</text>',
                '<rect x="50" y="480" width="300" height="80" fill="#f3f4f6" rx="10"/>',
                '<text x="200" y="510" font-family="Arial" font-size="10" text-anchor="middle" fill="#6b7280">',
                'POWERED BY ELLIPTICHECK',
                '</text>',
                '<text x="200" y="535" font-family="Arial" font-size="10" text-anchor="middle" fill="#9ca3af">',
                'Blockchain Verified Ticket',
                '</text>',
                '</svg>'
            )
        );
    }

    // MISC
    function toggleEventStatus(uint256 eventId) external onlyOwner {
        events[eventId].isActive = !events[eventId].isActive;
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // GETTER FUNCTIONS
    function eventCounter() external view returns (uint256) {
        return _eventIdCounter - 1;
    }

    function getEvent(uint256 eventId) 
        external 
        view 
        returns (TicketMetadata memory) 
    {
        if (eventId == 0 || eventId >= _eventIdCounter) revert InvalidEventId();
        return events[eventId];
    }

    function getTicket(uint256 tokenId) 
        external 
        view 
        returns (Ticket memory) 
    {
        _requireOwned(tokenId);
        return tickets[tokenId];
    }

    function getAllEvents() external view returns (TicketMetadata[] memory) {
        uint256 totalEvents = _eventIdCounter - 1;
        TicketMetadata[] memory allEvents = new TicketMetadata[](totalEvents);
        
        for (uint256 i = 1; i <= totalEvents; i++) {
            allEvents[i - 1] = events[i];
        }
        
        return allEvents;
    }

    function tokenCounter() external view returns (uint256) {
        return _tokenIdCounter - 1;
    }

    // Get full ticket info for frontend display
    function getTicketInfo(uint256 tokenId) 
        external 
        view 
        returns (
            string memory eventName,
            string memory eventDate,
            string memory eventLocation,
            uint256 ticketNumber,
            bool isUsed
        ) 
    {
        _requireOwned(tokenId);
        Ticket memory ticket = tickets[tokenId];
        TicketMetadata memory eventData = events[ticket.eventId];
        
        return (
            eventData.eventName,
            eventData.eventDate,
            eventData.eventLocation,
            ticket.ticketNumber,
            ticket.isUsed
        );
    }
}