// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Holds rate limit information for each client.
struct ClientInfo {
    mapping(uint256 window => uint256 allocations) allocations;
    uint256 windowOffset;
    uint256 limitPerWindow;
    uint128 windowSizeInBlocks;
    bool locked;
}
