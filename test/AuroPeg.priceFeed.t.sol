// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.priceFeed.test.ts ("AuroPeg XAU/USD price feed (mock)").
contract AuroPegPriceFeedTest is AuroPegTestBase {
    function test_StoresTheConfiguredPriceFeedAddress() public view {
        assertEq(address(auroPeg.xauUsdPriceFeed()), address(xauUsdPriceFeed));
    }

    function test_ReturnsTheFeedsLatestPriceAndTimestamp() public view {
        (, int256 expectedAnswer,, uint256 expectedUpdatedAt,) = xauUsdPriceFeed.latestRoundData();
        (int256 price, uint256 updatedAt,) = auroPeg.getGoldPriceUSD();

        assertEq(price, expectedAnswer);
        assertEq(updatedAt, expectedUpdatedAt);
    }

    function test_ReportsIsStaleFalseRightAfterAFreshUpdate() public view {
        (,, bool isStale) = auroPeg.getGoldPriceUSD();
        assertFalse(isStale);
    }

    function test_ReportsIsStaleTrueOnceOlderThanMaxPriceStalenessWithoutReverting() public {
        uint256 maxPriceStaleness = auroPeg.MAX_PRICE_STALENESS();
        assertEq(maxPriceStaleness, 1 hours);

        vm.warp(block.timestamp + maxPriceStaleness + 1);

        (,, bool isStale) = auroPeg.getGoldPriceUSD();
        assertTrue(isStale);
    }

    function test_ReflectsAPriceUpdateOnTheNextCall() public {
        int256 newPrice = 2_650_00000000; // arbitrary spot-price-shaped value

        vm.prank(admin);
        xauUsdPriceFeed.setReserve(uint256(newPrice));

        (int256 price,,) = auroPeg.getGoldPriceUSD();
        assertEq(price, newPrice);
    }

    function test_IsCallableByAnyoneNoRoleRequired() public {
        vm.prank(other);
        (int256 price,,) = auroPeg.getGoldPriceUSD();
        assertNotEq(price, int256(0));
    }

    function test_RemainsReadableWhileTheContractIsPaused() public {
        vm.prank(admin);
        auroPeg.pause();

        (int256 price,,) = auroPeg.getGoldPriceUSD();
        assertNotEq(price, int256(0));
    }

    // Crash the price feed entirely — mint eligibility depends only on
    // goldReserveOracle, never on xauUsdPriceFeed.
    function test_IsNeverConsultedByTheMintCircuitBreaker() public {
        vm.prank(admin);
        xauUsdPriceFeed.setReserve(0);

        vm.prank(admin);
        auroPeg.mint(other, 1);

        assertEq(auroPeg.balanceOf(other), 1);
    }
}
