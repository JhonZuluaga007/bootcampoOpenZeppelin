// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice Port of scripts/upgrade.ts — upgrades the AuroPeg UUPS proxy to a
/// new implementation contract.
///
/// NEW_IMPLEMENTATION_NAME is required (unlike the original Hardhat script,
/// which defaulted it to "AuroPeg" itself as a "no-op smoke test"): the
/// OpenZeppelin Foundry Upgrades plugin explicitly rejects a contract using
/// itself as its own storage-layout reference ("must not use itself as a
/// reference for storage layout comparisons"), so that no-op path was never
/// a safely-validatable operation to begin with. Point this at a real new
/// implementation contract that carries a `@custom:oz-upgrades-from
/// <PreviousContract>` annotation (see contracts/mocks/AuroPegV2Mock.sol for
/// the pattern).
///
/// If DEFAULT_ADMIN_ROLE has moved to the timelock (via DeployTimelock.s.sol),
/// this direct call reverts — a real upgrade must instead be encoded as a
/// timelocked upgradeToAndCall operation via the timelock's schedule()/execute().
contract Upgrade is Script {
    function run() external {
        address auroPegAddress = vm.envAddress("AUROPEG_ADDRESS");
        string memory newImplementationName = vm.envString("NEW_IMPLEMENTATION_NAME");
        string memory contractFile = string.concat(newImplementationName, ".sol");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        Upgrades.upgradeProxy(auroPegAddress, contractFile, "");
        vm.stopBroadcast();

        address newImplementationAddress = Upgrades.getImplementationAddress(auroPegAddress);
        console2.log("NEW_IMPLEMENTATION_ADDRESS=", newImplementationAddress);
        console2.log(
            "Verify with: forge verify-contract",
            newImplementationAddress,
            string.concat("contracts/", contractFile, ":", newImplementationName),
            "--chain sepolia"
        );
    }
}
