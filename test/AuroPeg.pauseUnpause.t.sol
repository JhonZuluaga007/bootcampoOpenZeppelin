// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.pauseUnpause.test.ts ("AuroPeg pause / unpause").
contract AuroPegPauseUnpauseTest is AuroPegTestBase {
    // --- Access control ---

    function test_AllowsAccountWithPauserRoleToPause() public {
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(admin);
        vm.prank(admin);
        auroPeg.pause();

        assertTrue(auroPeg.paused());
    }

    function test_AllowsAccountWithUnpauserRoleToUnpause() public {
        vm.prank(admin);
        auroPeg.pause();

        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(admin);
        vm.prank(admin);
        auroPeg.unpause();

        assertFalse(auroPeg.paused());
    }

    function test_RevertWhen_NonPauserAccountCallsPause() public {
        bytes32 pauserRole = auroPeg.PAUSER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, pauserRole)
        );
        auroPeg.pause();
    }

    function test_RevertWhen_NonUnpauserAccountCallsUnpause() public {
        bytes32 unpauserRole = auroPeg.UNPAUSER_ROLE();

        vm.prank(admin);
        auroPeg.pause();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, unpauserRole)
        );
        auroPeg.unpause();
    }

    // Simulate granting the off-chain monitor keeper PAUSER_ROLE only —
    // exactly as scripts/grantRoles.ts will do in Phase 6 — and confirm
    // it can never be granted UNPAUSER_ROLE's privileges by proxy.
    function test_DoesNotAllowAccountWithOnlyPauserRoleToUnpause() public {
        bytes32 pauserRole = auroPeg.PAUSER_ROLE();
        bytes32 unpauserRole = auroPeg.UNPAUSER_ROLE();

        vm.prank(admin);
        auroPeg.grantRole(pauserRole, monitor);

        vm.prank(monitor);
        auroPeg.pause();

        assertFalse(auroPeg.hasRole(unpauserRole, monitor));

        vm.prank(monitor);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, monitor, unpauserRole)
        );
        auroPeg.unpause();
    }

    // --- Double pause/unpause protection ---

    function test_RevertWhen_PausingAnAlreadyPausedContract() public {
        vm.prank(admin);
        auroPeg.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        auroPeg.pause();
    }

    function test_RevertWhen_UnpausingAContractThatIsNotPaused() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        vm.prank(admin);
        auroPeg.unpause();
    }

    // --- Effect on mint, burn, and transfers ---

    function test_RevertWhen_MintWhilePaused() public {
        vm.prank(admin);
        auroPeg.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        auroPeg.mint(other, 1);
    }

    function test_AllowsMintAgainOnceUnpaused() public {
        vm.startPrank(admin);
        auroPeg.pause();
        auroPeg.unpause();
        auroPeg.mint(other, 1);
        vm.stopPrank();
    }

    // Design decision: pause only gates mint — burn/redemption is never
    // blocked, so holders can always exit even mid-incident.
    function test_DoesNotBlockBurnWhilePaused() public {
        uint256 amount = 100 * 10 ** 18;
        vm.prank(admin);
        auroPeg.mint(other, amount);

        vm.prank(admin);
        auroPeg.pause();

        vm.prank(other);
        auroPeg.burn(amount);
    }

    function test_DoesNotBlockRegularTransfersWhilePaused() public {
        uint256 amount = 100 * 10 ** 18;
        vm.prank(admin);
        auroPeg.mint(other, amount);

        vm.prank(admin);
        auroPeg.pause();

        vm.prank(other);
        auroPeg.transfer(monitor, amount);

        assertEq(auroPeg.balanceOf(monitor), amount);
    }
}
