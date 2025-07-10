// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

// solhint-disable-next-line import-path-check
import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";

import {ClientInfo} from "./ClientInfo.sol";
import {IClient} from "./interfaces/IClient.sol";
import {IOnRamp} from "./interfaces/IOnRamp.sol";

/// @title OnRamp Rate-Limited Client Allowance Manager
/// @author FIDL
/// @notice This contract manages client allowance increases to a Filecoin IClient with per-window rate limiting
/// @dev Uses AccessControl, Multicall and Pausable from OpenZeppelin. Proxies unknown calls to a `CLIENT_CONTRACT` via `call`.
contract OnRamp is IOnRamp, AccessControl, Pausable, Multicall {
    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role identifier for allocators
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @notice Stores rate limit configuration for each client
    mapping(address clientAddress => ClientInfo clientInfo) public clients;

    /// @notice Default max allocation per window
    uint256 public initialLimitPerWindow;

    /// @notice Default window size used for rate limiting (in blocks)
    uint128 public initialWindowSizeInBlocks;

    /// @notice Client smart contract managed by this OnRamp instance
    IClient public immutable CLIENT_CONTRACT;
    /// @notice Initializes the OnRamp contract with roles and default limits

    /// @param clientContract Address of the IClient contract
    /// @param admin Address assigned DEFAULT_ADMIN_ROLE
    /// @param manager Address assigned MANAGER_ROLE
    /// @param allocator Address assigned ALLOCATOR_ROLE
    /// @param initialWindowSizeInBlocks_ Default window size in blocks
    /// @param initialLimitPerWindow_ Default limit per window
    constructor(
        IClient clientContract,
        address admin,
        address manager,
        address allocator,
        uint128 initialWindowSizeInBlocks_,
        uint256 initialLimitPerWindow_
    ) {
        CLIENT_CONTRACT = clientContract;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(ALLOCATOR_ROLE, allocator);

        if (initialWindowSizeInBlocks_ == 0) {
            revert InvalidArgument();
        }

        initialWindowSizeInBlocks = initialWindowSizeInBlocks_;
        initialLimitPerWindow = initialLimitPerWindow_;
    }

    /* solhint-disable use-natspec */
    /// @notice Disabled - use CLIENT_CONTRACT directly to transfer DC and make allocations
    function transfer(DataCapTypes.TransferParams calldata) external pure {
        revert Forbidden();
    }
    /* solhint-enable use-natspec */

    /// @notice Pauses the contract
    /// @dev Only callable by address with MANAGER_ROLE
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Only callable by address with MANAGER_ROLE
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    modifier onlyManagerOrAllocator() {
        if (!hasRole(MANAGER_ROLE, msg.sender) && !hasRole(ALLOCATOR_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice Increases the allowance for a specific client, subject to rate limiting
    /// @param client The address of the client
    /// @param amount The amount to increase the allowance by
    /// @dev Respects per-window limits and access control
    function increaseAllowance(address client, uint256 amount) external whenNotPaused onlyManagerOrAllocator {
        ClientInfo storage c = clients[client];

        if (c.locked) {
            revert ClientLocked();
        }

        if (c.windowSizeInBlocks == 0) {
            c.windowSizeInBlocks = initialWindowSizeInBlocks;
            c.limitPerWindow = initialLimitPerWindow;
        }

        uint256 window = _window(c);
        c.allocations[window] += amount;
        if (c.allocations[window] > c.limitPerWindow) {
            revert RateLimited();
        }

        CLIENT_CONTRACT.increaseAllowance(client, amount);
    }

    /// @notice Locks a client, optionally decreasing its allowance
    /// @param client Address of the client to lock
    /// @param amount Amount to decrease allowance by (if any)
    function lock(address client, uint256 amount) external onlyRole(MANAGER_ROLE) {
        ClientInfo storage c = clients[client];
        c.locked = true;

        emit Locked(client);

        if (amount > 0) {
            CLIENT_CONTRACT.decreaseAllowance(client, amount);
        }
    }

    /// @notice Unlocks a previously locked client
    /// @param client Address of the client to unlock
    function unlock(address client) external onlyRole(MANAGER_ROLE) {
        ClientInfo storage c = clients[client];
        c.locked = false;

        emit Unlocked(client);
    }

    /// @notice Updates the default rate limit parameters for all future clients
    /// @param initialWindowSizeInBlocks_ New default window size
    /// @param initialLimitPerWindow_ New default limit per window
    function setInitialRateLimitParameters(uint128 initialWindowSizeInBlocks_, uint256 initialLimitPerWindow_)
        external
        onlyRole(MANAGER_ROLE)
    {
        if (initialWindowSizeInBlocks_ == 0) {
            revert InvalidArgument();
        }

        initialWindowSizeInBlocks = initialWindowSizeInBlocks_;
        initialLimitPerWindow = initialLimitPerWindow_;

        emit InitialRateLimitParametersChanged(initialWindowSizeInBlocks, initialLimitPerWindow);
    }

    /// @notice Calculates the current rate limiting window for a client
    /// @param c The client's configuration
    /// @return window The current window index
    function _window(ClientInfo storage c) internal view returns (uint256 window) {
        if (c.windowSizeInBlocks == 0) {
            revert InvalidArgument();
        }
        return block.number / c.windowSizeInBlocks + c.windowOffset;
    }

    /// @notice Sets per-client rate limit configuration. Resets counters
    /// @param client Client address
    /// @param windowSizeInBlocks New window size
    /// @param limitPerWindow New limit per window
    function setClientRateLimitParameters(address client, uint128 windowSizeInBlocks, uint256 limitPerWindow)
        external
        onlyRole(MANAGER_ROLE)
    {
        ClientInfo storage c = clients[client];

        if (windowSizeInBlocks == 0) {
            revert InvalidArgument();
        }

        if (c.windowSizeInBlocks != 0) {
            c.windowOffset = _window(c);
        }
        c.windowSizeInBlocks = windowSizeInBlocks;
        c.limitPerWindow = limitPerWindow;

        emit ClientRateLimitParametersChanged(client, windowSizeInBlocks, limitPerWindow);
    }

    /// @notice Get allocations in window
    /// @param client Client address
    /// @param window Window index
    /// @return allocations Allocations in window
    function clientAllocations(address client, uint256 window) external view returns (uint256 allocations) {
        return clients[client].allocations[window];
    }

    /// @notice Get current window for client
    /// @param client Client address
    /// @return window Current window index
    function clientWindow(address client) external view returns (uint256 window) {
        return _window(clients[client]);
    }

    /**
     * @notice This function sets the list of allowed storage providers for a specific client
     * @param client The address of the client for whom the allowed storage providers are being set
     * @param allowedSPs_ The list of allowed storage providers
     */
    function addAllowedSPsForClient(address client, uint64[] calldata allowedSPs_) external onlyManagerOrAllocator {
        CLIENT_CONTRACT.addAllowedSPsForClient(client, allowedSPs_);
    }

    /**
     * @notice This function removes storage providers from the allowed list for a specific client
     * @param client The address of the client for whom the allowed storage providers are being removed
     * @param disallowedSPs_ The list of storage providers to remove
     */
    function removeAllowedSPsForClient(address client, uint64[] calldata disallowedSPs_)
        external
        onlyManagerOrAllocator
    {
        CLIENT_CONTRACT.removeAllowedSPsForClient(client, disallowedSPs_);
    }

    /**
     * @notice This function sets the maximum allowed deviation from a fair
     * distribution of data between storage providers.
     * @param client The address of the client
     * @param maxDeviation Max allowed deviation. 0 = no slack, DENOMINATOR = 100% (based on total allocations of user)
     */
    function setClientMaxDeviationFromFairDistribution(address client, uint256 maxDeviation)
        external
        onlyManagerOrAllocator
    {
        CLIENT_CONTRACT.setClientMaxDeviationFromFairDistribution(client, maxDeviation);
    }

    /**
     * @notice This function sets the list of allowed storage providers for a specific client
     * @param client The address of the client for whom the allowed storage providers are being set
     * @param allowedSPs_ abi.encodePacked tuple of uint64's representing SPs to allow
     */
    function addAllowedSPsForClientPacked(address client, bytes calldata allowedSPs_) external onlyManagerOrAllocator {
        CLIENT_CONTRACT.addAllowedSPsForClientPacked(client, allowedSPs_);
    }

    /**
     * @notice This function removes storage providers from the allowed list for a specific client
     * @param client The address of the client for whom the allowed storage providers are being removed
     * @param disallowedSPs_ abi.encodePacked tuple of uint64's representing SPs to disallow
     */
    function removeAllowedSPsForClientPacked(address client, bytes calldata disallowedSPs_)
        external
        onlyManagerOrAllocator
    {
        CLIENT_CONTRACT.removeAllowedSPsForClientPacked(client, disallowedSPs_);
    }

    /**
     * @notice Decrease client allowance
     * @param client Client whose allowance is reduced
     * @param amount Amount to decrease the allowance
     */
    function decreaseAllowance(address client, uint256 amount) external onlyManagerOrAllocator {
        CLIENT_CONTRACT.decreaseAllowance(client, amount);
    }

    /// @notice Forwards unknown calls to the CLIENT_CONTRACT using call
    /// @param clientContract Address to forward calls to
    function _fallback(address clientContract) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), clientContract, 0, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // call returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Fallback function; proxies to CLIENT_CONTRACT
    fallback() external onlyRole(MANAGER_ROLE) {
        _fallback(address(CLIENT_CONTRACT));
    }
}
