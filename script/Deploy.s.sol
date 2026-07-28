// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {MockGoldReserveOracle} from "../contracts/mocks/MockGoldReserveOracle.sol";

/// @notice Port of scripts/deploy.ts — deploys the full stack: the
/// Proof-of-Reserve oracle (always mocked — no real PoR testnet feed exists
/// for a fictional gold-backed asset, see the README's "Known Limitations"),
/// the XAU/USD price feed (real Chainlink feed on Sepolia, mocked elsewhere),
/// and the AuroPeg UUPS proxy.
contract Deploy is Script {
    // Chainlink XAU/USD proxy feed on Sepolia. Purely informational — read
    // only via AuroPeg.getGoldPriceUSD(), never consulted by the mint
    // circuit breaker. Reconfirm against
    // https://docs.chain.link/data-feeds/price-feeds/addresses before
    // relying on it: testnet feed addresses can change without notice.
    address internal constant SEPOLIA_XAU_USD_FEED = 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    uint256 internal constant DEFAULT_INITIAL_RESERVE_GRAMS = 1_000_000 * 10 ** 8;
    string internal constant DEFAULT_TOKEN_NAME = "AuroPeg";
    string internal constant DEFAULT_TOKEN_SYMBOL = "AUP";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 initialReserveGrams = vm.envOr("INITIAL_RESERVE_GRAMS", DEFAULT_INITIAL_RESERVE_GRAMS);
        string memory tokenName = vm.envOr("TOKEN_NAME", DEFAULT_TOKEN_NAME);
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", DEFAULT_TOKEN_SYMBOL);
        address adminAddress = vm.envOr("ADMIN_ADDRESS", deployer);
        address priceFeedOverride = vm.envOr("PRICE_FEED_ADDRESS", address(0));

        console2.log("Deployer:", deployer);
        console2.log("Default admin:", adminAddress);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("\nDeploying MockGoldReserveOracle (Proof-of-Reserve, mocked)...");
        MockGoldReserveOracle goldReserveOracle = new MockGoldReserveOracle(initialReserveGrams, adminAddress);
        console2.log("  MockGoldReserveOracle:", address(goldReserveOracle));

        address priceFeedAddress = priceFeedOverride;
        if (priceFeedAddress == address(0) && block.chainid == SEPOLIA_CHAIN_ID) {
            priceFeedAddress = SEPOLIA_XAU_USD_FEED;
            console2.log("\nUsing the real Chainlink XAU/USD feed on Sepolia:", priceFeedAddress);
            console2.log(
                "  Reconfirm this address against https://docs.chain.link/data-feeds/price-feeds/addresses before relying on it."
            );
        }
        if (priceFeedAddress == address(0)) {
            console2.log(
                "\nDeploying a MockGoldReserveOracle stand-in for the XAU/USD price feed (no real feed on this network)..."
            );
            MockGoldReserveOracle priceFeedStandIn = new MockGoldReserveOracle(initialReserveGrams, adminAddress);
            priceFeedAddress = address(priceFeedStandIn);
            console2.log("  Price feed stand-in:", priceFeedAddress);
        }

        console2.log("\nDeploying AuroPeg (UUPS proxy)...");
        address auroPegAddress = Upgrades.deployUUPSProxy(
            "AuroPeg.sol",
            abi.encodeCall(
                AuroPeg.initialize, (tokenName, tokenSymbol, adminAddress, address(goldReserveOracle), priceFeedAddress)
            )
        );
        address implementationAddress = Upgrades.getImplementationAddress(auroPegAddress);

        vm.stopBroadcast();

        console2.log("  AuroPeg proxy:", auroPegAddress);
        console2.log("  AuroPeg implementation:", implementationAddress);

        console2.log("\nDeployment summary");
        console2.log("===================");
        console2.log("AUROPEG_ADDRESS=", auroPegAddress);
        console2.log("AUROPEG_IMPLEMENTATION_ADDRESS=", implementationAddress);
        console2.log("GOLD_RESERVE_ORACLE_ADDRESS=", address(goldReserveOracle));
        console2.log("PRICE_FEED_ADDRESS=", priceFeedAddress);

        console2.log("\nNext steps:");
        console2.log("  1. Verify the implementation:");
        console2.log(
            "     forge verify-contract", implementationAddress, "contracts/AuroPeg.sol:AuroPeg --chain sepolia"
        );
        console2.log("  2. Delegate operational roles:");
        console2.log(
            "     MINTER_ADDRESS=... MONITOR_PAUSER_ADDRESS=... AUROPEG_ADDRESS=<proxy> forge script script/GrantRoles.s.sol:GrantRoles --rpc-url sepolia --broadcast"
        );
        console2.log("  3. Hand DEFAULT_ADMIN_ROLE to a timelock:");
        console2.log(
            "     AUROPEG_ADDRESS=<proxy> forge script script/DeployTimelock.s.sol:DeployTimelock --rpc-url sepolia --broadcast"
        );
    }
}
