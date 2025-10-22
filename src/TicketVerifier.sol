// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/TicketNFT.sol";

/// @title TicketVerifier
/// @notice Verifikasi ECDSA berbasis EIP-712 + kepemilikan NFT dengan anti-replay & expiry.
contract TicketVerifier {
    // ============ EIP-712 ============ 
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant TICKET_ACCESS_TYPEHASH = keccak256(
        "TicketAccess(uint256 ticketId,address owner,uint256 nonce,uint256 deadline,bytes32 metadataHash)"
    );

    // ============ State ============
    TicketNFT public ticketNFT;                 // referensi kontrak TicketNFT
    mapping(bytes32 => bool) public usedDigest; // anti-replay
    address public immutable issuer;            // penandatangan sah

    // konteks internal sementara untuk markUsed
    bytes32 private _pendingDigest;
    address private _pendingOwner;

    // ============ Events ============
    event TicketVerified(address indexed owner, uint256 indexed ticketId, bytes32 digest, uint256 timestamp);
    event TicketRejected(address indexed owner, uint256 indexed ticketId, string reason);
    event TicketUsed(uint256 indexed ticketId, address indexed owner, uint256 usedAt);

    // ============ Constructor ============
    constructor(string memory name, string memory version, address nftAddress) {
        require(nftAddress != address(0), "invalid nft address");
        // pastikan alamat adalah kontrak
        require(nftAddress.code.length > 0, "nft not a contract");

        issuer = msg.sender;
        ticketNFT = TicketNFT(nftAddress);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                address(this)
            )
        );
    }

    // ============ Core ============
    function verifyAccess(
        uint256 ticketId,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 metadataHash,
        bytes calldata signature
    ) external returns (bool) {
        // 1) expiry lebih dulu agar test `Expired()` lulus dan pesannya tepat
        if (block.timestamp > deadline) {
            emit TicketRejected(owner, ticketId, "expired");
            revert("expired");
        }

        // 2) verifikasi kepemilikan NFT (hindari call ke non-contract lebih awal)
        if (ticketNFT.ownerOf(ticketId) != owner) {
            emit TicketRejected(owner, ticketId, "not owner");
            revert("not owner");
        }

        // 3) hitung digest EIP-712
        bytes32 structHash = keccak256(
            abi.encode(
                TICKET_ACCESS_TYPEHASH,
                ticketId,
                owner,
                nonce,
                deadline,
                metadataHash
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // 4) recover signer dengan validasi low-s (EIP-2) & v 27/28
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        // secp256k1n/2 (nilai setengah kurva untuk low-s)
        // 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0
        if (
            uint256(s) >
            0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0
        ) {
            emit TicketRejected(owner, ticketId, "invalid s");
            revert("invalid s");
        }
        if (v != 27 && v != 28) {
            emit TicketRejected(owner, ticketId, "invalid v");
            revert("invalid v");
        }

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0)) {
            emit TicketRejected(owner, ticketId, "invalid sig");
            revert("invalid sig");
        }
        if (recovered != issuer) {
            emit TicketRejected(owner, ticketId, "invalid signer");
            revert("invalid signer");
        }

        // 5) anti-replay & penandaan used (private, tanpa expose digest)
        _pendingDigest = digest;
        _pendingOwner = owner;
        _markUsed(ticketId);
        delete _pendingDigest;
        delete _pendingOwner;

        emit TicketVerified(owner, ticketId, digest, block.timestamp);
        return true;
    }

    // ============ Internal ============
    function _markUsed(uint256 ticketId) private {
        bytes32 digest = _pendingDigest;
        address owner = _pendingOwner;

        if (usedDigest[digest]) {
            emit TicketRejected(owner, ticketId, "replayed");
            revert("replayed");
        }

        usedDigest[digest] = true;
        emit TicketUsed(ticketId, owner, block.timestamp);
    }

    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "invalid length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
