// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/TicketNFT.sol";
import "./ECDSAVerify.sol";

/// @title TicketVerifier
/// @notice Verifikasi ECDSA berbasis EIP-712 + kepemilikan NFT dengan anti-replay & expiry.
contract TicketVerifier {
    // ============ EIP-712 ============
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant TICKET_ACCESS_TYPEHASH =
        keccak256(
            "TicketAccess(uint256 ticketId,address owner,uint256 nonce,uint256 deadline,bytes32 metadataHash)"
        );

    // ============ State ============
    TicketNFT public ticketNFT; // referensi ke kontrak NFT tempat tiket disimpan, untuk memeriksa siapa pemilik tiket 
    mapping(bytes32 => bool) public usedDigest; // menyimpan hash tanda tangan (digest) yang sudah pernah digunakan → agar tidak bisa di-replay.
    address public immutable issuer; // alamat pembuat kontrak, yang menjadi penerbit tiket.
    mapping(address => uint256) public userNonce; //penyimpanan angka unik untuk setiap user.
                                                  // Ini inti mekanisme anti-replay versi on-chain.
                                                  // Setiap pengguna punya nonce tersendiri, dimulai dari 0, dan akan bertambah setiap kali verifikasi berhasil.

    // tambahkan koordinat publik key issuer (dihitung dari private key penanda tangan)
    // tambahkan koordinat publik key issuer 
    uint256 constant Qx =
        0x931e7fda8da226f799f791eefc9afebcd7ae2b1b19a03c5eaa8d72122d9fe74d;
    uint256 constant Qy =
        0x887a3962ff861190b531ab31ee82f0d7f255dfe3ab73ca627bd70ab3d1cbb417;

    // konteks internal sementara untuk markUsed → Variabel sementara untuk menyimpan digest dan owner sebelum diproses di fungsi _markUsed.
    //Setelah selesai, nilainya dihapus lagi (delete).
    bytes32 private _pendingDigest;
    address private _pendingOwner;

    // ============ Events ============
    // tanda tiket berhasil diverifikasi.
    event TicketVerified(   
        address indexed owner,
        uint256 indexed ticketId,
        bytes32 digest,
        uint256 timestamp
    );
    // tiket ditolak (dengan alasan).
    event TicketRejected(
        address indexed owner,
        uint256 indexed ticketId,
        string reason
    );
    // tiket resmi digunakan.
    event TicketUsed(
        uint256 indexed ticketId,
        address indexed owner,
        uint256 usedAt
    );

    // ============ Constructor ============
    constructor(string memory name, string memory version, address nftAddress) {
        require(nftAddress != address(0), "invalid nft address");
        // pastikan alamat adalah kontrak
        require(nftAddress.code.length > 0, "nft not a contract");

        // Menyimpan issuer = msg.sender (pembuat kontrak).
        issuer = msg.sender;
        ticketNFT = TicketNFT(nftAddress);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
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
        // Mengambil nilai nonce terakhir milik user dari kontrak.
        uint256 expectedNonce = userNonce[owner];
        // Mengecek apakah nonce yang dikirim sama dengan yang tersimpan.
        // Kalau beda → tanda tangan ditolak (bisa jadi replay).
        require(nonce == expectedNonce, "invalid nonce");

        // 1) expiry lebih dulu agar test `Expired()` lulus dan pesannya tepat
        // Jika waktu sekarang melewati batas deadline, tiket dianggap kadaluarsa dan transaksi dibatalkan.
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
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        // 4) recover signer dengan validasi low-s (EIP-2) & v 27/28
        // Memecah tanda tangan signature menjadi tiga komponen (r, s, v) agar bisa diproses di ECDSA.
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
        } //Memastikan nilai tanda tangan tidak manipulatif dan sesuai aturan low-s (EIP-2).

        /// verifikasi ECDSA dengan public key issuer
        // Mengecek apakah tanda tangan (r, s) cocok dengan pesan digest dan public key issuer.
        // Jika tidak cocok → transaksi gagal.
        ECDSAVerify.ECPoint memory pubKey = ECDSAVerify.ECPoint(Qx, Qy);
        bool valid = ECDSAVerify.ecdsaverify(
            uint256(digest),
            uint256(r),
            uint256(s),
            pubKey
        );

        if (!valid) {
            emit TicketRejected(owner, ticketId, "invalid sig");
            revert("invalid sig");
        }

        // 5) anti-replay & penandaan used (private, tanpa expose digest)
        _pendingDigest = digest;
        _pendingOwner = owner;
        _markUsed(ticketId);
        delete _pendingDigest;
        delete _pendingOwner;

        emit TicketVerified(owner, ticketId, digest, block.timestamp);
        userNonce[owner]++; // naikkan nonce agar tidak bisa diulang
        return true;
        /*
        1) _pendingDigest & _pendingOwner disiapkan sementara.
        2) _markUsed() menandai bahwa digest ini sudah pernah digunakan.
        3) Setelah itu dihapus (supaya variabel sementara bersih).
        4) Emit event TicketVerified.
        5) userNonce[owner]++ → meningkatkan nonce user agar tanda tangan yang sama tidak bisa dipakai ulang.  
                */
    }

    // ============ Internal ============
    function _markUsed(uint256 ticketId) private {
        bytes32 digest = _pendingDigest;
        address owner = _pendingOwner;

        if (usedDigest[digest]) { //Jika digest sudah ada di mapping, berarti pesan itu pernah diverifikasi → replay attack
            emit TicketRejected(owner, ticketId, "replayed");
            revert("replayed");
        }

        usedDigest[digest] = true;
        emit TicketUsed(ticketId, owner, block.timestamp);
    } 

    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function getNonce(address user) external view returns (uint256) {
        return userNonce[user]; 
    }//Frontend bisa memanggil ini untuk mengetahui nonce terakhir milik user sebelum membuat tanda tangan baru.
}
