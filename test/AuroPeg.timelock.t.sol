// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {AuroPegTimelock} from "../contracts/governance/AuroPegTimelock.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.timelock.test.ts ("AuroPeg DEFAULT_ADMIN_ROLE timelock handover").
contract AuroPegTimelockHandoverTest is AuroPegTestBase {
    uint256 internal constant MIN_DELAY = 2 days;

    AuroPegTimelock internal timelock;

    function setUp() public override {
        super.setUp();

        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = admin;

        // no separate optional admin — the timelock self-administers
        timelock = new AuroPegTimelock(MIN_DELAY, proposers, executors, address(0));

        vm.startPrank(admin);
        auroPeg.grantRole(auroPeg.DEFAULT_ADMIN_ROLE(), address(timelock));
        auroPeg.revokeRole(auroPeg.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();
    }

    // --- Handover ---

    function test_RevokesTheDeployersDirectAdminAccess() public view {
        assertFalse(auroPeg.hasRole(auroPeg.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_GrantsDefaultAdminRoleToTheTimelock() public view {
        assertTrue(auroPeg.hasRole(auroPeg.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    function test_RevertWhen_DeployerCallsAdminGatedFunctionDirectly() public {
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, defaultAdminRole)
        );
        auroPeg.grantRole(minterRole, other);
    }

    function test_LeavesMinterPauserUnpauserRolesUntouched() public {
        // admin still holds MINTER_ROLE — only DEFAULT_ADMIN_ROLE moved to the timelock.
        vm.prank(admin);
        auroPeg.mint(other, 10 ** 18);
    }

    // --- Timelocked administration ---

    function test_TimelockGrantsRoleAfterDelayElapsesViaScheduleAndExecute() public {
        bytes memory data = abi.encodeCall(auroPeg.grantRole, (auroPeg.MINTER_ROLE(), other));
        address auroPegAddress = address(auroPeg);

        vm.prank(admin);
        timelock.schedule(auroPegAddress, 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(admin);
        timelock.execute(auroPegAddress, 0, data, bytes32(0), bytes32(0));

        assertTrue(auroPeg.hasRole(auroPeg.MINTER_ROLE(), other));
        assertEq(address(timelock), address(timelock));
    }

    function test_RevertWhen_ExecuteAttemptedBeforeDelayElapses() public {
        bytes memory data = abi.encodeCall(auroPeg.grantRole, (auroPeg.MINTER_ROLE(), other));
        address auroPegAddress = address(auroPeg);
        bytes32 operationId = timelock.hashOperation(auroPegAddress, 0, data, bytes32(0), bytes32(0));
        // OperationState.Ready == 2 → bitmask 1 << 2.
        bytes32 readyStateBitmap = bytes32(uint256(1 << 2));

        vm.prank(admin);
        timelock.schedule(auroPegAddress, 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector, operationId, readyStateBitmap
            )
        );
        timelock.execute(auroPegAddress, 0, data, bytes32(0), bytes32(0));
    }

    function test_RevertWhen_SchedulingBelowConfiguredMinimumDelay() public {
        bytes memory data = abi.encodeCall(auroPeg.grantRole, (auroPeg.MINTER_ROLE(), other));
        address auroPegAddress = address(auroPeg);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, MIN_DELAY - 1, MIN_DELAY)
        );
        timelock.schedule(auroPegAddress, 0, data, bytes32(0), bytes32(0), MIN_DELAY - 1);
    }

    function test_RevertWhen_NonProposerAttemptsToSchedule() public {
        bytes memory data = abi.encodeCall(auroPeg.grantRole, (auroPeg.MINTER_ROLE(), other));
        address auroPegAddress = address(auroPeg);
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, proposerRole)
        );
        timelock.schedule(auroPegAddress, 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_RevertWhen_NonExecutorAttemptsToExecuteReadyOperation() public {
        bytes memory data = abi.encodeCall(auroPeg.grantRole, (auroPeg.MINTER_ROLE(), other));
        address auroPegAddress = address(auroPeg);
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        vm.prank(admin);
        timelock.schedule(auroPegAddress, 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, executorRole)
        );
        timelock.execute(auroPegAddress, 0, data, bytes32(0), bytes32(0));
    }
}
