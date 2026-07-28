// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuroPeg} from "../contracts/AuroPeg.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.reserveDrop.test.ts ("AuroPeg reserve-drop scenario").
contract AuroPegReserveDropTest is AuroPegTestBase {
    uint256 internal mintedAmount;

    function setUp() public override {
        super.setUp();
        mintedAmount = (RESERVE_IN_TOKEN_UNITS * 70) / 100;
        vm.prank(admin);
        auroPeg.mint(other, mintedAmount);
    }

    function test_DoesNotAutoPauseTheContractWhenTheOracleReportsAReserveDrop() public {
        goldReserveOracle.simulateReserveDrop(5_000); // 50%

        assertFalse(auroPeg.paused());
    }

    function test_BlocksFurtherMintingOnceOutstandingSupplyExceedsTheDroppedReserve() public {
        goldReserveOracle.simulateReserveDrop(5_000); // 50%
        uint256 available = auroPeg.currentReserves();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AuroPeg.InsufficientReserves.selector, mintedAmount + 1, available));
        auroPeg.mint(other, 1);
    }

    function test_StillAllowsHoldersToBurnRedeemAfterAnUnActionedReserveDrop() public {
        goldReserveOracle.simulateReserveDrop(5_000);

        vm.prank(other);
        auroPeg.burn(mintedAmount);
    }

    // --- Manual incident response ---

    function test_LetsPauserRolePauseMintingAfterObservingADropIndependentOfTheDropItself() public {
        goldReserveOracle.simulateReserveDrop(5_000);
        vm.prank(admin);
        auroPeg.pause();

        assertTrue(auroPeg.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        auroPeg.mint(other, 1);
    }

    function test_ResumesMintingOnceReservesRecoverAndAnUnpauserRoleAccountUnpauses() public {
        goldReserveOracle.simulateReserveDrop(5_000);
        vm.prank(admin);
        auroPeg.pause();

        // Reserves recover — restore to the original level.
        vm.prank(admin);
        goldReserveOracle.setReserve(INITIAL_RESERVE_GRAMS);
        vm.prank(admin);
        auroPeg.unpause();

        vm.prank(admin);
        auroPeg.mint(other, 1);
    }

    function test_DoesNotResumeMintingFromTheReserveDropAloneUnpauseMustBeASeparateManualStep() public {
        goldReserveOracle.simulateReserveDrop(5_000);
        vm.prank(admin);
        auroPeg.pause();

        // Reserves recover, but nobody has unpaused yet.
        vm.prank(admin);
        goldReserveOracle.setReserve(INITIAL_RESERVE_GRAMS);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        auroPeg.mint(other, 1);
    }
}
