// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {YieldDonatingStrategy} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/**
 * @title Deploy YieldDonatingStrategy
 * @notice Script to deploy both YieldDonatingTokenizedStrategy and YieldDonatingStrategy contracts
 * @dev Run with: forge script script/DeployYieldDonatingStrategy.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
 *
 * Steps:
 * 1. Deploy YieldDonatingTokenizedStrategy (singleton/implementation)
 * 2. Deploy YieldDonatingStrategy with reference to the tokenized strategy
 */
contract DeployYieldDonatingStrategy is Script {

    struct DeploymentResult {
        YieldDonatingTokenizedStrategy tokenizedStrategy;
        YieldDonatingStrategy strategy;
    }

    function run() external returns (DeploymentResult memory) {
        // Read configuration from environment variables
        address yieldSource = vm.envAddress("YIELD_SOURCE");
        address asset = vm.envAddress("ASSET");
        string memory name = vm.envString("STRATEGY_NAME");
        address management = vm.envAddress("MANAGEMENT");
        address keeper = vm.envAddress("KEEPER");
        address emergencyAdmin = vm.envAddress("EMERGENCY_ADMIN");
        address donationAddress = vm.envAddress("DONATION_ADDRESS");
        bool enableBurning = vm.envBool("ENABLE_BURNING");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Log deployment parameters
        console2.log("=================================================");
        console2.log("=== YieldDonating Deployment Parameters ===");
        console2.log("=================================================");
        console2.log("Deployer:", deployer);
        console2.log("Yield Source:", yieldSource);
        console2.log("Asset:", asset);
        console2.log("Strategy Name:", name);
        console2.log("Management:", management);
        console2.log("Keeper:", keeper);
        console2.log("Emergency Admin:", emergencyAdmin);
        console2.log("Donation Address (Dragon Router):", donationAddress);
        console2.log("Enable Burning:", enableBurning);
        console2.log("=================================================");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy YieldDonatingTokenizedStrategy
        console2.log("\n[1/2] Deploying YieldDonatingTokenizedStrategy...");
        YieldDonatingTokenizedStrategy tokenizedStrategy = new YieldDonatingTokenizedStrategy();
        console2.log("YieldDonatingTokenizedStrategy deployed at:", address(tokenizedStrategy));

        // Step 2: Deploy YieldDonatingStrategy
        console2.log("\n[2/2] Deploying YieldDonatingStrategy...");
        YieldDonatingStrategy strategy = new YieldDonatingStrategy(
            yieldSource,
            asset,
            name,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            enableBurning,
            address(tokenizedStrategy)
        );
        console2.log("YieldDonatingStrategy deployed at:", address(strategy));

        vm.stopBroadcast();

        // Log final summary
        console2.log("\n=================================================");
        console2.log("=== Deployment Summary ===");
        console2.log("=================================================");
        console2.log("YieldDonatingTokenizedStrategy:", address(tokenizedStrategy));
        console2.log("YieldDonatingStrategy:", address(strategy));
        console2.log("=================================================");
        console2.log("Deployment completed successfully!");
        console2.log("=================================================\n");

        return DeploymentResult({
            tokenizedStrategy: tokenizedStrategy,
            strategy: strategy
        });
    }
}
