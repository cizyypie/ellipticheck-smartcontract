// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TicketNFT.sol";
import "./ECDSAVerify.sol";

/// @title TicketVerifier
/// @notice Verifikasi tiket NFT menggunakan implementasi manual ECDSA + EIP-712
///         Dilengkapi proteksi nonce, expiry, dan anti-replay.
contract TicketVerifier {
    using ECDSAVerify for uint256;

    // =============================================================
    // 📦 STRUCTS
    // =============================================================
    struct VerificationRequest {
        uint256 ticketId;
        address owner;
        uint256 nonce;
        uint256 deadline;
        bytes32 metadataHash;
    }

    struct SignatureData {
        uint256 r;
        uint256 s;
        uint256 Qx;
        uint256 Qy;
    }

    // =============================================================
    // 🧠 KONSTANTA EIP-712
    // =============================================================
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant TICKET_ACCESS_TYPEHASH = keccak256(
        "TicketAccess(uint256 ticketId,address owner,uint256 nonce,uint256 deadline,bytes32 metadataHash)"
    );

    // =============================================================
    // 🧩 STATE
    // =============================================================
    TicketNFT public ticketNFT;                     // referensi kontrak tiket
    mapping(bytes32 => bool) public usedDigest;     // anti replay
    mapping(address => uint256) public nonces;      // pelacakan nonce per user

    // =============================================================
    // ⚠️ CUSTOM ERRORS
    // =============================================================
    error Expired();
    error Replayed();
    error InvalidSignature();
    error NotOwner();
    error InvalidPublicKey();

    // =============================================================
    // 📋 EVENTS
    // =============================================================
    event TicketVerified(
        address indexed owner, 
        uint256 indexed ticketId, 
        bytes32 digest, 
        uint256 timestamp
    );
    event TicketRejected(
        address indexed owner, 
        uint256 indexed ticketId, 
        string reason
    );

    // =============================================================
    // 🗃️ KONSTRUKTOR
    // =============================================================
    constructor(address _ticketNFT) {
        ticketNFT = TicketNFT(_ticketNFT);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TicketVerifier")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // =============================================================
    // 📊 GETTER NONCE
    // =============================================================
    function getNonce(address owner) external view returns (uint256) {
        return nonces[owner];
    }

    // =============================================================
    // 🎫 FUNGSI VERIFIKASI TIKET (MENGGUNAKAN ECDSA MANUAL)
    // =============================================================
    /// @notice Verifikasi akses tiket dengan implementasi ECDSA manual
    function verifyAccess(
        VerificationRequest calldata request,
        SignatureData calldata signature
    ) external returns (bool) {
        // ====== FASE 1: VALIDASI AWAL ======
        _validateRequest(request);

        // ====== FASE 2: HITUNG EIP-712 DIGEST ======
        bytes32 digest = _computeDigest(request);

        // ====== FASE 3: VERIFIKASI ECDSA MANUAL ======
        _verifySignature(request.owner, request.ticketId, digest, signature);

        // ====== FASE 4: FINALISASI ======
        usedDigest[digest] = true;
        nonces[request.owner]++;

        emit TicketVerified(request.owner, request.ticketId, digest, block.timestamp);
        
        return true;
    }

    // =============================================================
    // 🔒 INTERNAL FUNCTIONS
    // =============================================================
    
    function _validateRequest(VerificationRequest calldata request) private {
        // 1️⃣ Cek masa berlaku
        if (block.timestamp > request.deadline) {
            emit TicketRejected(request.owner, request.ticketId, "expired");
            revert Expired();
        }

        // 2️⃣ Pastikan tiket benar-benar milik owner
        if (ticketNFT.ownerOf(request.ticketId) != request.owner) {
            emit TicketRejected(request.owner, request.ticketId, "not owner");
            revert NotOwner();
        }

        // 3️⃣ Cek nonce agar tidak terjadi replay
        if (request.nonce != nonces[request.owner]) {
            emit TicketRejected(request.owner, request.ticketId, "invalid nonce");
            revert Replayed();
        }
    }

    function _computeDigest(VerificationRequest calldata request) private returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                TICKET_ACCESS_TYPEHASH,
                request.ticketId,
                request.owner,
                request.nonce,
                request.deadline,
                request.metadataHash
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );

        // Cek apakah digest sudah pernah dipakai (anti replay)
        if (usedDigest[digest]) {
            emit TicketRejected(request.owner, request.ticketId, "digest already used");
            revert Replayed();
        }

        return digest;
    }

    function _verifySignature(
        address owner,
        uint256 ticketId,
        bytes32 digest,
        SignatureData calldata signature
    ) private {
        // Bentuk public key dari koordinat yang dikirim
        ECDSAVerify.ECPoint memory Q = ECDSAVerify.ECPoint(signature.Qx, signature.Qy);

        // Validasi bahwa public key benar-benar milik owner
        if (ECDSAVerify.publicKeyToAddress(Q) != owner) {
            emit TicketRejected(owner, ticketId, "invalid public key");
            revert InvalidPublicKey();
        }

        // Konversi digest ke uint256 untuk ECDSA verify
        uint256 z = uint256(digest);

        // VERIFIKASI SIGNATURE DENGAN ALGORITMA ECDSA MANUAL
        if (!ECDSAVerify.ecdsaverify(z, signature.r, signature.s, Q)) {
            emit TicketRejected(owner, ticketId, "invalid signature");
            revert InvalidSignature();
        }
    }

    // =============================================================
    // 🔧 FUNGSI HELPER: Cek apakah digest sudah pernah digunakan
    // =============================================================
    function isDigestUsed(bytes32 digest) external view returns (bool) {
        return usedDigest[digest];
    }

    // =============================================================
    // 🔄 BACKWARD COMPATIBILITY: Original function signature
    // =============================================================
    /// @notice Wrapper untuk backward compatibility
    function verifyAccess(
        uint256 ticketId,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 metadataHash,
        uint256 r,
        uint256 s,
        uint256 Qx,
        uint256 Qy
    ) external returns (bool) {
        return this.verifyAccess(
            VerificationRequest(ticketId, owner, nonce, deadline, metadataHash),
            SignatureData(r, s, Qx, Qy)
        );
    }
}