// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IGoldReserveOracle} from "./interfaces/IGoldReserveOracle.sol";

/// @title AuroPeg
/// @notice A 1:1 gold-backed (grams), UUPS-upgradeable ERC-20 stablecoin
/// with an on-chain Proof-of-Reserve circuit breaker on mint (added in a
/// later phase). 1 AuroPeg (1e18 base units, standard 18-decimal ERC-20
/// precision) always represents exactly 1 gram of custodied gold — there
/// is no additional conversion constant at the token level.
/// @dev `ReentrancyGuardTransient` is inherited directly from the plain
/// (non-upgradeable) OpenZeppelin Contracts package rather than an
/// "Upgradeable" variant: upstream it is documented as stateless, since it
/// only uses EIP-1153 transient storage and never touches regular storage
/// slots, so it carries no storage-layout risk and needs no initializer.
/// No ReentrancyGuardUpgradeable variant is published for OpenZeppelin
/// Contracts (Upgradeable) v5.x — this is the maintainers' current
/// recommended replacement for upgradeable contracts.
contract AuroPeg is
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Restricted to human/multisig admins. Deliberately never
    /// granted to the off-chain monitor's keeper account: the monitor may
    /// receive {PAUSER_ROLE} to pause automatically on a reserve drop, but
    /// unpausing must always be a manual decision.
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Proof-of-Reserve oracle backing the mint circuit breaker.
    /// Reports the custodied gold reserve, in grams, at 8 decimals.
    IGoldReserveOracle public goldReserveOracle;

    /// @notice Informational Chainlink XAU/USD price feed. Never consulted
    /// by the mint circuit breaker — read only via {getGoldPriceUSD}.
    AggregatorV3Interface public xauUsdPriceFeed;

    error ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy. Grants `defaultAdmin` every role
    /// (`DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `PAUSER_ROLE`,
    /// `UNPAUSER_ROLE`) so the deployer can operate the contract
    /// immediately and delegate roles afterward (see `scripts/grantRoles.ts`).
    function initialize(
        string memory name_,
        string memory symbol_,
        address defaultAdmin,
        address goldReserveOracle_,
        address xauUsdPriceFeed_
    ) public initializer {
        if (defaultAdmin == address(0)) revert ZeroAddress();
        if (goldReserveOracle_ == address(0)) revert ZeroAddress();
        if (xauUsdPriceFeed_ == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __Pausable_init();

        goldReserveOracle = IGoldReserveOracle(goldReserveOracle_);
        xauUsdPriceFeed = AggregatorV3Interface(xauUsdPriceFeed_);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
        _grantRole(UNPAUSER_ROLE, defaultAdmin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
