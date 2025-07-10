// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {OnRamp, IClient} from "../src/OnRamp.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        IClient client = IClient(vm.envAddress("ONRAMP_CLIENT_CONTRACT_ADDRESS"));
        address admin = vm.envAddress("ONRAMP_ADMIN");
        address manager = vm.envAddress("ONRAMP_MANAGER");
        address allocator = vm.envAddress("ONRAMP_ALLOCATOR");
        uint128 windowSize = uint128(vm.envUint("ONRAMP_INITIAL_WINDOW_SIZE_IN_BLOCKS"));
        uint256 limit = vm.envUint("ONRAMP_INITIAL_LIMIT_PER_WINDOW");

        OnRamp onRamp = new OnRamp(client, msg.sender, msg.sender, allocator, windowSize, limit);
        Ownable2Step(address(client)).transferOwnership(address(onRamp));
        Ownable2Step(address(onRamp)).acceptOwnership();

        if (msg.sender != manager) {
            onRamp.grantRole(onRamp.MANAGER_ROLE(), manager);
            onRamp.renounceRole(onRamp.MANAGER_ROLE(), msg.sender);
        }

        if (msg.sender != admin) {
            onRamp.grantRole(onRamp.DEFAULT_ADMIN_ROLE(), admin);
            onRamp.renounceRole(onRamp.DEFAULT_ADMIN_ROLE(), msg.sender);
        }

        vm.stopBroadcast();
        console.log("OnRamp contract deployed to", address(onRamp));
        console.log("Client contract:", address(client));
        console.log("Admin:", admin);
        console.log("Manager:", manager);
        console.log("Allocator:", allocator);
        console.log("Initial window size:", windowSize);
        console.log("Initial limit:", limit);
    }
}
