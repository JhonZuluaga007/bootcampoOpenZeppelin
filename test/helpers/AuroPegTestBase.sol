// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AuroPeg} from "../../contracts/AuroPeg.sol";
import {MockGoldReserveOracle} from "../../contracts/mocks/MockGoldReserveOracle.sol";

/// @notice Shared setup for the AuroPeg test suite, port of
/// test/helpers/fixtures.ts's `deployAuroPegFixture` + test/helpers/constants.ts.
abstract contract AuroPegTestBase is Test {
    string internal constant TOKEN_NAME = "AuroPeg";
    string internal constant TOKEN_SYMBOL = "AUP";

    // 1,000,000 grams of gold, at the oracle's 8-decimal precision.
    uint256 internal constant INITIAL_RESERVE_GRAMS = 1_000_000 * 10 ** 8;

    // Same reserve, converted to 18-decimal token units (1e18 == 1 gram).
    uint256 internal constant RESERVE_IN_TOKEN_UNITS = INITIAL_RESERVE_GRAMS * 10 ** 10;

    AuroPeg internal auroPeg;
    MockGoldReserveOracle internal goldReserveOracle;
    MockGoldReserveOracle internal xauUsdPriceFeed;

    address internal admin;
    address internal other;
    address internal monitor;

    function setUp() public virtual {
        admin = makeAddr("admin");
        other = makeAddr("other");
        monitor = makeAddr("monitor");

        goldReserveOracle = new MockGoldReserveOracle(INITIAL_RESERVE_GRAMS, admin);
        xauUsdPriceFeed = new MockGoldReserveOracle(INITIAL_RESERVE_GRAMS, admin);

        address proxy = Upgrades.deployUUPSProxy(
            "AuroPeg.sol",
            abi.encodeCall(
                AuroPeg.initialize,
                (TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(xauUsdPriceFeed))
            )
        );
        auroPeg = AuroPeg(proxy);
    }
}
