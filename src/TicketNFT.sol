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

    //  Base URI for external images
    string public baseImageURI = "https://api.dicebear.com/7.x/shapes/svg?seed=";
    
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
    error CannotTransferUsedTicket();

    // CONSTRUCTOR
    constructor() ERC721("ElliptiCheck", "ELC") Ownable(msg.sender) {}

    // OVERRIDE _update TO PREVENT TRANSFER OF USED TICKETS
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == address(0))
        // Allow burning (to == address(0))
        // But block transfers of used tickets
        if (from != address(0) && to != address(0)) {
            if (tickets[tokenId].isUsed) {
                revert CannotTransferUsedTicket();
            }
        }
        
        return super._update(to, tokenId, auth);
    }

    // SET VERIFIER
    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
    }

    // NEW: Set base image URI (for updating image source)
    function setBaseImageURI(string memory _baseImageURI) external onlyOwner {
        baseImageURI = _baseImageURI;
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

    //tokenURI with EXTERNAL IMAGE URL
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Ticket memory ticket = tickets[tokenId];
        TicketMetadata memory eventData = events[ticket.eventId];

        // Generate unique image URL based on tokenId
        // This uses Dicebear API to generate unique avatars/shapes
        string memory imageUrl = string(
            abi.encodePacked(
                baseImageURI,
                "ticket",
                tokenId.toString()
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"', eventData.eventName, ' - Ticket #', tokenId.toString(), '",',
                '"description":"Official event ticket for ', eventData.eventName, '",',
                '"image":"', imageUrl, '",', 
                '"external_url":"https://ellipticheck.com/ticket/', tokenId.toString(), '",',
                '"attributes":[',
                    '{"trait_type":"Event","value":"', eventData.eventName, '"},',
                    '{"trait_type":"Date","value":"', eventData.eventDate, '"},',
                    '{"trait_type":"Location","value":"', eventData.eventLocation, '"},',
                    '{"trait_type":"Ticket ID","value":"', tokenId.toString(), '"},',
                    '{"trait_type":"Ticket Number","value":"', ticket.ticketNumber.toString(), '"},',
                    '{"trait_type":"Status","value":"', ticket.isUsed ? 'Used' : 'Active', '"}',
                ']}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
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

    function isTicketUsed(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return tickets[tokenId].isUsed;
    }

    // Get full ticket info for frontend display
    function getTicketInfo(uint256 tokenId) 
        external 
        view 
        returns (
            string memory eventName,
            string memory eventDate,
            string memory eventLocation,
            uint256 ticketId,
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
            tokenId,
            ticket.isUsed
        );
    }
}
