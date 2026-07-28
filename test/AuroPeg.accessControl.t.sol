// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.accessControl.test.ts ("AuroPeg access control sweep").
contract AuroPegAccessControlTest is AuroPegTestBase {
    // --- Role admin configuration ---

    function test_UsesDefaultAdminRoleAsTheAdminForEveryCustomRole() public view {
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();

        assertEq(auroPeg.getRoleAdmin(auroPeg.MINTER_ROLE()), defaultAdminRole);
        assertEq(auroPeg.getRoleAdmin(auroPeg.PAUSER_ROLE()), defaultAdminRole);
        assertEq(auroPeg.getRoleAdmin(auroPeg.UNPAUSER_ROLE()), defaultAdminRole);
    }

    // --- Restricted functions revert for unauthorized callers ---
    //
    // Every role constant is read into a local variable BEFORE vm.prank is
    // armed: vm.prank only covers the single next external call, and an
    // inline `auroPeg.SOME_ROLE()` read nested inside the guarded call's
    // (or vm.expectRevert's) own arguments would itself be that "next
    // call," silently consuming the prank before the real guarded call runs.

    function test_RevertWhen_MintCalledWithoutMinterRole() public {
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, minterRole)
        );
        auroPeg.mint(other, 1);
    }

    function test_RevertWhen_PauseCalledWithoutPauserRole() public {
        bytes32 pauserRole = auroPeg.PAUSER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, pauserRole)
        );
        auroPeg.pause();
    }

    function test_RevertWhen_UnpauseCalledWithoutUnpauserRole() public {
        bytes32 unpauserRole = auroPeg.UNPAUSER_ROLE();

        vm.prank(admin);
        auroPeg.pause();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, unpauserRole)
        );
        auroPeg.unpause();
    }

    function test_RevertWhen_UpgradeToAndCallCalledWithoutDefaultAdminRole() public {
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();
        AuroPeg newImplementation = new AuroPeg();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        auroPeg.upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_GrantRoleCalledWithoutDefaultAdminRole() public {
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        auroPeg.grantRole(minterRole, monitor);
    }

    function test_RevertWhen_RevokeRoleCalledWithoutDefaultAdminRole() public {
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        auroPeg.revokeRole(minterRole, admin);
    }

    // --- Authorized callers succeed ---

    function test_LetsTheAdminGrantAndRevokeMinterRole() public {
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(admin);
        auroPeg.grantRole(minterRole, monitor);
        assertTrue(auroPeg.hasRole(minterRole, monitor));

        vm.prank(admin);
        auroPeg.revokeRole(minterRole, monitor);
        assertFalse(auroPeg.hasRole(minterRole, monitor));
    }
}
