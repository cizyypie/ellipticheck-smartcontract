// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TicketNFT.sol";
import "../src/TicketVerifier.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // 1️⃣ Deploy TicketNFT
        TicketNFT nft = new TicketNFT("ElliptiCheck", "ELT");

        // 2️⃣ Deploy TicketVerifier, passing address NFT ke constructor
        TicketVerifier verifier = new TicketVerifier("ElliptiCheck", "1", address(nft));

        console.log("TicketNFT deployed at:", address(nft));
        console.log("TicketVerifier deployed at:", address(verifier));

        vm.stopBroadcast();
    }
}
