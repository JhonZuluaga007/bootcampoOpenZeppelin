// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.deployment.test.ts ("AuroPeg deployment & initialization").
contract AuroPegDeploymentTest is AuroPegTestBase {
    // --- Token metadata ---

    function test_SetsNameSymbolAndStandard18Decimals() public {
        assertEq(auroPeg.name(), TOKEN_NAME);
        assertEq(auroPeg.symbol(), TOKEN_SYMBOL);
        assertEq(uint256(auroPeg.decimals()), 18);
        assertEq(auroPeg.totalSupply(), 0);
    }

    // --- Oracle wiring ---

    function test_StoresGoldReserveOracleAndPriceFeedAddresses() public view {
        assertEq(address(auroPeg.goldReserveOracle()), address(goldReserveOracle));
        assertEq(address(auroPeg.xauUsdPriceFeed()), address(xauUsdPriceFeed));
    }

    // --- Initialization events ---

    function test_EmitsGoldReserveOracleSetAndPriceFeedSetDuringInitialize() public {
        vm.recordLogs();
        address freshProxy = Upgrades.deployUUPSProxy(
            "AuroPeg.sol",
            abi.encodeCall(
                AuroPeg.initialize,
                (TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(xauUsdPriceFeed))
            )
        );
        freshProxy; // silence unused-var warning; only the emitted logs matter here

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawGoldReserveOracleSet = false;
        bool sawPriceFeedSet = false;
        bytes32 goldReserveOracleSetTopic = keccak256("GoldReserveOracleSet(address)");
        bytes32 priceFeedSetTopic = keccak256("PriceFeedSet(address)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == goldReserveOracleSetTopic) sawGoldReserveOracleSet = true;
            if (logs[i].topics[0] == priceFeedSetTopic) sawPriceFeedSet = true;
        }

        assertTrue(sawGoldReserveOracleSet, "GoldReserveOracleSet not emitted");
        assertTrue(sawPriceFeedSet, "PriceFeedSet not emitted");
    }

    // --- Role assignment ---

    function test_GrantsDefaultAdminEveryRole() public view {
        assertTrue(auroPeg.hasRole(auroPeg.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(auroPeg.hasRole(auroPeg.MINTER_ROLE(), admin));
        assertTrue(auroPeg.hasRole(auroPeg.PAUSER_ROLE(), admin));
        assertTrue(auroPeg.hasRole(auroPeg.UNPAUSER_ROLE(), admin));
    }

    function test_DoesNotGrantAnyRoleToUnrelatedAccounts() public view {
        assertFalse(auroPeg.hasRole(auroPeg.DEFAULT_ADMIN_ROLE(), other));
        assertFalse(auroPeg.hasRole(auroPeg.MINTER_ROLE(), other));
    }

    // --- Zero-address guards ---

    // vm.expectRevert can't reliably wrap Upgrades.deployUUPSProxy: the
    // plugin performs several non-reverting calls (ffi safety validation,
    // implementation deployment) before the proxy construction that
    // actually reverts, which desynchronizes the cheatcode's "next call"
    // expectation. These negative-path tests deploy the implementation +
    // ERC1967Proxy manually instead — the exact same mechanism the plugin
    // uses internally, just without the extra validation round-trip.
    function test_RevertWhen_DefaultAdminIsZeroAddress() public {
        AuroPeg implementation = new AuroPeg();
        vm.expectRevert(AuroPeg.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                AuroPeg.initialize,
                (TOKEN_NAME, TOKEN_SYMBOL, address(0), address(goldReserveOracle), address(xauUsdPriceFeed))
            )
        );
    }

    function test_RevertWhen_GoldReserveOracleIsZeroAddress() public {
        AuroPeg implementation = new AuroPeg();
        vm.expectRevert(AuroPeg.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(AuroPeg.initialize, (TOKEN_NAME, TOKEN_SYMBOL, admin, address(0), address(xauUsdPriceFeed)))
        );
    }

    function test_RevertWhen_PriceFeedIsZeroAddress() public {
        AuroPeg implementation = new AuroPeg();
        vm.expectRevert(AuroPeg.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                AuroPeg.initialize, (TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(0))
            )
        );
    }

    // --- Re-initialization protection ---

    function test_RevertWhen_InitializeCalledASecondTimeOnTheProxy() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        auroPeg.initialize(TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(xauUsdPriceFeed));
    }

    function test_RevertWhen_InitializeCalledDirectlyOnTheImplementation() public {
        address implementationAddress = Upgrades.getImplementationAddress(address(auroPeg));
        AuroPeg implementation = AuroPeg(implementationAddress);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(xauUsdPriceFeed));
    }

    // --- Oracle sanity check ---

    function test_ReportsExpectedInitialReserveOnItsConfiguredOracle() public view {
        (, int256 answer,,,) = goldReserveOracle.latestRoundData();
        assertEq(uint256(answer), INITIAL_RESERVE_GRAMS);
    }
}
