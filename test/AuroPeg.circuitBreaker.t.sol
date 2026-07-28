// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.circuitBreaker.test.ts ("AuroPeg mint circuit breaker").
contract AuroPegCircuitBreakerTest is AuroPegTestBase {
    // --- Decimal conversion ---

    function test_ConvertsOracles8DecimalReserveTo18DecimalTokenUnits() public view {
        assertEq(auroPeg.currentReserves(), RESERVE_IN_TOKEN_UNITS);
    }

    function test_ReflectsAReserveUpdateFromTheOracleImmediately() public {
        uint256 newReserveGrams = 500_000 * 10 ** 8;

        vm.prank(admin);
        goldReserveOracle.setReserve(newReserveGrams);

        assertEq(auroPeg.currentReserves(), newReserveGrams * 10 ** 10);
    }

    // --- Reserve boundary ---

    function test_RevertWhen_OneUnitOverTheReserve() public {
        uint256 amount = RESERVE_IN_TOKEN_UNITS + 1;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AuroPeg.InsufficientReserves.selector, amount, RESERVE_IN_TOKEN_UNITS));
        auroPeg.mint(other, amount);
    }

    function test_RevertWhen_OutstandingSupplyPlusNewMintExceedsReserve() public {
        vm.prank(admin);
        auroPeg.mint(other, RESERVE_IN_TOKEN_UNITS);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuroPeg.InsufficientReserves.selector, RESERVE_IN_TOKEN_UNITS + 1, RESERVE_IN_TOKEN_UNITS
            )
        );
        auroPeg.mint(monitor, 1);
    }

    // --- Reserve drop ---

    function test_BlocksFurtherMintingOnceAReserveDropPushesSupplyAboveCapacity() public {
        uint256 seventyPercent = (RESERVE_IN_TOKEN_UNITS * 70) / 100;

        vm.prank(admin);
        auroPeg.mint(other, seventyPercent);

        // Drop the reserve by 50% (the mock's per-call cap) — outstanding
        // 70%-of-original supply now exceeds the new 50%-of-original reserve.
        vm.prank(admin);
        goldReserveOracle.simulateReserveDrop(5_000);
        uint256 available = auroPeg.currentReserves();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AuroPeg.InsufficientReserves.selector, seventyPercent + 1, available));
        auroPeg.mint(other, 1);
    }

    // --- Stale or invalid reserve data ---

    function test_RevertWhen_OracleReportsAZeroReserve() public {
        vm.prank(admin);
        goldReserveOracle.setReserve(0);

        vm.prank(admin);
        vm.expectRevert(AuroPeg.StaleReserveData.selector);
        auroPeg.mint(other, 1);
    }

    function test_RevertWhen_LastUpdateExceedsMaxReserveStaleness() public {
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(admin);
        vm.expectRevert(AuroPeg.StaleReserveData.selector);
        auroPeg.mint(other, 1);
    }

    function test_DoesNotRevertForDataUpdatedJustUnderTheStalenessThreshold() public {
        vm.warp(block.timestamp + 1 days - 60);

        vm.prank(admin);
        auroPeg.mint(other, 1);
    }
}
