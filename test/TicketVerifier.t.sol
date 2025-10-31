// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicketVerifier.sol"; // sesuaikan path jika berbeda

/// ------------------------------------------------------------------------
/// Mock NFT: cukup minimal, hanya butuh ownerOf() untuk dipanggil verifier
/// ------------------------------------------------------------------------
contract MockNFT {
    mapping(uint256 => address) private _owners;

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "nonexistent");
        return o;
    }

    function mint(address to, uint256 tokenId) external {
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = to;
    }
}

/// ------------------------------------------------------------------------
/// Test suite
/// ------------------------------------------------------------------------
contract TicketVerifierTest is Test {
    // ====== Konstanta secp256k1 yang dipakai kontrak ======
    uint256 constant N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 constant HALF_N =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    // ====== SUT & dependencies ======
    MockNFT nft;
    TicketVerifier verifier;

    // ====== Domain/EIP-712 params ======
    string NAME = "ElliptiCheck";
    string VERSION = "1";

    // ====== Aktor & kunci ======
    address buyer;          // pemilik tiket/NFT
    uint256 buyerPk;        // tidak dipakai untuk tanda tangan di sini
    address issuerEOA;      // hanya untuk menyimpan siapa deployer (kontrak pakai Qx,Qy)
    uint256 issuerPk;       // HARUS diset agar public key-nya = (Qx,Qy) di kontrak!

    // Catatan PENTING:
    // TicketVerifier TIDAK pakai ecrecover(issuer), tapi memverifikasi SIG dengan public key (Qx,Qy) yang DIHARDCODE.
    // Jadi, supaya test "valid signature" lulus, 'issuerPk' HARUS merupakan private key yang public key-nya cocok
    // dengan Qx,Qy dalam TicketVerifier.
    

    function setUp() public {
        // akun pembeli (random untuk test)
    (buyer, buyerPk) = makeAddrAndKey("BUYER");

    // Ambil private key issuer dari file .env
    issuerPk = vm.envUint("PRIVATE_KEY");
    issuerEOA = vm.addr(issuerPk); // derive address dari private key

    // Deploy NFT mock dan mint tiket
    nft = new MockNFT();
    nft.mint(buyer, 1);

    // Deploy verifier oleh issuer
    vm.startPrank(issuerEOA);
    verifier = new TicketVerifier(NAME, VERSION, address(nft));
    vm.stopPrank();
    }

    // === Util: buat EIP-712 digest, lalu sign pakai issuerPk ===
    function _signTicket(
        uint256 ticketId,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 metadataHash
    ) internal view returns (bytes memory sig, bytes32 digest, bytes32 r, bytes32 s, uint8 v) {
        // struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                verifier.TICKET_ACCESS_TYPEHASH(),
                ticketId,
                owner,
                nonce,
                deadline,
                metadataHash
            )
        );

        // EIP-712 digest
        digest = keccak256(
            abi.encodePacked("\x19\x01", verifier.DOMAIN_SEPARATOR(), structHash)
        );

        // tanda tangan secp256k1
        (v, r, s) = vm.sign(issuerPk, digest);

        // Pastikan v dalam {27,28}
        if (v < 27) v += 27;

        // Foundry/Anvil default-nya sudah low-s. Validasi defensif opsional.
        require(uint256(s) <= HALF_N, "vm.sign produced high-s");

        sig = abi.encodePacked(r, s, v);
    }

    // === Util: coba call verifyAccess dan harapkan sukses ===
    function _callVerifyExpectSuccess(
        uint256 ticketId,
        address owner,
        uint256 nonce,
        uint256 deadline,
        bytes32 metadataHash
    ) internal returns (bytes32 digest) {
        (bytes memory sig, bytes32 dig,,,) =
            _signTicket(ticketId, owner, nonce, deadline, metadataHash);

        // panggil
        bool ok = verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
        assertTrue(ok, "verifyAccess must succeed");
        return dig;
    }

    // -------------------------------------------------------
    //                   TEST CASES
    // -------------------------------------------------------

    /// Skenario bahagia: signature valid, owner benar, nonce benar, belum expired.
    function test_Verify_Succeeds_WithValidSignature() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 nonce = verifier.getNonce(owner); // harus 0 saat awal
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        bytes32 digest = _callVerifyExpectSuccess(ticketId, owner, nonce, deadline, metadataHash);

        // Nonce bertambah
        assertEq(verifier.getNonce(owner), nonce + 1, "nonce must increment");

        // Digest ditandai used
        assertTrue(verifier.usedDigest(digest), "digest must be marked used");
    }

    /// Anti-replay via digest: kirim ulang signature yang sama → revert("replayed")
    function test_Replay_SameDigest_Rejected() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 nonce = verifier.getNonce(owner);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        (bytes memory sig, bytes32 digest,,,) =
            _signTicket(ticketId, owner, nonce, deadline, metadataHash);

        // panggilan pertama OK
        bool ok = verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
        assertTrue(ok);

        // panggilan ulang dengan SIG & input sama → replayed
        vm.expectRevert(bytes("replayed"));
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);

        // mapping usedDigest tetap true
        assertTrue(verifier.usedDigest(digest));
    }

    /// Nonce salah → revert("invalid nonce")
    function test_InvalidNonce_Rejected() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 correctNonce = verifier.getNonce(owner); // 0
        uint256 wrongNonce = correctNonce + 5;           // salah
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        // Kita harus tetap menandatangani payload dengan wrongNonce agar digest konsisten
        (bytes memory sig,,,,) =
            _signTicket(ticketId, owner, wrongNonce, deadline, metadataHash);

        vm.expectRevert("invalid nonce");
        verifier.verifyAccess(ticketId, owner, wrongNonce, deadline, metadataHash, sig);
    }

    /// Pemilik NFT tidak cocok → revert("not owner")
    function test_NotOwner_Rejected() public {
        uint256 ticketId = 1;
        address fakeOwner = address(0xBEEF);
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        (bytes memory sig,,,,) =
            _signTicket(ticketId, fakeOwner, nonce, deadline, metadataHash);

        vm.expectRevert("not owner");
        verifier.verifyAccess(ticketId, fakeOwner, nonce, deadline, metadataHash, sig);
    }

    /// Expired → revert("expired")
    function test_Expired_Rejected() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 nonce = verifier.getNonce(owner);
        uint256 deadline = block.timestamp + 10; // 10 detik
        bytes32 metadataHash = keccak256("seat-A12");

        (bytes memory sig,,,,) =
            _signTicket(ticketId, owner, nonce, deadline, metadataHash);

        // majukan waktu melewati deadline
        vm.warp(deadline + 1);

        vm.expectRevert("expired");
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sig);
    }

    /// Low-s enforcement (EIP-2): paksa high-s → revert("invalid s")
    function test_HighS_Rejected() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 nonce = verifier.getNonce(owner);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        // ambil tanda tangan valid dulu
        (bytes memory sig,, bytes32 r, bytes32 s, uint8 v) =
            _signTicket(ticketId, owner, nonce, deadline, metadataHash);

        // ubah ke high-s: s' = N - s
        uint256 sNum = uint256(s);
        uint256 sHigh = N - sNum;

        // rakit ulang signature dengan sHigh
        bytes memory sigHigh = abi.encodePacked(r, bytes32(sHigh), v);

        vm.expectRevert("invalid s");
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sigHigh);
    }

    /// v bukan 27/28 → revert("invalid v")
    function test_InvalidV_Rejected() public {
        uint256 ticketId = 1;
        address owner = buyer;
        uint256 nonce = verifier.getNonce(owner);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 metadataHash = keccak256("seat-A12");

        (bytes memory sig,, bytes32 r, bytes32 s, ) =
            _signTicket(ticketId, owner, nonce, deadline, metadataHash);

        // paksa v jadi 1 (salah)
        uint8 vBad = 1;
        bytes memory sigBad = abi.encodePacked(r, s, vBad);

        vm.expectRevert("invalid v");
        verifier.verifyAccess(ticketId, owner, nonce, deadline, metadataHash, sigBad);
    }

    /// Pastikan userNonce bertambah hanya pada verifikasi yang sukses
    function test_Nonce_Increments_OnlyOnSuccess() public {
        uint256 ticketId = 1;
        address owner = buyer;

        // 1) sukses → nonce naik
        {
            uint256 nonce0 = verifier.getNonce(owner);
            uint256 deadline = block.timestamp + 1 hours;
            bytes32 metadataHash = keccak256("A");
            _callVerifyExpectSuccess(ticketId, owner, nonce0, deadline, metadataHash);
            assertEq(verifier.getNonce(owner), nonce0 + 1);
        }

        // 2) gagal (expired) → nonce tidak berubah
        {
            uint256 nonce1 = verifier.getNonce(owner);
            uint256 deadline = block.timestamp + 10;
            bytes32 metadataHash = keccak256("B");
            (bytes memory sig,,,,) =
                _signTicket(ticketId, owner, nonce1, deadline, metadataHash);
            vm.warp(deadline + 1);
            vm.expectRevert("expired");
            verifier.verifyAccess(ticketId, owner, nonce1, deadline, metadataHash, sig);
            assertEq(verifier.getNonce(owner), nonce1, "nonce must not change on failure");
        }
    }
}
