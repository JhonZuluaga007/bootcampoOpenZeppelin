// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IGoldReserveOracle} from "../contracts/interfaces/IGoldReserveOracle.sol";

/// @notice Port of test/AuroPeg.priceFeed.fork.test.ts ("AuroPeg XAU/USD price feed (Sepolia fork, optional)").
/// Skipped unless SEPOLIA_RPC_URL is set — reconfirm this feed address against
/// https://docs.chain.link/data-feeds/price-feeds/addresses before relying on it.
contract AuroPegPriceFeedForkTest is Test {
    address internal constant SEPOLIA_XAU_USD_FEED = 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea;
    uint8 internal constant EXPECTED_DECIMALS = 8;

    function setUp() public {
        string memory rpcUrl = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcUrl);
    }

    function test_ReadsLiveDecimalsAndNonZeroAnswerFromTheRealChainlinkFeed() public view {
        IGoldReserveOracle priceFeed = IGoldReserveOracle(SEPOLIA_XAU_USD_FEED);

        uint8 decimals = priceFeed.decimals();
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();

        assertEq(uint256(decimals), uint256(EXPECTED_DECIMALS));
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
    }
}
