// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IGoldReserveOracle} from "../interfaces/IGoldReserveOracle.sol";

/// @title MockGoldReserveOracle
/// @notice Testnet-only stand-in for a real Proof-of-Reserve feed. Mirrors
/// Chainlink's `AggregatorV3Interface` ABI exactly so `AuroPeg.sol` can be
/// pointed at a real PoR aggregator later without any interface changes.
/// The reported `answer` is the custodied gold reserve, denominated in
/// grams, at the same 8-decimal precision Chainlink uses for its own
/// feeds (see {decimals}).
contract MockGoldReserveOracle is IGoldReserveOracle, Ownable {
    uint8 private constant DECIMALS = 8;
    string private constant DESCRIPTION = "AuroPeg Mock Gold Reserve Oracle (grams, testnet only)";
    uint256 private constant VERSION = 1;

    /// @dev `percentBps` is capped so {simulateReserveDrop} can never zero
    /// out the reserve in a single call, keeping the demo scenario gradual.
    uint256 private constant MAX_DROP_BPS = 5_000;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    uint80 private latestRoundId;
    mapping(uint80 roundId => int256 answer) private answers;
    mapping(uint80 roundId => uint256 timestamp) private startedAtTimestamps;
    mapping(uint80 roundId => uint256 timestamp) private updatedAtTimestamps;

    event ReserveUpdated(uint80 indexed roundId, int256 reserveGrams, uint256 updatedAt);

    /// @param initialReserveGrams Starting reserve, in grams, at 8 decimals.
    /// @param initialAdmin Address granted exclusive access to {setReserve}.
    constructor(uint256 initialReserveGrams, address initialAdmin) Ownable(initialAdmin) {
        _recordRound(int256(initialReserveGrams));
    }

    /// @notice Sets the custodied gold reserve. Restricted to the contract
    /// owner so the mock's trust model matches a real PoR feed operator.
    function setReserve(uint256 newReserveGrams) external onlyOwner {
        _recordRound(int256(newReserveGrams));
    }

    /// @notice Demo-only helper that shrinks the current reserve by
    /// `percentBps` basis points, callable by anyone. Exists purely so a
    /// Sepolia demo (or a test) can trigger a reserve-drop scenario without
    /// owner keys. A production PoR oracle would never expose this.
    /// @param percentBps Drop size in basis points (1 - 5_000, i.e. up to 50%).
    function simulateReserveDrop(uint256 percentBps) external {
        require(percentBps > 0 && percentBps <= MAX_DROP_BPS, "MockGoldReserveOracle: invalid bps");
        int256 currentReserve = answers[latestRoundId];
        int256 newReserve = currentReserve - (currentReserve * int256(percentBps)) / int256(BPS_DENOMINATOR);
        _recordRound(newReserve);
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external pure override returns (string memory) {
        return DESCRIPTION;
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external pure override returns (uint256) {
        return VERSION;
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        require(_roundId > 0 && _roundId <= latestRoundId, "MockGoldReserveOracle: no data present");
        return (
            _roundId,
            answers[_roundId],
            startedAtTimestamps[_roundId],
            updatedAtTimestamps[_roundId],
            _roundId
        );
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint80 currentRoundId = latestRoundId;
        return (
            currentRoundId,
            answers[currentRoundId],
            startedAtTimestamps[currentRoundId],
            updatedAtTimestamps[currentRoundId],
            currentRoundId
        );
    }

    function _recordRound(int256 newAnswer) private {
        uint80 roundId = latestRoundId + 1;
        latestRoundId = roundId;
        answers[roundId] = newAnswer;
        startedAtTimestamps[roundId] = block.timestamp;
        updatedAtTimestamps[roundId] = block.timestamp;
        emit ReserveUpdated(roundId, newAnswer, block.timestamp);
    }
}
