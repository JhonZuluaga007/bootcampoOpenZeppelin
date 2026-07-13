// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title AuroPegTimelock
/// @notice Thin re-export of OpenZeppelin's TimelockController, used as-is
/// with no custom logic. It exists only so Hardhat compiles and generates
/// an artifact for it: TimelockController.sol otherwise lives exclusively
/// in node_modules and is never imported by any other AuroPeg contract, so
/// it wouldn't get an artifact of its own.
/// @dev Deployed and wired up by `scripts/deployTimelock.ts`, which grants
/// this contract `DEFAULT_ADMIN_ROLE` on `AuroPeg` and revokes it from the
/// EOA deployer. From that point on, upgrades and role administration go
/// through this timelock's `schedule`/`execute` flow, while `MINTER_ROLE`,
/// `PAUSER_ROLE`, and `UNPAUSER_ROLE` are untouched and stay instant — see
/// the "Design Decisions" section of the README for the full rationale.
contract AuroPegTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
