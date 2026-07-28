// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.minting.test.ts ("AuroPeg minting").
contract AuroPegMintingTest is AuroPegTestBase {
    // --- Happy path ---

    function test_MintsToTheRecipientAndIncreasesTotalSupply() public {
        uint256 amount = 100 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), other, amount);

        vm.prank(admin);
        auroPeg.mint(other, amount);

        assertEq(auroPeg.balanceOf(other), amount);
        assertEq(auroPeg.totalSupply(), amount);
    }

    function test_AllowsMintingExactlyUpToTheAvailableReserve() public {
        vm.prank(admin);
        auroPeg.mint(other, RESERVE_IN_TOKEN_UNITS);

        assertEq(auroPeg.totalSupply(), RESERVE_IN_TOKEN_UNITS);
    }

    function test_AccumulatesTotalSupplyAcrossMultipleMints() public {
        uint256 amount = 100 * 10 ** 18;

        vm.startPrank(admin);
        auroPeg.mint(other, amount);
        auroPeg.mint(monitor, amount);
        vm.stopPrank();

        assertEq(auroPeg.totalSupply(), amount * 2);
    }

    // --- Access control ---

    function test_RevertWhen_CalledByAnAccountWithoutMinterRole() public {
        bytes32 minterRole = auroPeg.MINTER_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, minterRole)
        );
        auroPeg.mint(other, 1);
    }

    // --- Input validation ---

    function test_RevertWhen_MintingToTheZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(AuroPeg.ZeroAddress.selector);
        auroPeg.mint(address(0), 1);
    }

    function test_RevertWhen_MintingAZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(AuroPeg.ZeroAmount.selector);
        auroPeg.mint(other, 0);
    }

    // --- getGoldPriceUSD (informational) ---

    function test_PassesThroughTheConfiguredPriceFeedsLatestRound() public view {
        (, int256 expectedAnswer,, uint256 expectedUpdatedAt,) = xauUsdPriceFeed.latestRoundData();
        (int256 price, uint256 updatedAt,) = auroPeg.getGoldPriceUSD();

        assertEq(price, expectedAnswer);
        assertEq(updatedAt, expectedUpdatedAt);
    }

    function test_DoesNotAffectMintEligibility() public {
        // Crash the informational price feed's reserve-shaped reading; mint
        // must remain unaffected since it never reads xauUsdPriceFeed.
        vm.prank(admin);
        xauUsdPriceFeed.setReserve(0);

        uint256 amount = 100 * 10 ** 18;
        vm.prank(admin);
        auroPeg.mint(other, amount);
    }
}
