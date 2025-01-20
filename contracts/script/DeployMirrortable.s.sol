// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/Mirrortable.sol";

/**
 * @dev Example Foundry script to deploy Mirrortable.
 *
 * Run:
 * forge script script/DeployMirrortable.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployMirrortable is Script {
    function run() external {
        vm.startBroadcast(); // uses the private key
        Mirrortable mirrortable = new Mirrortable();
        vm.stopBroadcast();

        // Foundry will print the deployed address in the logs
    }
}
