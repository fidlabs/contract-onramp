# OnRamp Smart Contract

## Overview

`OnRamp` is a rate-limited allowance manager designed to control how allocators interact with client contracts. It ensures that increases in client allowances occur under strict, block-based time windows, enforcing usage limits while offering flexibility through roles and administrative control.

## Features

* **Per-client rate-limiting** on allowance increases
* **Per-client locking** functionality
* **Role-based access control** (Admin, Manager, Allocator)
* **Emergency pause/unpause** functionality
* **Multicall support** for batch actions

## Roles

* **DEFAULT\_ADMIN\_ROLE**: Can assign other roles
* **MANAGER\_ROLE**: Can pause/unpause, lock/unlock clients, and set rate limits
* **ALLOCATOR\_ROLE**: Can increase client allowances

## Deployment Parameters

| Parameter                   | Type      | Description                                    |
| --------------------------- | --------- | ---------------------------------------------- |
| `clientContract`            | `address` | Address of the Filecoin `IClient` contract     |
| `admin`                     | `address` | Admin role holder                              |
| `manager`                   | `address` | Manager role holder                            |
| `allocator`                 | `address` | Allocator role holder                          |
| `initialWindowSizeInBlocks` | `uint128` | Default size of rate-limiting windows (blocks) |
| `initialLimitPerWindow`     | `uint256` | Default allowance cap per window               |

## Core Concepts

### Rate Limiting

Each client has:

* A **window size** (in blocks)
* A **limit per window** (maximum allocation allowed)

Allocations exceeding this limit within a window are reverted with a `RateLimited()` error.

### Locking Clients

Clients can be locked via `lock(address client, uint256 amount)` to prevent further allowance increases. Optionally decreases allowance on lock.

### Fallback Proxying

Unrecognized function calls are forwarded directly to the `CLIENT_CONTRACT` if called by a manager. This allows `OnRamp` to act as a transparent proxy when needed.

## Functions

| Function                                            | Access               | Description                                          |
| --------------------------------------------------- | -------------------- | ---------------------------------------------------- |
| `increaseAllowance(client, amount)`                 | Manager or Allocator | Increases a client's allowance if within rate limits |
| `pause()` / `unpause()`                             | Manager              | Pauses or unpauses the contract                      |
| `lock(client, amount)` / `unlock(client)`           | Manager              | Locks or unlocks a client                            |
| `setInitialRateLimitParameters(size, limit)`        | Manager              | Sets new defaults for rate-limiting                  |
| `setClientRateLimitParameters(client, size, limit)` | Manager              | Overrides defaults for a specific client             |
| `clientAllocations(client, window)`                 | Public               | View usage for a specific window                     |
| `clientWindow(client)`                              | Public               | View current window index for client                 |

## Events

* `Locked(address client)`
* `Unlocked(address client)`
* `InitialRateLimitParametersChanged(uint128 size, uint256 limit)`
* `ClientRateLimitParametersChanged(address client, uint128 size, uint256 limit)`

## Errors

* `Unauthorized()`: Caller lacks required role
* `Forbidden()`: Call is disallowed
* `ClientLocked()`: Operation attempted on locked client
* `RateLimited()`: Exceeded allocation for time window
* `InvalidArgument()`: Supplied zero for window size

## Dependencies

* [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
* [Filecoin Solidity Bindings](https://github.com/filecoin-project/filecoin-solidity)

## Example deployment procedure

1. Deploy an instance of Client Smart contract, using a real wallet as an owner:

    ```
    cast send --private-key [your-private-key] --rpc-url https://api.node.glif.io/rpc/v1 0xa0985F0E7Aa0b938dC0B48C65e50a3A38AF42de4 'create(address)' [your-address]
    ```

2. Copy `.env.example` to `.env` and fill out parameters.
3. Deploy the OnRamp Smart Contract - the script will handle transferring the ownership of Client contract address from you to the OnRamp contract. Check logs at the top of the output to get address of the OnRamp contract:

    ```
    forge script --private-key [your-private-key] --rpc-url https://api.node.glif.io/rpc/v1 script/Deploy.s.sol --broadcast
    ```

## Using with Safe

1. Make sure your safe account was marked the admin and/or manager of the OnRamp contract during deployment.
2. Open your Safe account.
3. Go to Apps -> Transaction builder
4. Enter address of the OnRamp contract
5. Enter [IOnRamp.json](./abis/IOnRamp.json) file as ABI
6. Select the [function](#functions) you want to call. In addition to OnRamp functions, some Client smart contract functions are available as well (such as managing SPs, deviation and decreasing allowance without locking the client)
7. Fill arguments, if any
8. Click Add Transaction
9. Proceed with standard Safe flow
