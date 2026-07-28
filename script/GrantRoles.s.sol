// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";

/// @notice Port of scripts/grantRoles.ts — delegates MINTER_ROLE and/or
/// PAUSER_ROLE from the deployer to operational addresses post-deploy.
/// UNPAUSER_ROLE is deliberately never touched here — it must stay
/// human/multisig-only.
contract GrantRoles is Script {
    function run() external {
        address auroPegAddress = vm.envAddress("AUROPEG_ADDRESS");
        address minterAddress = vm.envOr("MINTER_ADDRESS", address(0));
        address monitorPauserAddress = vm.envOr("MONITOR_PAUSER_ADDRESS", address(0));

        if (minterAddress == address(0) && monitorPauserAddress == address(0)) {
            console2.log("Neither MINTER_ADDRESS nor MONITOR_PAUSER_ADDRESS set - nothing to do.");
            return;
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        AuroPeg auroPeg = AuroPeg(auroPegAddress);
        bytes32 minterRole = auroPeg.MINTER_ROLE();
        bytes32 pauserRole = auroPeg.PAUSER_ROLE();

        vm.startBroadcast(deployerPrivateKey);

        if (minterAddress != address(0)) {
            auroPeg.grantRole(minterRole, minterAddress);
            console2.log("Granted MINTER_ROLE to", minterAddress);
        }
        if (monitorPauserAddress != address(0)) {
            auroPeg.grantRole(pauserRole, monitorPauserAddress);
            console2.log("Granted PAUSER_ROLE to", monitorPauserAddress);
        }

        vm.stopBroadcast();
    }
}
