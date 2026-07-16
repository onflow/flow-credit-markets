// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Script.sol";

import {FlowSwapSwapper} from "../src/FlowSwapSwapper.sol";
import {ConfiguredScript} from "./ConfiguredScript.s.sol";

/// @title DeploySwapper
/// @notice Deploys the FlowSwapSwapper pointing at the configured FlowSwap V3
///         router. The swapper is a standalone contract — deploy it once and
///         pass its address to FCMVault.InitParams.swapper on vault deploy.
///
///         Usage (dry-run first by dropping --broadcast):
///           forge script script/DeploySwapper.s.sol \
///             --rpc-url flow_mainnet --broadcast --account "$ACCOUNT"
contract DeploySwapper is ConfiguredScript {
    function run() public {
        Config memory c = _loadConfig();

        vm.startBroadcast();
        FlowSwapSwapper swap = new FlowSwapSwapper(c.swapRouter);
        vm.stopBroadcast();

        console.log("=== deployment complete ===");
        console.log("FlowSwapSwapper: %s", address(swap));
        console.log("SwapRouter:      %s", c.swapRouter);
        console.log("Pass the swapper address to FCMVault.InitParams.swapper on vault deploy.");
    }
}
