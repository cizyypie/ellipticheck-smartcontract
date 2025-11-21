// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";

/// @title DeployScript
/// @notice Script untuk deploy TicketNFT dan TicketVerifier
contract DeployScript is Script {
    function run() external {
        // Ambil private key dari environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TicketNFT
        console.log("Deploying TicketNFT...");
        TicketNFT ticketNFT = new TicketNFT();
        console.log("TicketNFT deployed at:", address(ticketNFT));

        // 2. Deploy TicketVerifier
        console.log("Deploying TicketVerifier...");
        TicketVerifier verifier = new TicketVerifier(address(ticketNFT));
        console.log("TicketVerifier deployed at:", address(verifier));

        // 3. Setup event example (optional)
        console.log("\n=== Creating Sample Event ===");
        uint256 eventId = ticketNFT.createEvent(
            "Konser Musik Rock 2024",
            "2024-12-31",
            "Jakarta Convention Center",
            0.1 ether, // 0.1 ETH per ticket
            100 // 100 tickets available
        );
        console.log("Sample event created with ID:", eventId);

        vm.stopBroadcast();

        // Log summary
        console.log("\n=== Deployment Summary ===");
        console.log("TicketNFT:", address(ticketNFT));
        console.log("TicketVerifier:", address(verifier));
        console.log("\nSave these addresses for frontend integration!");
    }
}