// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MockGoldReserveOracle} from "../contracts/mocks/MockGoldReserveOracle.sol";

/// @notice Port of scripts/deployMockOracle.ts — standalone deploy of a
/// MockGoldReserveOracle, independent of the full stack deploy in Deploy.s.sol.
contract DeployMockOracle is Script {
    uint256 internal constant DEFAULT_INITIAL_RESERVE_GRAMS = 1_000_000 * 10 ** 8;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 initialReserveGrams = vm.envOr("INITIAL_RESERVE_GRAMS", DEFAULT_INITIAL_RESERVE_GRAMS);
        address ownerAddress = vm.envOr("ORACLE_OWNER_ADDRESS", deployer);

        vm.startBroadcast(deployerPrivateKey);
        MockGoldReserveOracle oracle = new MockGoldReserveOracle(initialReserveGrams, ownerAddress);
        vm.stopBroadcast();

        console2.log("MockGoldReserveOracle:", address(oracle));
    }
}
