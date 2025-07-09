// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable, Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import {OnRamp, IOnRamp, IClient} from "../src/OnRamp.sol";

contract MockClient is IClient, Ownable2Step {
    constructor() Ownable(msg.sender) {}
    function increaseAllowance(address, uint256) external view onlyOwner {}
    function decreaseAllowance(address, uint256) external pure {}
    function noop(uint256) external pure {}
    function addAllowedSPsForClient(address, uint64[] calldata) external pure {}
    function removeAllowedSPsForClient(address, uint64[] calldata) external pure {}
    function addAllowedSPsForClientPacked(address, bytes calldata) external pure {}
    function removeAllowedSPsForClientPacked(address, bytes calldata) external pure {}
    function setClientMaxDeviationFromFairDistribution(address, uint256) external pure {}
}

contract OnRampTest is Test {
    OnRamp public onRamp;
    MockClient public mockClient;
    address public manager = address(100);
    address public allocator = address(200);

    function setUp() public {
        mockClient = new MockClient();
        onRamp = new OnRamp(mockClient, address(this), manager, allocator, 100, 200);
        mockClient.transferOwnership(address(onRamp));
        vm.prank(manager);
        (bool success,) = address(onRamp).call(abi.encodeCall(Ownable2Step.acceptOwnership, ()));
        if (!success) revert();
    }

    function testClientContractSet() public view {
        assertEq(address(onRamp.CLIENT_CONTRACT()), address(mockClient));
    }

    function testInitialParamsSet() public view {
        assertEq(onRamp.initialWindowSizeInBlocks(), 100);
        assertEq(onRamp.initialLimitPerWindow(), 200);
    }

    function testRolesSet() public view {
        assertTrue(onRamp.hasRole(onRamp.DEFAULT_ADMIN_ROLE(), address(this)));
        assertFalse(onRamp.hasRole(onRamp.DEFAULT_ADMIN_ROLE(), manager));
        assertFalse(onRamp.hasRole(onRamp.DEFAULT_ADMIN_ROLE(), allocator));

        assertFalse(onRamp.hasRole(onRamp.MANAGER_ROLE(), address(this)));
        assertTrue(onRamp.hasRole(onRamp.MANAGER_ROLE(), manager));
        assertFalse(onRamp.hasRole(onRamp.MANAGER_ROLE(), allocator));

        assertFalse(onRamp.hasRole(onRamp.ALLOCATOR_ROLE(), address(this)));
        assertFalse(onRamp.hasRole(onRamp.ALLOCATOR_ROLE(), manager));
        assertTrue(onRamp.hasRole(onRamp.ALLOCATOR_ROLE(), allocator));
    }

    function testCantSetWindowToZero() public {
        vm.startPrank(manager);

        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        new OnRamp(mockClient, manager, manager, manager, 0, 100);

        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        onRamp.setInitialRateLimitParameters(0, 100);

        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        onRamp.setClientRateLimitParameters(manager, 0, 100);
    }

    function testTransferDisabled() public {
        DataCapTypes.TransferParams memory params;

        vm.expectRevert(IOnRamp.Forbidden.selector);
        onRamp.transfer(params);
    }

    function testPauseWorks() public {
        assertFalse(onRamp.paused());
        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(manager);
        onRamp.pause();
        assertTrue(onRamp.paused());
    }

    function testUnpauseWorks() public {
        vm.startPrank(manager);
        onRamp.pause();

        assertTrue(onRamp.paused());
        vm.expectEmit(true, true, true, true);
        emit Pausable.Unpaused(manager);
        onRamp.unpause();
        assertFalse(onRamp.paused());
    }

    function testIncreaseAllowanceRespectsPause() public {
        vm.prank(manager);
        onRamp.pause();

        vm.prank(allocator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        onRamp.increaseAllowance(manager, 100);
    }

    function testIncreaseAllowanceRespectsPermissions() public {
        vm.prank(manager);
        onRamp.increaseAllowance(manager, 100);

        vm.prank(allocator);
        onRamp.increaseAllowance(manager, 100);

        vm.prank(address(1000));
        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.increaseAllowance(manager, 100);
    }

    function testIncreaseAllowanceRespectsLock() public {
        vm.prank(manager);
        onRamp.lock(manager, 0);

        vm.prank(allocator);
        vm.expectRevert(IOnRamp.ClientLocked.selector);
        onRamp.increaseAllowance(manager, 100);
    }

    function testIncreaseAllowanceRespectsRateLimitsSimple() public {
        uint256 limit = onRamp.initialLimitPerWindow();

        vm.prank(allocator);
        vm.expectRevert(IOnRamp.RateLimited.selector);
        onRamp.increaseAllowance(manager, limit + 1);
    }

    function testIncreaseAllowanceCallsClientContract() public {
        vm.prank(allocator);
        vm.expectCall(address(mockClient), abi.encodeCall(IClient.increaseAllowance, (manager, 100)));
        onRamp.increaseAllowance(manager, 100);
    }

    function testLockWorks() public {
        vm.startPrank(manager);
        onRamp.increaseAllowance(manager, 100);

        vm.expectEmit(true, true, true, true);
        emit IOnRamp.Locked(manager);
        vm.expectCall(address(mockClient), abi.encodeCall(IClient.decreaseAllowance, (manager, 50)));
        onRamp.lock(manager, 50);

        (,,, bool locked) = onRamp.clients(manager);
        assertTrue(locked);
    }

    function testLockRespectsPermissions() public {
        vm.prank(allocator);
        vm.expectRevert();
        onRamp.lock(manager, 0);
    }

    function testUnlockWorks() public {
        vm.startPrank(manager);
        onRamp.lock(manager, 0);
        (,,, bool locked) = onRamp.clients(manager);
        assertTrue(locked);

        vm.expectEmit(true, true, true, true);
        emit IOnRamp.Unlocked(manager);
        onRamp.unlock(manager);
        (,,, locked) = onRamp.clients(manager);
        assertFalse(locked);
    }

    function testUnlockRespectsPermissions() public {
        vm.prank(allocator);
        vm.expectRevert();
        onRamp.unlock(manager);
    }

    function testSetInitialRateLimitParametersWorks() public {
        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);
        emit IOnRamp.InitialRateLimitParametersChanged(1000, 2000);
        onRamp.setInitialRateLimitParameters(1000, 2000);
        assertEq(onRamp.initialWindowSizeInBlocks(), 1000);
        assertEq(onRamp.initialLimitPerWindow(), 2000);
    }

    function testSetInitialRateLimitParametersRespectsPermissions() public {
        vm.prank(allocator);
        vm.expectRevert();
        onRamp.setInitialRateLimitParameters(1000, 2000);
    }

    function testSetInitialRateLimitParametersDoesntAllowZeroWindow() public {
        vm.prank(manager);
        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        onRamp.setInitialRateLimitParameters(0, 2000);
    }

    function testSetClientRateLimitParametersWorks() public {
        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);
        emit IOnRamp.ClientRateLimitParametersChanged(manager, 1000, 2000);
        onRamp.setClientRateLimitParameters(manager, 1000, 2000);
        (, uint256 limitPerWindow, uint128 windowSizeInBlocks,) = onRamp.clients(manager);
        assertEq(windowSizeInBlocks, 1000);
        assertEq(limitPerWindow, 2000);
    }

    function testSetClientRateLimitParametersRespectsPermissions() public {
        vm.prank(allocator);
        vm.expectRevert();
        onRamp.setClientRateLimitParameters(manager, 1000, 2000);
    }

    function testSetClientRateLimitParametersDoesntAllowZeroWindow() public {
        vm.prank(manager);
        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        onRamp.setClientRateLimitParameters(manager, 0, 2000);
    }

    function testFallback() public {
        bytes memory call = abi.encodeCall(MockClient.noop, (100));
        vm.expectCall(address(mockClient), call);
        vm.prank(manager);
        (bool success,) = address(onRamp).call(call);
        assertTrue(success);
    }

    function testFallbackRespectsPermissions() public {
        bytes memory call = abi.encodeCall(MockClient.noop, (100));
        (bool success,) = address(onRamp).call(call);
        assertFalse(success);
    }

    function testWindowCalculationsRevertsOnEmptyClient() public {
        vm.expectRevert(IOnRamp.InvalidArgument.selector);
        onRamp.clientWindow(manager);
    }

    function testWindowCalculationsSimple() public {
        vm.startPrank(manager);
        onRamp.increaseAllowance(manager, 1);

        vm.roll(100);
        assertEq(onRamp.clientWindow(manager), 1);

        vm.roll(199);
        assertEq(onRamp.clientWindow(manager), 1);

        vm.roll(200);
        assertEq(onRamp.clientWindow(manager), 2);
    }

    function testAllocationsTracking() public {
        vm.startPrank(manager);
        vm.roll(100);

        onRamp.increaseAllowance(manager, 1);
        assertEq(onRamp.clientAllocations(manager, 1), 1);

        onRamp.setClientRateLimitParameters(manager, 99, 200);
        onRamp.increaseAllowance(manager, 1);
        assertEq(onRamp.clientAllocations(manager, 1), 1);
        assertEq(onRamp.clientAllocations(manager, 2), 1);

        onRamp.increaseAllowance(manager, 1);
        assertEq(onRamp.clientAllocations(manager, 2), 2);

        vm.roll(99 * 2);
        onRamp.increaseAllowance(manager, 1);
        assertEq(onRamp.clientAllocations(manager, 3), 1);
    }

    function testRateLimitingOverManyCalls() public {
        vm.startPrank(manager);

        onRamp.increaseAllowance(manager, 199);
        onRamp.increaseAllowance(manager, 1);

        vm.expectRevert(IOnRamp.RateLimited.selector);
        onRamp.increaseAllowance(manager, 1);

        vm.roll(99);
        vm.expectRevert(IOnRamp.RateLimited.selector);
        onRamp.increaseAllowance(manager, 1);

        vm.roll(100);
        onRamp.increaseAllowance(manager, 200);
        vm.expectRevert(IOnRamp.RateLimited.selector);
        onRamp.increaseAllowance(manager, 1);

        onRamp.setClientRateLimitParameters(manager, 100, 400);
        onRamp.increaseAllowance(manager, 400);
        vm.expectRevert(IOnRamp.RateLimited.selector);
        onRamp.increaseAllowance(manager, 1);
    }

    function testClientContractFunctionsForwardedCorrectly() public {
        uint64[] memory arr;

        vm.startPrank(allocator);

        vm.expectCall(address(mockClient), abi.encodeCall(IClient.addAllowedSPsForClient, (manager, arr)));
        onRamp.addAllowedSPsForClient(manager, arr);

        vm.expectCall(address(mockClient), abi.encodeCall(IClient.removeAllowedSPsForClient, (manager, arr)));
        onRamp.removeAllowedSPsForClient(manager, arr);

        vm.expectCall(address(mockClient), abi.encodeCall(IClient.addAllowedSPsForClientPacked, (manager, "")));
        onRamp.addAllowedSPsForClientPacked(manager, "");

        vm.expectCall(address(mockClient), abi.encodeCall(IClient.removeAllowedSPsForClientPacked, (manager, "")));
        onRamp.removeAllowedSPsForClientPacked(manager, "");

        vm.expectCall(
            address(mockClient), abi.encodeCall(IClient.setClientMaxDeviationFromFairDistribution, (manager, 5))
        );
        onRamp.setClientMaxDeviationFromFairDistribution(manager, 5);

        vm.expectCall(address(mockClient), abi.encodeCall(IClient.decreaseAllowance, (manager, 5)));
        onRamp.decreaseAllowance(manager, 5);
    }

    function testClientContractFunctionsForwardingRespectsPermissions() public {
        uint64[] memory arr;

        vm.startPrank(allocator);
        onRamp.addAllowedSPsForClient(manager, arr);
        onRamp.removeAllowedSPsForClient(manager, arr);
        onRamp.addAllowedSPsForClientPacked(manager, "");
        onRamp.removeAllowedSPsForClientPacked(manager, "");
        onRamp.setClientMaxDeviationFromFairDistribution(manager, 5);
        onRamp.decreaseAllowance(manager, 5);

        vm.startPrank(manager);
        onRamp.addAllowedSPsForClient(manager, arr);
        onRamp.removeAllowedSPsForClient(manager, arr);
        onRamp.addAllowedSPsForClientPacked(manager, "");
        onRamp.removeAllowedSPsForClientPacked(manager, "");
        onRamp.setClientMaxDeviationFromFairDistribution(manager, 5);
        onRamp.decreaseAllowance(manager, 5);

        vm.stopPrank();

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.addAllowedSPsForClient(manager, arr);

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.removeAllowedSPsForClient(manager, arr);

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.addAllowedSPsForClientPacked(manager, "");

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.removeAllowedSPsForClientPacked(manager, "");

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.setClientMaxDeviationFromFairDistribution(manager, 5);

        vm.expectRevert(IOnRamp.Unauthorized.selector);
        onRamp.decreaseAllowance(manager, 5);
    }
}
