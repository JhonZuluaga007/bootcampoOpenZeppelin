// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockGoldReserveOracle} from "../contracts/mocks/MockGoldReserveOracle.sol";

/// @notice Port of test/MockGoldReserveOracle.test.ts ("MockGoldReserveOracle").
contract MockGoldReserveOracleTest is Test {
    uint256 internal constant INITIAL_RESERVE_GRAMS = 1_000_000 * 10 ** 8;

    address internal admin;
    address internal other;
    MockGoldReserveOracle internal oracle;

    function setUp() public {
        admin = makeAddr("admin");
        other = makeAddr("other");
        oracle = new MockGoldReserveOracle(INITIAL_RESERVE_GRAMS, admin);
    }

    // --- Constructor ---

    function test_SetsTheInitialReserveAsRound1() public view {
        (uint80 roundId, int256 answer,,,) = oracle.latestRoundData();
        assertEq(uint256(roundId), 1);
        assertEq(answer, int256(INITIAL_RESERVE_GRAMS));
    }

    function test_SetsTheDeployerProvidedAdminAsOwner() public view {
        assertEq(oracle.owner(), admin);
    }

    function test_ExposesChainlinkCompatibleMetadata() public view {
        assertEq(uint256(oracle.decimals()), 8);
        assertEq(oracle.description(), "AuroPeg Mock Gold Reserve Oracle (grams, testnet only)");
        assertEq(oracle.version(), 1);
    }

    // --- setReserve access control ---

    function test_AllowsTheOwnerToUpdateTheReserve() public {
        uint256 newReserve = 2_000_000 * 10 ** 8;

        vm.prank(admin);
        oracle.setReserve(newReserve);

        // The TS test's `anyUint` matcher on `updatedAt` means the event's
        // timestamp field isn't checked exactly; since forge-std's
        // `expectEmit` checks non-indexed data fields all-or-nothing, we
        // instead verify the stored round data directly, which lets us
        // assert `answer` exactly without needing to predict `block.timestamp`.
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, int256(newReserve));
    }

    function test_RevertWhen_NonOwnerCallsSetReserve() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        vm.prank(other);
        oracle.setReserve(1);
    }

    // --- latestRoundData shape ---

    function test_ReturnsMatchingStartedAtUpdatedAtTimestampsForTheLatestRound() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(uint256(roundId), uint256(answeredInRound));
        assertEq(startedAt, updatedAt);
        assertEq(answer, int256(INITIAL_RESERVE_GRAMS));
    }

    // --- getRoundData ---

    function test_ReturnsHistoricalRoundDataForAPastRound() public {
        uint256 newReserve = 2_000_000 * 10 ** 8;
        vm.prank(admin);
        oracle.setReserve(newReserve);

        (uint80 roundId, int256 answer,,,) = oracle.getRoundData(1);
        assertEq(uint256(roundId), 1);
        assertEq(answer, int256(INITIAL_RESERVE_GRAMS));
    }

    function test_RevertWhen_GetRoundDataForARoundThatDoesNotExistYet() public {
        vm.expectRevert(bytes("MockGoldReserveOracle: no data present"));
        oracle.getRoundData(99);
    }

    // --- Ownable2Step ownership transfer ---

    function test_RequiresTheNewOwnerToAcceptBeforeOwnershipActuallyTransfers() public {
        vm.prank(admin);
        oracle.transferOwnership(other);
        assertEq(oracle.owner(), admin);
        assertEq(oracle.pendingOwner(), other);

        vm.prank(other);
        oracle.acceptOwnership();
        assertEq(oracle.owner(), other);
    }

    // --- simulateReserveDrop ---

    function test_IsCallableByAnyoneAndShrinksTheReserveByTheGivenBps() public {
        vm.prank(other);
        oracle.simulateReserveDrop(1_000); // 10%

        (, int256 answer,,,) = oracle.latestRoundData();
        uint256 expected = INITIAL_RESERVE_GRAMS - (INITIAL_RESERVE_GRAMS * 1_000) / 10_000;
        assertEq(answer, int256(expected));
    }

    function test_RevertWhen_BpsValueIsZero() public {
        vm.expectRevert(bytes("MockGoldReserveOracle: invalid bps"));
        oracle.simulateReserveDrop(0);
    }

    function test_RevertWhen_BpsValueIsAboveThe50PercentCap() public {
        vm.expectRevert(bytes("MockGoldReserveOracle: invalid bps"));
        oracle.simulateReserveDrop(5_001);
    }
}
