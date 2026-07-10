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
/// with an on-chain Proof-of-Reserve circuit breaker on mint. 1 AuroPeg
/// (1e18 base units, standard 18-decimal ERC-20 precision) always
/// represents exactly 1 gram of custodied gold — there is no additional
/// conversion constant at the token level.
/// @dev `ReentrancyGuardTransient` is inherited directly from the plain
/// (non-upgradeable) OpenZeppelin Contracts package rather than an
/// "Upgradeable" variant: upstream it is documented as stateless, since it
/// only uses EIP-1153 transient storage and never touches regular storage
/// slots, so it carries no storage-layout risk and needs no initializer.
/// No ReentrancyGuardUpgradeable variant is published for OpenZeppelin
/// Contracts (Upgradeable) v5.x — this is the maintainers' current
/// recommended replacement for upgradeable contracts.
/// @dev Design decision: {pause} only gates {mint} — it is the circuit
/// breaker's "stop new issuance" lever, not a full token freeze. Transfers
/// and {burn}/redemption are never blocked by pause, so holders can always
/// exit even while an incident is being investigated.
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

    /// @notice Maximum age, in seconds, a {goldReserveOracle} round may
    /// have before {mint} refuses to trust it. Proof-of-Reserve data
    /// updates far less often than a price feed (it tracks custodian
    /// attestations, not market prices), so this is deliberately looser
    /// than a typical Chainlink price-feed heartbeat.
    uint256 public constant MAX_RESERVE_STALENESS = 1 days;

    error ZeroAddress();
    error ZeroAmount();

    /// @notice Thrown by {mint} when minting `requested` total supply
    /// would exceed the `available` reserve, both in 18-decimal token
    /// units.
    error InsufficientReserves(uint256 requested, uint256 available);

    /// @notice Thrown when {goldReserveOracle}'s latest round is missing,
    /// non-positive, or older than {MAX_RESERVE_STALENESS}.
    error StaleReserveData();

    /// @notice Emitted when a holder burns their own balance to request
    /// off-chain physical redemption of the underlying gold.
    event RedemptionRequested(address indexed holder, uint256 amount, uint256 gramsOfGold);

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

    /// @notice Mints `amount` to `to`, gated by the Proof-of-Reserve
    /// circuit breaker: reverts with {InsufficientReserves} if doing so
    /// would push `totalSupply()` above the reserve reported by
    /// {goldReserveOracle}.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 requestedSupply = totalSupply() + amount;
        uint256 available = currentReserves();
        if (requestedSupply > available) {
            revert InsufficientReserves(requestedSupply, available);
        }

        _mint(to, amount);
    }

    /// @notice Burns `amount` from the caller's own balance to request
    /// off-chain physical redemption. Never gated by {pause} — holders can
    /// always exit their position.
    /// @dev `gramsOfGold` in {RedemptionRequested} is a plain integer gram
    /// count (`amount / 1e18`), relying directly on the 1-token-equals-
    /// 1-gram invariant rather than the oracle's own decimal precision —
    /// any sub-gram remainder is dropped, which matches how a physical
    /// redemption (whole gold units) would be processed off-chain.
    function burn(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, amount);

        uint256 gramsOfGold = amount / 1e18;
        emit RedemptionRequested(msg.sender, amount, gramsOfGold);
    }

    /// @notice The custodied gold reserve reported by {goldReserveOracle},
    /// converted to 18-decimal token units (1e18 == 1 gram).
    /// @dev Reverts with {StaleReserveData} if the latest round is
    /// non-positive or older than {MAX_RESERVE_STALENESS}.
    function currentReserves() public view returns (uint256) {
        (, int256 answer, , uint256 updatedAt,) = goldReserveOracle.latestRoundData();
        if (answer <= 0) revert StaleReserveData();
        if (block.timestamp - updatedAt > MAX_RESERVE_STALENESS) revert StaleReserveData();

        return uint256(answer) * (10 ** (18 - goldReserveOracle.decimals()));
    }

    /// @notice Informational Chainlink XAU/USD spot price. Purely for
    /// display purposes — never consulted by {mint}'s circuit breaker.
    function getGoldPriceUSD() external view returns (int256 price, uint256 updatedAt) {
        (, price, , updatedAt,) = xauUsdPriceFeed.latestRoundData();
    }

    /// @notice Halts {mint} — the circuit breaker's manual or
    /// monitor-triggered "stop new issuance" lever. Does not affect
    /// transfers or {burn}.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes {mint}. Restricted to {UNPAUSER_ROLE}, which is
    /// deliberately never granted to the off-chain monitor's keeper
    /// account — unpausing is always a manual, human decision.
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
