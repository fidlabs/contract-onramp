// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Minimal interface for client smart contract
/// @author FIDL
/// @notice Methods of client smart contract used by OnRamp
interface IClient {
    /// @notice Increases the allowance
    /// @param client The address of the client
    /// @param amount The amount to increase the allowance by
    function increaseAllowance(address client, uint256 amount) external;

    /// @notice Decreases the allowance
    /// @param client The address of the client
    /// @param amount The amount to decrease the allowance by
    function decreaseAllowance(address client, uint256 amount) external;
}
