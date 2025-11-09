// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ReputationSplitter} from "../src/builder_gate/ReputationSplitter.sol";

/**
 * @title Deploy ReputationSplitter
 * @notice Script to deploy ReputationSplitter contract (uses ERC20 token)
 * @dev Run with: forge script script/DeployReputationSplitter.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
 *
 * Steps:
 * 1. Deploy ReputationSplitter with reward token address from REWARD_TOKEN env variable
 */
contract DeployReputationSplitter is Script {

    struct DeploymentResult {
        ReputationSplitter splitter;
    }

    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address rewardToken = vm.envAddress("REWARD_TOKEN");

        // Log deployment parameters
        console2.log("=================================================");
        console2.log("=== ReputationSplitter Deployment Parameters ===");
        console2.log("=================================================");
        console2.log("Deployer:", deployer);
        console2.log("Reward Token:", rewardToken);
        console2.log("=================================================");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ReputationSplitter
        console2.log("\nDeploying ReputationSplitter...");
        ReputationSplitter splitter = new ReputationSplitter(rewardToken);
        console2.log("ReputationSplitter deployed at:", address(splitter));

        vm.stopBroadcast();

        // Log final summary
        console2.log("\n=================================================");
        console2.log("=== Deployment Summary ===");
        console2.log("=================================================");
        console2.log("ReputationSplitter:", address(splitter));
        console2.log("Reward Token:", address(splitter.rewardToken()));
        console2.log("Owner:", splitter.owner());
        console2.log("Current Round:", splitter.currentRound());
        console2.log("Current Phase:", _getPhaseString(splitter.currentPhase()));
        console2.log("=================================================");
        console2.log("Deployment completed successfully!");
        console2.log("=================================================\n");

        return DeploymentResult({
            splitter: splitter
        });
    }

    function _getPhaseString(ReputationSplitter.Phase phase) internal pure returns (string memory) {
        if (phase == ReputationSplitter.Phase.Registration) {
            return "Registration";
        } else if (phase == ReputationSplitter.Phase.Active) {
            return "Active";
        } else {
            return "Distribution";
        }
    }
}
