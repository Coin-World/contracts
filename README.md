# Coin World - Staking Contracts

![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)

## Overview

Welcome to the official smart contract repository for **Coin World**, a decentralized platform built to power Abstract Chain projects.

A key feature of the Coin World platform is a factory system (`PoolGen.sol`) that deploys standardized, secure, and isolated staking contracts (`SimpleStaking.sol`). This "Staking-as-a-Service" model empowers any token project to offer rewards to their holders without needing to develop their own staking infrastructure from scratch.

## Core Concepts

The system is built on two primary contracts that work together:

1.  **`PoolGen.sol` (The Factory):** This is the central hub for creating new staking pools. Users interact with this contract to define their pool's parameters and deploy it. It handles the initial setup, including funding the pool and collecting a small platform fee (tax).

2.  **`SimpleStaking.sol` (The Pool):** This is the contract that gets deployed by the factory. Each `SimpleStaking` contract is an independent pool where users can stake a specific token to earn rewards. It manages all staking logic, including deposits, withdrawals, and reward calculations.

3.  **Tax Mechanism:** To support the platform, a **0.25%** tax (`25 / 10000`) is applied to the `rewardAmount` when a new pool is created. This tax is sent to a designated `TAX_RECIPIENT`. Pools using the platform's native token ($COIN) as a reward are exempt from this tax.

## Contracts Overview

### Custom Contracts

*   **`PoolGen.sol`**: The factory contract responsible for deploying `SimpleStaking` pools.
    *   Manages the creation and initialization of new staking pools.
    *   Collects a platform tax on the total rewards being offered.
    *   Transfers the net rewards to the newly created pool.
    *   Includes an emergency function for the tax recipient to recover any stuck tokens.

*   **`SimpleStaking.sol`**: The main staking contract where all user interactions happen.
    *   Allows users to `stake` and `unstake` a designated `stakingToken`.
    *   Calculates and distributes `rewardToken` rewards on a per-block basis.
    *   Rewards are distributed over a fixed duration (`rewardDuration`).
    *   Includes `claimReward` for users and an `emergencyWithdraw` to retrieve staked tokens without rewards.
    *   The contract owner (the `PoolGen` factory upon deployment) has administrative functions, though ownership is intended to be renounced or held by a governance contract in a production environment.

### OpenZeppelin Contracts

This project uses battle-tested contracts from OpenZeppelin for security and standardization.

*   **`IERC20.sol`**: The standard interface for ERC20 tokens.
*   **`Ownable.sol`**: Provides a basic access control mechanism, used to manage administrative functions in `SimpleStaking`.
*   **`ReentrancyGuard.sol`**: A security module to prevent re-entrancy attacks on critical functions like `stake`, `unstake`, and `claimReward`.
*   **`Context.sol`**: An abstraction used by `Ownable` to support meta-transactions.

## Workflow: How to Create and Use a Staking Pool

#### 1. Creating a Pool (Project Owner)

A project owner who wants to create a staking pool for their community follows these steps:

1.  **Approve Tokens**: The owner must first `approve` the `PoolGen` contract to spend the total amount of `rewardToken` they wish to fund the pool with.
2.  **Call `deployPool`**: The owner calls the `deployPool` function on the `PoolGen` contract with the following parameters:
    *   `_stakingToken`: The address of the token users will stake.
    *   `_rewardToken`: The address of the token that will be given as a reward.
    *   `_rewardStartBlock`: The future block number when rewards should begin.
    *   `_rewardDuration`: The number of blocks the reward program will last.
    *   `_rewardAmount`: The total amount of `rewardToken` to be distributed.
3.  **Factory Magic**: The `PoolGen` contract automatically:
    *   Pulls the `_rewardAmount` from the owner's wallet.
    *   Calculates the 0.25% tax (unless the reward is the `NATIVE_TOKEN`).
    *   Transfers the tax to the `TAX_RECIPIENT`.
    *   Deploys a new `SimpleStaking` contract instance.
    *   Transfers the remaining net reward amount to the new pool.
    *   Emits a `PoolDeployed` event with the address of the new pool.

#### 2. Using a Pool (Staker)

Any user can now interact with the newly deployed `SimpleStaking` pool address:

1.  **Approve Staking**: The user `approve`s the `SimpleStaking` contract to spend their `stakingToken`.
2.  **Stake**: The user calls `stake(amount)` to deposit their tokens and start earning rewards.
3.  **Claim Rewards**: The user can call `claimReward()` at any time to withdraw their earned rewards without unstaking.
4.  **Unstake**: The user calls `unstake(amount)` to withdraw their staked tokens. This action automatically claims any pending rewards as well.

## Security

Security is a top priority for the Coin World platform. The following measures have been taken:

*   **Re-entrancy Protection**: All critical state-changing functions use the `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`.
*   **Ownership Control**: Administrative functions in `SimpleStaking` are protected with the `onlyOwner` modifier.
*   **Standard Contracts**: The use of OpenZeppelin contracts for `ERC20`, `Ownable`, and `ReentrancyGuard` leverages industry-standard, audited code.
*   **Checks-Effects-Interactions Pattern**: Functions are written to follow this pattern where possible to minimize attack vectors.

> **Disclaimer**: These smart contracts have not yet been professionally audited. Use them in a production environment at your own risk. We strongly recommend a full security audit before deploying any funds.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.