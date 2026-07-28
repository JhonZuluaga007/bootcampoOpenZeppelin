// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AuroPeg} from "../contracts/AuroPeg.sol";
import {AuroPegTestBase} from "./helpers/AuroPegTestBase.sol";

/// @notice Port of test/AuroPeg.e2e.test.ts ("AuroPeg end-to-end scenario").
contract AuroPegE2ETest is AuroPegTestBase {
    address internal bob;

    function setUp() public override {
        super.setUp();
        bob = makeAddr("bob");
    }

    function test_FullLifecycle_MintingReserveDropPauseUnpauseRecovery() public {
        uint256 ONE_GRAM = 1e18;

        // --- 1. Two users mint against the healthy, initial reserve. ---
        uint256 aliceMint = (RESERVE_IN_TOKEN_UNITS * 50) / 100;
        uint256 bobMint = (RESERVE_IN_TOKEN_UNITS * 40) / 100;
        vm.prank(admin);
        auroPeg.mint(other, aliceMint);
        vm.prank(admin);
        auroPeg.mint(bob, bobMint);
        assertEq(auroPeg.totalSupply(), aliceMint + bobMint);

        // --- 2. Reserves fluctuate upward: the custodian reports more gold,
        // freeing up capacity that didn't exist before. ---
        uint256 doubledReserveGrams = INITIAL_RESERVE_GRAMS * 2;
        vm.prank(admin);
        goldReserveOracle.setReserve(doubledReserveGrams);
        uint256 topUpMint = (RESERVE_IN_TOKEN_UNITS * 60) / 100; // only possible post-increase
        vm.prank(admin);
        auroPeg.mint(other, topUpMint);
        uint256 supplyAfterTopUp = aliceMint + bobMint + topUpMint;
        assertEq(auroPeg.totalSupply(), supplyAfterTopUp);
        assertGt(supplyAfterTopUp, RESERVE_IN_TOKEN_UNITS); // exceeds the original cap

        // --- 3. The reserve drops sharply; the circuit breaker blocks any
        // further mint once outstanding supply exceeds the new, lower cap. ---
        goldReserveOracle.simulateReserveDrop(5_000); // 50% off the doubled reserve, callable by anyone
        uint256 availableAfterDrop = auroPeg.currentReserves();
        assertGt(supplyAfterTopUp, availableAfterDrop);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(AuroPeg.InsufficientReserves.selector, supplyAfterTopUp + 1, availableAfterDrop)
        );
        auroPeg.mint(other, 1);

        // --- 4. The off-chain monitor — holding only PAUSER_ROLE, delegated
        // here the same way scripts/grantRoles.ts would in production — reacts
        // to the drop by pausing minting. ---
        bytes32 pauserRole = auroPeg.PAUSER_ROLE();
        vm.prank(admin);
        auroPeg.grantRole(pauserRole, monitor);
        vm.prank(monitor);
        auroPeg.pause();
        assertTrue(auroPeg.paused());

        // --- 5. That same monitor account can never unpause: it was deliberately
        // never granted UNPAUSER_ROLE, so resuming minting stays a human decision. ---
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, monitor, auroPeg.UNPAUSER_ROLE()
            )
        );
        vm.prank(monitor);
        auroPeg.unpause();

        // Holders can still exit their position while paused — pause only gates mint.
        vm.prank(other);
        auroPeg.burn(ONE_GRAM);

        // --- 6. The admin "fixes" the reserve (the custodian restocks) and
        // manually unpauses — never the monitor. ---
        vm.prank(admin);
        goldReserveOracle.setReserve(doubledReserveGrams);
        vm.prank(admin);
        auroPeg.unpause();
        assertFalse(auroPeg.paused());

        // --- 7. Normal operation resumes. ---
        vm.prank(admin);
        auroPeg.mint(other, ONE_GRAM);
        assertEq(auroPeg.totalSupply(), supplyAfterTopUp - ONE_GRAM + ONE_GRAM);
    }
}
