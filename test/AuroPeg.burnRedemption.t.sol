// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.burnRedemption.test.ts ("AuroPeg burn / redemption").
contract AuroPegBurnRedemptionTest is AuroPegTestBase {
    uint256 internal constant MINTED_AMOUNT = 500e18;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        auroPeg.mint(other, MINTED_AMOUNT);
    }

    // --- Happy path ---

    function test_BurnsTheCallersOwnBalanceAndDecreasesTotalSupply() public {
        uint256 burnAmount = 200e18;

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(other, address(0), burnAmount);
        vm.prank(other);
        auroPeg.burn(burnAmount);

        assertEq(auroPeg.balanceOf(other), MINTED_AMOUNT - burnAmount);
        assertEq(auroPeg.totalSupply(), MINTED_AMOUNT - burnAmount);
    }

    function test_EmitsRedemptionRequestedWithTheCorrectGramsOfGoldConversion() public {
        uint256 burnAmount = 250e18; // 250 grams
        uint256 expectedGrams = 250;

        vm.expectEmit(true, true, true, true);
        emit AuroPeg.RedemptionRequested(other, burnAmount, expectedGrams);
        vm.prank(other);
        auroPeg.burn(burnAmount);
    }

    function test_AllowsBurningTheFullBalanceDownToZero() public {
        vm.prank(other);
        auroPeg.burn(MINTED_AMOUNT);

        assertEq(auroPeg.balanceOf(other), 0);
    }

    // --- Input validation ---

    function test_RevertWhen_BurningAZeroAmount() public {
        vm.prank(other);
        vm.expectRevert(AuroPeg.ZeroAmount.selector);
        auroPeg.burn(0);
    }

    function test_RevertWhen_BurningMoreThanTheCallersBalance() public {
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, other, MINTED_AMOUNT, MINTED_AMOUNT + 1e18
            )
        );
        auroPeg.burn(MINTED_AMOUNT + 1e18);
    }

    function test_RevertWhen_BurningAnAmountThatIsNotAWholeGram() public {
        uint256 fractionalAmount = 1e18 + 1; // 1 gram + 1 wei

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AuroPeg.InvalidBurnAmount.selector, fractionalAmount));
        auroPeg.burn(fractionalAmount);
    }

    function test_RevertWhen_BurningAnotherAccountsBalance() public {
        vm.prank(monitor);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, monitor, 0, MINTED_AMOUNT)
        );
        auroPeg.burn(MINTED_AMOUNT);
    }

    // --- Reserve capacity after redemption ---

    function test_FreesUpReserveCapacityForFutureMints() public {
        uint256 available = auroPeg.currentReserves();
        uint256 totalSupply = auroPeg.totalSupply();
        uint256 remainingCapacity = available - totalSupply;

        uint256 oneGram = 1e18;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AuroPeg.InsufficientReserves.selector, available + oneGram, available));
        auroPeg.mint(monitor, remainingCapacity + oneGram);

        vm.prank(other);
        auroPeg.burn(oneGram);

        vm.prank(admin);
        auroPeg.mint(monitor, remainingCapacity + oneGram);
    }
}
