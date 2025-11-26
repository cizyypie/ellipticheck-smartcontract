// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TicketNFT.sol";
import "./ECDSAVerify.sol";

contract TicketVerifier {
    using ECDSAVerify for uint256;

    struct VerificationRequest {
        uint256 ticketId;
        address owner;
        uint256 deadline;
        bytes32 metadataHash;
    }

    struct SignatureData {
        uint256 r;
        uint256 s;
        uint256 Qx;
        uint256 Qy;
    }

    TicketNFT public ticketNFT;

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant TYPEHASH =
        keccak256(
            "TicketAccess(uint256 ticketId,address owner,uint256 deadline,bytes32 metadataHash)"
        );

    mapping(bytes32 => bool) public usedDigest;

    // ERRORS
    error Expired();
    error Replayed();
    error InvalidSignature();
    error NotOwner();
    error InvalidPublicKey();

    event TicketVerified(address indexed owner, uint256 ticketId, bytes32 digest);
    event TicketRejected(uint256 ticketId, string reason);

    constructor(address _ticketNFT) {
        ticketNFT = TicketNFT(_ticketNFT);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("TicketVerifier"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
    }

    // ───────────────────────────
    // MAIN VERIFY FUNCTION
    // ───────────────────────────
    function verifyAccess(
        VerificationRequest calldata req,
        SignatureData calldata sig
    ) external returns (bool) {
        // 1. request validation
        if (block.timestamp > req.deadline) revert Expired();
        if (ticketNFT.ownerOf(req.ticketId) != req.owner) revert NotOwner();

        // 2. digest
        bytes32 digest = _buildDigest(req);
        if (usedDigest[digest]) revert Replayed();

        // 3. signature verification
        _verifySignature(req.owner, digest, sig);

        // 4. mark digest used
        usedDigest[digest] = true;

        // 5. mark ticket used
        ticketNFT.markTicketAsUsed(req.ticketId);

        emit TicketVerified(req.owner, req.ticketId, digest);
        return true;
    }

    // ───────────────────────────
    // INTERNAL HELPERS
    // ───────────────────────────
    function _buildDigest(VerificationRequest calldata req)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                TYPEHASH,
                req.ticketId,
                req.owner,
                req.deadline,
                req.metadataHash
            )
        );

        return keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
    }

    function _verifySignature(
    address owner,
    bytes32 digest,
    SignatureData calldata sig
) internal pure {
    ECDSAVerify.ECPoint memory Q = ECDSAVerify.ECPoint(
        sig.Qx,
        sig.Qy
    );

    if (ECDSAVerify.publicKeyToAddress(Q) != owner)
        revert InvalidPublicKey();

    if (!ECDSAVerify.ecdsaverify(uint256(digest), sig.r, sig.s, Q))
        revert InvalidSignature();
}

}
