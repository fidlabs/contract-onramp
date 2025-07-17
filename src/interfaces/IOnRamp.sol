// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// solhint-disable-next-line import-path-check
import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";

/// @title OnRamp Rate-Limited Client Allowance Manager
/// @author FIDL
/// @notice This contract manages client allowance increases to a Filecoin IClient with per-window rate limiting
/// @dev Uses AccessControlEnumerable, Multicall and Pausable from OpenZeppelin. Proxies unknown calls to a `CLIENT_CONTRACT` via `call`.
interface IOnRamp {
    /// @dev Thrown when the function shouldn't be called
    error Forbidden();

    /// @dev Thrown when the caller is not authorized for the operation
    error Unauthorized();

    /// @dev Thrown when the client is currently locked
    error ClientLocked();

    /// @dev Thrown when the allocation exceeds allowed limit per window
    error RateLimited();

    /// @dev Thrown when setting or using a window size 0
    error InvalidArgument();

    /// @notice Emitted when a client is locked
    /// @param client The address of the client that was locked
    event Locked(address indexed client);

    /// @notice Emitted when a client is unlocked
    /// @param client The address of the client that was unlocked
    event Unlocked(address indexed client);

    /* solhint-disable gas-indexed-events */
    /// @notice Emitted when default rate limit parameters are updated
    /// @param initialWindowSizeInBlocks New default window size
    /// @param initialLimitPerWindow New default per-window limit
    event InitialRateLimitParametersChanged(uint128 initialWindowSizeInBlocks, uint256 initialLimitPerWindow);

    /// @notice Emitted when a specific client's rate limits are updated
    /// @param client Client address
    /// @param windowSizeInBlocks New window size
    /// @param limitPerWindow New per-window limit
    event ClientRateLimitParametersChanged(address indexed client, uint128 windowSizeInBlocks, uint256 limitPerWindow);
    /* solhint-enable gas-indexed-events */

    /* solhint-disable use-natspec */
    /// @notice Disabled - use CLIENT_CONTRACT directly to transfer DC and make allocations
    function transfer(DataCapTypes.TransferParams calldata) external pure;
    /* solhint-enable use-natspec */

    /// @notice Pauses the contract
    /// @dev Only callable by address with MANAGER_ROLE
    function pause() external;

    /// @notice Unpauses the contract
    /// @dev Only callable by address with MANAGER_ROLE
    function unpause() external;

    /// @notice Increases the allowance for a specific client, subject to rate limiting
    /// @param client The address of the client
    /// @param amount The amount to increase the allowance by
    /// @dev Respects per-window limits and access control
    function increaseAllowance(address client, uint256 amount) external;

    /// @notice Locks a client, optionally decreasing its allowance
    /// @param client Address of the client to lock
    /// @param amount Amount to decrease allowance by (if any)
    function lock(address client, uint256 amount) external;

    /// @notice Unlocks a previously locked client
    /// @param client Address of the client to unlock
    function unlock(address client) external;

    /// @notice Updates the default rate limit parameters for all future clients
    /// @param initialWindowSizeInBlocks_ New default window size
    /// @param initialLimitPerWindow_ New default limit per window
    function setInitialRateLimitParameters(uint128 initialWindowSizeInBlocks_, uint256 initialLimitPerWindow_)
        external;

    /// @notice Sets per-client rate limit configuration. Resets counters
    /// @param client Client address
    /// @param windowSizeInBlocks New window size
    /// @param limitPerWindow New limit per window
    function setClientRateLimitParameters(address client, uint128 windowSizeInBlocks, uint256 limitPerWindow)
        external;

    /// @notice Get allocations in window
    /// @param client Client address
    /// @param window Window index
    /// @return allocations Allocations in window
    function clientAllocations(address client, uint256 window) external view returns (uint256 allocations);

    /// @notice Get current window for client
    /// @param client Client address
    /// @return window Current window index
    function clientWindow(address client) external view returns (uint256 window);

    /**
     * @notice This function sets the list of allowed storage providers for a specific client
     * @param client The address of the client for whom the allowed storage providers are being set
     * @param allowedSPs_ The list of allowed storage providers
     */
    function addAllowedSPsForClient(address client, uint64[] memory allowedSPs_) external;

    /**
     * @notice This function removes storage providers from the allowed list for a specific client
     * @param client The address of the client for whom the allowed storage providers are being removed
     * @param disallowedSPs_ The list of storage providers to remove
     */
    function removeAllowedSPsForClient(address client, uint64[] memory disallowedSPs_) external;

    /**
     * @notice This function sets the maximum allowed deviation from a fair
     * distribution of data between storage providers.
     * @param client The address of the client
     * @param maxDeviation Max allowed deviation. 0 = no slack, DENOMINATOR = 100% (based on total allocations of user)
     */
    function setClientMaxDeviationFromFairDistribution(address client, uint256 maxDeviation) external;

    /**
     * @notice This function sets the list of allowed storage providers for a specific client
     * @param client The address of the client for whom the allowed storage providers are being set
     * @param allowedSPs_ abi.encodePacked tuple of uint64's representing SPs to allow
     */
    function addAllowedSPsForClientPacked(address client, bytes calldata allowedSPs_) external;

    /**
     * @notice This function removes storage providers from the allowed list for a specific client
     * @param client The address of the client for whom the allowed storage providers are being removed
     * @param disallowedSPs_ abi.encodePacked tuple of uint64's representing SPs to disallow
     */
    function removeAllowedSPsForClientPacked(address client, bytes calldata disallowedSPs_) external;

    /**
     * @notice Decrease client allowance
     * @param client Client whose allowance is reduced
     * @param amount Amount to decrease the allowance
     */
    function decreaseAllowance(address client, uint256 amount) external;
}
