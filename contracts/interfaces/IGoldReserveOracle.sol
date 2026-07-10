// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Semantic alias over `AggregatorV3Interface` for the Proof-of-Reserve
/// oracle (reserve quantity, in grams of gold) that feeds AuroPeg's mint
/// circuit breaker. Kept as a distinct type from a plain price feed
/// (e.g. the informational XAU/USD feed used by `AuroPeg.getGoldPriceUSD()`)
/// so the two roles can never be confused at the call site, even though both
/// share the exact same ABI by design.
interface IGoldReserveOracle is AggregatorV3Interface {}
