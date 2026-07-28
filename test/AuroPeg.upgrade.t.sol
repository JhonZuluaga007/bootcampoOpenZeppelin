// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AuroPegV2Mock} from "../contracts/mocks/AuroPegV2Mock.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.upgrade.test.ts ("AuroPeg upgrade safety").
contract AuroPegUpgradeTest is AuroPegTestBase {
    function test_PreservesStorageBalancesTotalSupplyRolesAcrossAnUpgrade() public {
        uint256 amount = 250 * 10 ** 18;
        vm.prank(admin);
        auroPeg.mint(other, amount);

        // startPrank (not a single-shot prank) since Upgrades.upgradeProxy
        // performs several internal calls (ffi safety validation, new
        // implementation deployment) before the actual admin-gated
        // upgradeToAndCall call — a single vm.prank would be consumed by
        // one of those earlier steps instead of the one that needs it.
        vm.startPrank(admin);
        Upgrades.upgradeProxy(address(auroPeg), "AuroPegV2Mock.sol", "");
        vm.stopPrank();

        assertEq(auroPeg.balanceOf(other), amount);
        assertEq(auroPeg.totalSupply(), amount);
        assertTrue(auroPeg.hasRole(auroPeg.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(auroPeg.hasRole(auroPeg.MINTER_ROLE(), admin));
    }

    function test_KeepsTheSameProxyAddressAcrossTheUpgrade() public {
        address proxyAddress = address(auroPeg);

        // startPrank (not a single-shot prank) since Upgrades.upgradeProxy
        // performs several internal calls (ffi safety validation, new
        // implementation deployment) before the actual admin-gated
        // upgradeToAndCall call — a single vm.prank would be consumed by
        // one of those earlier steps instead of the one that needs it.
        vm.startPrank(admin);
        Upgrades.upgradeProxy(address(auroPeg), "AuroPegV2Mock.sol", "");
        vm.stopPrank();

        assertEq(address(auroPeg), proxyAddress);
    }

    function test_ExposesTheNewV2FunctionalityAfterUpgrading() public {
        // startPrank (not a single-shot prank) since Upgrades.upgradeProxy
        // performs several internal calls (ffi safety validation, new
        // implementation deployment) before the actual admin-gated
        // upgradeToAndCall call — a single vm.prank would be consumed by
        // one of those earlier steps instead of the one that needs it.
        vm.startPrank(admin);
        Upgrades.upgradeProxy(address(auroPeg), "AuroPegV2Mock.sol", "");
        vm.stopPrank();

        AuroPegV2Mock upgraded = AuroPegV2Mock(address(auroPeg));

        assertEq(upgraded.version(), "v2");

        vm.prank(admin);
        upgraded.setUpgradeMarker(42);

        assertEq(upgraded.upgradeMarker(), 42);
    }

    function test_RevertWhen_ReinitializeAttemptedAfterAnUpgrade() public {
        // startPrank (not a single-shot prank) since Upgrades.upgradeProxy
        // performs several internal calls (ffi safety validation, new
        // implementation deployment) before the actual admin-gated
        // upgradeToAndCall call — a single vm.prank would be consumed by
        // one of those earlier steps instead of the one that needs it.
        vm.startPrank(admin);
        Upgrades.upgradeProxy(address(auroPeg), "AuroPegV2Mock.sol", "");
        vm.stopPrank();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        auroPeg.initialize(TOKEN_NAME, TOKEN_SYMBOL, admin, address(goldReserveOracle), address(xauUsdPriceFeed));
    }

    function test_RevertWhen_NonAdminAttemptsTheUpgradeDirectly() public {
        // Deploy a standalone V2Mock implementation to use as the upgrade
        // target, bypassing the Upgrades plugin (which always signs with the
        // default signer) so we can attempt the call as `other`.
        AuroPegV2Mock rawImpl = new AuroPegV2Mock();
        bytes32 defaultAdminRole = auroPeg.DEFAULT_ADMIN_ROLE();

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        auroPeg.upgradeToAndCall(address(rawImpl), "");
    }
}
