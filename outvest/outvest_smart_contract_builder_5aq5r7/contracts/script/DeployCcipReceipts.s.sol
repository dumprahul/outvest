// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EarningsReceiptSender} from "../ccip/EarningsReceiptSender.sol";
import {EarningsReceiptReceiver} from "../ccip/EarningsReceiptReceiver.sol";

/// @notice Deploys the CCIP earnings-receipt pair. Run twice, once per chain.
///   Arc Testnet (5042002):   ROLE=sender   FACTORY=0x..  -> EarningsReceiptSender
///   Destination testnet:     ROLE=receiver SENDER=0x..   -> EarningsReceiptReceiver (pinned to the Arc sender)
/// Router addresses are the active CCIP routers from https://api.ccip.chain.link/v2/chains (checked at deploy time).
contract DeployCcipReceipts is Script {
    uint64 internal constant ARC_TESTNET_SELECTOR = 3034092155422581607;
    address internal constant ARC_ROUTER = 0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8;
    address internal constant SEPOLIA_ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address internal constant BASE_SEPOLIA_ROUTER = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory role = vm.envString("ROLE");
        vm.startBroadcast(pk);
        if (keccak256(bytes(role)) == keccak256("sender")) {
            require(block.chainid == 5042002, "sender must be deployed on Arc Testnet");
            address factory = vm.envAddress("FACTORY");
            EarningsReceiptSender s = new EarningsReceiptSender(ARC_ROUTER, factory);
            console.log("EarningsReceiptSender:", address(s));
        } else if (keccak256(bytes(role)) == keccak256("receiver")) {
            address router = block.chainid == 84532 ? BASE_SEPOLIA_ROUTER
                : block.chainid == 11155111 ? SEPOLIA_ROUTER : address(0);
            require(router != address(0), "unsupported destination chain");
            EarningsReceiptReceiver r = new EarningsReceiptReceiver(router, ARC_TESTNET_SELECTOR, vm.envAddress("SENDER"));
            console.log("EarningsReceiptReceiver:", address(r));
        } else {
            revert("ROLE must be sender or receiver");
        }
        vm.stopBroadcast();
    }
}
