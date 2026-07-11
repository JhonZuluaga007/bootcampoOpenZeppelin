// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuroPeg} from "../AuroPeg.sol";

/// @title AuroPegV2Mock
/// @notice Minimal UUPS upgrade target used only by
/// `test/AuroPeg.upgrade.test.ts` to prove that upgrading `AuroPeg`
/// preserves storage and keeps role-gating intact. Never deployed to any
/// real network. Inherits `AuroPeg` directly (rather than redeclaring its
/// base contracts) so its storage layout is `AuroPeg`'s layout with one
/// new variable appended — the additive layout shape the OpenZeppelin
/// Upgrades plugin expects when validating an upgrade.
contract AuroPegV2Mock is AuroPeg {
    /// @notice New storage slot appended after V1's layout.
    uint256 public upgradeMarker;

    /// @notice Only callable once upgraded, to prove the implementation
    /// actually changed post-upgrade.
    function setUpgradeMarker(uint256 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeMarker = value;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}
