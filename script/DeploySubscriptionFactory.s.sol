// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {SubscriptionTokenV1Factory} from "../src/subscriptions/SubscriptionTokenV1Factory.sol";
import {SubscriptionTokenV1} from "../src/subscriptions/SubscriptionTokenV1.sol";

contract DeploySubscriptionFactory is Script {
    function run() public {
        vm.startBroadcast();

        // Deploy the SubscriptionTokenV1 implementation
        SubscriptionTokenV1 implementation = new SubscriptionTokenV1();

        // Deploy the SubscriptionTokenV1Factory
        SubscriptionTokenV1Factory factory = new SubscriptionTokenV1Factory(address(implementation));

        console.log("SubscriptionTokenV1 implementation deployed at:", address(implementation));
        console.log("SubscriptionTokenV1Factory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
