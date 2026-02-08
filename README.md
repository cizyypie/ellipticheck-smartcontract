

# 🔐 elliptiCheck Smart Contracts

---

This repository uses **Foundry** as the main framework for:

* smart contract development
* unit testing
* deployment scripting
* local blockchain (Anvil)

All compile, test, and deployment processes are executed using Foundry built-in tools:
`forge` and `anvil`.

---

elliptiCheck Smart Contracts is the blockchain backend for an NFT-based ticketing system that implements:

* ERC-721 NFT Standard – each ticket is represented as a unique NFT
* ECDSA Verification – on-chain digital signature verification
* EIP-712 Typed Data – structured and standardized data format for signing
* Replay Attack Prevention – digest tracking and deadline mechanism
* On-Chain Ownership Validation – ownership is verified directly on-chain

---

## Main Components

1. TicketNFT.sol
   The main smart contract for minting and managing ticket NFTs.

2. TicketVerifier.sol
   A contract responsible for verifying tickets using ECDSA and EIP-712.

3. ECDSAVerify.sol
   A cryptographic library for secp256k1 elliptic curve operations.

---

## 🏗️ Smart Contract Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    TicketNFT.sol                        │
│  • Ticket NFT minting                                   │
│  • Event management                                     │
│  • Ownership and ticket status tracking                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ calls markTicketAsUsed()
                     ↓
┌─────────────────────────────────────────────────────────┐
│                 TicketVerifier.sol                      │
│  • EIP-712 signature verification                       │
│  • Digest tracking (replay prevention)                  │
│  • Deadline validation                                  │
│  • Ownership verification                               │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ uses
                     ↓
┌─────────────────────────────────────────────────────────┐
│                 ECDSAVerify.sol                         │
│  • ECDSA signature verification                         │
│  • Elliptic curve operations (secp256k1)                │
│  • Public key to address conversion                     │
└─────────────────────────────────────────────────────────┘
```

---

## System Flow

```
USER                    FRONTEND                SMART CONTRACT
  │                         │                          │
  │ Buy ticket              │                          │
  ├────────────────────────►│                          │
  │                         │ mintTicket()             │
  │                         ├─────────────────────────►│
  │                         │                          │
  │                         │◄─────────────────────────┤
  │                         │                          │
  │ Generate QR             │                          │
  ├────────────────────────►│                          │
  │                         │ Sign EIP-712             │
  │◄────────────────────────┤                          │
  │                         │                          │
  │ Scan at gate            │                          │
  ├────────────────────────►│ verifyAccess()           │
  │                         ├─────────────────────────►│
  │                         │                          │ Verify:
  │                         │                          │ - signature
  │                         │                          │ - ownership
  │                         │                          │ - deadline
  │                         │                          │ - not used
  │                         │◄─────────────────────────┤
```

---

## 🛠️ Technologies & Dependencies

Core technologies:

* Solidity ^0.8.24
* Foundry
* Anvil
* OpenZeppelin Contracts

Dependencies:

```
{
  "solidity": "^0.8.24",
  "@openzeppelin/contracts": "^5.0.0"
}
```

Development tools:

* forge
* cast
* anvil

---

💻 Installation

Prerequisites:

* Git
* Foundry

Install Foundry:

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Clone the repository:

```
git clone https://github.com/yourusername/elliptiCheck-contracts.git
cd elliptiCheck-contracts
```

Install dependencies:

```
forge install
```

Compile contracts:

```
forge build
```

---

🧪 Testing

Run all tests:

```
forge test
```

With verbosity:

```
forge test -vv
forge test -vvv
forge test -vvvv
```

Run specific test files:

```
forge test --match-path test/ReplayAttackTest.t.sol
forge test --match-path test/UnauthorizedAcceptanceTest.t.sol
```

Run a specific test function:

```
forge test --match-test test_verifyAccess_AcceptedBeforeDeadline
```

Coverage:

```
forge coverage
```

---

## 🚀 Deployment (Foundry + Anvil + Script)

Deployment is performed using a Foundry script:

```
script/Deploy.s.sol
```

This script automatically:

* deploys TicketNFT
* deploys TicketVerifier
* sets the verifier in TicketNFT
* creates several sample events

Deployment follows the three steps below.

---

1. Export Anvil RPC

Make sure Anvil is running:

```
anvil
```

Then set the RPC URL:

```
export RPC_URL=http://127.0.0.1:8545
```

---

2. Export Private Key (Anvil)

Use the first account’s private key from the Anvil output:

```
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

3. Deploy

Enter the repository directory:

```
cd elliptiCheck-contracts
```

Run the deployment script:

```
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

Example output:

```
Deploying TicketNFT...
TicketNFT deployed at: 0x...

Deploying TicketVerifier...
TicketVerifier deployed at: 0x...

Setting verifier...

Creating sample events...

Deployment summary
TicketNFT: 0x...
TicketVerifier: 0x...
```

---

Contract addresses

Save the addresses from the output:

```
TicketNFT Contract      : 0x...
TicketVerifier Contract : 0x...
Chain ID                : 31337
RPC URL                 : http://127.0.0.1:8545
```

---

Important note

By using:

```
script/Deploy.s.sol
```

you no longer need to run:

* forge create
* cast send setVerifier

All deployment and setup steps are handled automatically by the script.

---

Verify deployment (optional)

```
cast call <ADDRESS_TICKET_NFT> "verifier()" --rpc-url $RPC_URL
```

---

🔗 Frontend Integration

Update contract addresses:

```
export const CONTRACTS = {
  TICKET_NFT: "0x...",
  TICKET_VERIFIER: "0x..."
};
```

Copy ABIs:

```
cp out/TicketNFT.sol/TicketNFT.json ../elliptiCheck-frontend/src/contracts/TicketNFT.abi.json
cp out/TicketVerifier.sol/TicketVerifier.json ../elliptiCheck-frontend/src/contracts/TicketVerifier.abi.json
```

---

MetaMask configuration

Import an account using the private key:

```
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Add network:

```
Network Name    : Anvil Local
RPC URL         : http://127.0.0.1:8545
Chain ID        : 31337
Currency Symbol : ETH
```

---

Start frontend:

```
cd ../elliptiCheck-frontend
npm install
npm run dev
```

Access:

```
http://localhost:5173
```

---

## 🔒 Security Audit

Important:

The manual ECDSA implementation in this project is intended for research and learning purposes only.

For production, use an audited library:

```
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
```

Known limitations:

* higher gas consumption
* not professionally audited
* tested only on Anvil

Recommendations before production:

* replace the manual ECDSA implementation with OpenZeppelin ECDSA
* professional security audit
* gas optimization
* testnet deployment
* stress testing
* multi-sig for admin functions

---

## 🤝 Contribution

Contribution steps:

1. Fork the repository
2. Create a new branch
3. Commit your changes
4. Push the branch
5. Open a pull request

Guidelines:

* write tests for every new feature
* follow the Solidity style guide
* document all public functions
* run:

```
forge fmt
```

---
# Bahasa Indonesia
---
Repository ini menggunakan Foundry sebagai framework utama untuk:

* development smart contract
* unit testing
* deployment scripting
* local blockchain (Anvil)

Seluruh proses compile, test, dan deployment dilakukan menggunakan tool bawaan Foundry:
forge dan anvil.

---
elliptiCheck Smart Contracts adalah backend blockchain untuk sistem tiket NFT yang mengimplementasikan:

* ERC-721 NFT Standard – setiap tiket adalah NFT unik
* ECDSA Verification – verifikasi tanda tangan digital secara on-chain
* EIP-712 Typed Data – format data terstruktur untuk proses signing
* Replay Attack Prevention – digest tracking dan mekanisme deadline
* On-Chain Ownership Validation – verifikasi kepemilikan langsung di blockchain

---

## Komponen Utama

1. TicketNFT.sol
   Smart contract utama untuk minting dan manajemen tiket NFT.

2. TicketVerifier.sol
   Contract untuk memverifikasi tiket menggunakan ECDSA dan EIP-712.

3. ECDSAVerify.sol
   Library kriptografi kurva eliptik secp256k1.

---

## 🏗️ Arsitektur Smart Contract

```
┌─────────────────────────────────────────────────────────┐
│                    TicketNFT.sol                        │
│  • Minting NFT tiket                                    │
│  • Manajemen event                                      │
│  • Tracking kepemilikan & status tiket                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ calls markTicketAsUsed()
                     ↓
┌─────────────────────────────────────────────────────────┐
│                 TicketVerifier.sol                      │
│  • Verifikasi EIP-712 signature                         │
│  • Digest tracking (replay prevention)                  │
│  • Deadline validation                                  │
│  • Ownership verification                               │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ uses
                     ↓
┌─────────────────────────────────────────────────────────┐
│                 ECDSAVerify.sol                         │
│  • ECDSA signature verification                         │
│  • Elliptic curve operations (secp256k1)                │
│  • Public key to address conversion                     │
└─────────────────────────────────────────────────────────┘
```

---

## Flow Sistem

```
USER                    FRONTEND                SMART CONTRACT
  │                         │                          │
  │ Buy ticket              │                          │
  ├────────────────────────►│                          │
  │                         │ mintTicket()             │
  │                         ├─────────────────────────►│
  │                         │                          │
  │                         │◄─────────────────────────┤
  │                         │                          │
  │ Generate QR             │                          │
  ├────────────────────────►│                          │
  │                         │ Sign EIP-712             │
  │◄────────────────────────┤                          │
  │                         │                          │
  │ Scan at gate            │                          │
  ├────────────────────────►│ verifyAccess()           │
  │                         ├─────────────────────────►│
  │                         │                          │ Verify:
  │                         │                          │ - signature
  │                         │                          │ - ownership
  │                         │                          │ - deadline
  │                         │                          │ - not used
  │                         │◄─────────────────────────┤
```

---

## 🛠️ Teknologi & Dependencies

Core technologies:

* Solidity ^0.8.24
* Foundry
* Anvil
* OpenZeppelin Contracts

Dependencies:

```
{
  "solidity": "^0.8.24",
  "@openzeppelin/contracts": "^5.0.0"
}
```

Development tools:

* forge
* cast
* anvil

---

💻 Instalasi

Prerequisites:

* Git
* Foundry

Install Foundry:

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Clone repository:

```
git clone https://github.com/yourusername/elliptiCheck-contracts.git
cd elliptiCheck-contracts
```

Install dependencies:

```
forge install
```

Compile contracts:

```
forge build
```

---

🧪 Testing

Menjalankan semua test:

```
forge test
```

Dengan verbosity:

```
forge test -vv
forge test -vvv
forge test -vvvv
```

Menjalankan test file tertentu:

```
forge test --match-path test/ReplayAttackTest.t.sol
forge test --match-path test/UnauthorizedAcceptanceTest.t.sol
```

Menjalankan fungsi test tertentu:

```
forge test --match-test test_verifyAccess_AcceptedBeforeDeadline
```

Coverage:

```
forge coverage
```

---

## 🚀 Deployment (Foundry + Anvil + Script)

Deployment dilakukan menggunakan Foundry script:

```
script/Deploy.s.sol
```

Script ini akan otomatis:

* deploy TicketNFT
* deploy TicketVerifier
* set verifier ke TicketNFT
* membuat beberapa sample event

Deployment mengikuti tiga langkah berikut.

---

1. Export RPC Anvil

Pastikan Anvil sudah berjalan:

```
anvil
```

Lalu set RPC URL:

```
export RPC_URL=http://127.0.0.1:8545
```

---

2. Export Private Key (Anvil)

Gunakan private key account pertama dari output Anvil:

```
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

3. Deploy

Masuk ke folder repository:

```
cd elliptiCheck-contracts
```

Jalankan deploy script:

```
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

Contoh output:

```
Deploying TicketNFT...
TicketNFT deployed at: 0x...

Deploying TicketVerifier...
TicketVerifier deployed at: 0x...

Setting verifier...

Creating sample events...

Deployment summary
TicketNFT: 0x...
TicketVerifier: 0x...
```

---

Contract addresses

Simpan address dari output:

```
TicketNFT Contract      : 0x...
TicketVerifier Contract : 0x...
Chain ID                : 31337
RPC URL                 : http://127.0.0.1:8545
```

---

Catatan penting

Dengan menggunakan:

```
script/Deploy.s.sol
```

tidak perlu lagi menjalankan:

* forge create
* cast send setVerifier

Semua proses deploy dan setup dilakukan otomatis oleh script.

---

Verify deployment (opsional)

```
cast call <ADDRESS_TICKET_NFT> "verifier()" --rpc-url $RPC_URL
```

---

🔗 Integrasi dengan Frontend

Update address contract:

```
export const CONTRACTS = {
  TICKET_NFT: "0x...",
  TICKET_VERIFIER: "0x..."
};
```

Copy ABI:

```
cp out/TicketNFT.sol/TicketNFT.json ../elliptiCheck-frontend/src/contracts/TicketNFT.abi.json
cp out/TicketVerifier.sol/TicketVerifier.json ../elliptiCheck-frontend/src/contracts/TicketVerifier.abi.json
```

---

Konfigurasi MetaMask

Import account menggunakan private key:

```
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Add network:

```
Network Name    : Anvil Local
RPC URL         : http://127.0.0.1:8545
Chain ID        : 31337
Currency Symbol : ETH
```

---

Start frontend:

```
cd ../elliptiCheck-frontend
npm install
npm run dev
```

Akses:

```
http://localhost:5173
```

---

## 🔒 Security Audit

Penting:

Implementasi ECDSA manual pada project ini hanya untuk tujuan riset dan pembelajaran.

Untuk production, gunakan library yang telah diaudit:

```
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
```

Known limitations:

* konsumsi gas lebih tinggi
* belum melalui audit profesional
* baru diuji di Anvil

Rekomendasi sebelum production:

* ganti manual ECDSA dengan OpenZeppelin ECDSA
* professional security audit
* gas optimization
* testnet deployment
* stress testing
* multi-sig untuk admin function

---

## 🤝 Kontribusi

Langkah kontribusi:

1. Fork repository
2. Buat branch baru
3. Commit perubahan
4. Push ke branch
5. Buka pull request

Guidelines:

* tulis test untuk setiap fitur baru
* ikuti style guide Solidity
* dokumentasikan semua public function
* jalankan:

```
forge fmt
```

---

📄 License

MIT License

---

🔗 Links

Frontend repository
[https://github.com/yourusername/elliptiCheck-frontend](https://github.com/cizyypie/elliptic-fe)

Foundry book
[https://book.getfoundry.sh/](https://book.getfoundry.sh/)


elliptiCheck Smart Contracts – Cryptographically Secure Ticketing
