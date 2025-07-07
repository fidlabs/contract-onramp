// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOnRamp} from "./IOnRamp.sol";

/**
 * @title OnRamp Extended interface
 * @author FIDL
 * @notice OnRamp interface extended with relevant Client Smart contract methods
 */
interface IOnRampExtended is IOnRamp {
    /**
     * @notice Adds storage providers to the allowed list for a specific client.
     * @dev This function can only be called by the owner.
     * @param client The address of the client for whom the allowed storage providers are being set
     * @param allowedSPs_ The list of storage providers to add.
     */
    function addAllowedSPsForClient(address client, uint64[] calldata allowedSPs_) external;

    /**
     * @notice This function removes storage providers from the allowed list for a specific client.
     * @dev This function can only be called by the owner.
     * @param client The address of the client for whom the allowed storage providers are being removed
     * @param disallowedSPs_ The list of storage providers to remove.
     */
    function removeAllowedSPsForClient(address client, uint64[] calldata disallowedSPs_) external;

    /**
     * @notice This function sets the maximum allowed deviation from a fair
     * distribution of data between storage providers.
     * @dev This function can only be called by the owner
     * @param client The address of the client
     * @param maxDeviation Max allowed deviation. 0 = no slack, DENOMINATOR = 100% (based on total allocations of user)
     * @dev Emits ClientConfigChanged event
     */
    function setClientMaxDeviationFromFairDistribution(address client, uint256 maxDeviation) external;

    /**
     * @notice Decrease client allowance
     * @dev This function can only be called by the owner
     * @param client Client whose allowance is reduced
     * @param amount Amount to decrease the allowance
     * @dev Emits AllowanceChanged event
     * @dev Reverts if trying to decrease allowance by 0
     * @dev Reverts if client allowance is already 0
     */
    function decreaseAllowance(address client, uint256 amount) external;
}
