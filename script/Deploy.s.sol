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
        // Event 1: Education
        uint256 id1 = ticketNFT.createEvent(
            "Motion Design Workshop 2025",
            "2025-11-20",
            "Creative Hall, Jaksel",
            0.03 ether, 
            30 
        );
        console.log("Created Event 1: Motion Design Workshop (ID: %s)", id1);

        // Event 2: Sports
        uint256 id2 = ticketNFT.createEvent(
            "Indonesia Open: Finals",
            "2026-06-12",
            "Istora Senayan",
            0.12 ether, 
            5000 
        );
        console.log("Created Event 2: Indonesia Open (ID: %s)", id2);

        // Event 3: Food
        uint256 id3 = ticketNFT.createEvent(
            "Festival Kuliner Nusantara",
            "2026-01-15",
            "Lapangan Puputan, Bali",
            0.015 ether, 
            200 
        );
        console.log("Created Event 3: Festival Kuliner (ID: %s)", id3);

        // Event 4: Entertainment
        uint256 id4 = ticketNFT.createEvent(
            "Stand Up Comedy Special",
            "2026-02-28",
            "Teater Besar, TIM",
            0.04 ether, 
            300 
        );
        console.log("Created Event 4: Stand Up Comedy (ID: %s)", id4);

        // Event 5: Health
        uint256 id5 = ticketNFT.createEvent(
            "Yoga & Meditation Retreat",
            "2026-03-10",
            "Ubud Sanctuary",
            0.08 ether, 
            20 
        );
        console.log("Created Event 5: Yoga Retreat (ID: %s)", id5);
        vm.stopBroadcast();

        // Log summary
        console.log("\n=== Deployment Summary ===");
        console.log("TicketNFT:", address(ticketNFT));
        console.log("TicketVerifier:", address(verifier));
        console.log("\nSave these addresses for frontend integration!");
    }
}