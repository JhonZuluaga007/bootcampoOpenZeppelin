// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTimelock} from "../contracts/governance/AuroPegTimelock.sol";

/// @notice Port of scripts/deployTimelock.ts — mitigates audit finding I-01
/// by moving DEFAULT_ADMIN_ROLE on AuroPeg from the EOA deployer to a new
/// TimelockController. MINTER_ROLE/PAUSER_ROLE/UNPAUSER_ROLE are untouched.
contract DeployTimelock is Script {
    uint256 internal constant DEFAULT_MIN_DELAY_SECONDS = 2 days;

    function run() external {
        address auroPegAddress = vm.envAddress("AUROPEG_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 minDelay = vm.envOr("TIMELOCK_MIN_DELAY_SECONDS", DEFAULT_MIN_DELAY_SECONDS);
        address proposerAddress = vm.envOr("TIMELOCK_PROPOSER_ADDRESS", deployer);
        address executorAddress = vm.envOr("TIMELOCK_EXECUTOR_ADDRESS", deployer);

        address[] memory proposers = new address[](1);
        proposers[0] = proposerAddress;
        address[] memory executors = new address[](1);
        executors[0] = executorAddress;

        AuroPeg auroPeg = AuroPeg(auroPegAddress);
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();

        vm.startBroadcast(deployerPrivateKey);

        // No separate optional admin — the timelock self-administers.
        AuroPegTimelock timelock = new AuroPegTimelock(minDelay, proposers, executors, address(0));

        auroPeg.grantRole(defaultAdminRole, address(timelock));
        auroPeg.revokeRole(defaultAdminRole, deployer);

        vm.stopBroadcast();

        console2.log("TIMELOCK_ADDRESS=", address(timelock));
    }
}
