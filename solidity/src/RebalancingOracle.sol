// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @dev Minimal view of the vault's permissionless, best-effort rebalance.
interface IRebalancer {
    function rebalance() external;
}

/// @title RebalancingOracle
/// @notice A Morpho market oracle (#75) whose
///         stored price can only be advanced through `update()`, which also
///         attempts the vault's `rebalance()` in the same call — so the position
///         de-risks in step with price moves. Backed by an underlying source
///         price oracle (a Pyth adapter). Makes liquidation rarer; it is not a
///         liquidation-prevention guarantee.
///
///         Properties:
///         1. `update()` is the sole writer of the stored price, so every price
///            advance is accompanied by a rebalance *attempt* (success is not
///            guaranteed — it is best-effort). A caller cannot advance the
///            price while gas-starving the rebalance: `update()` reverts below
///            `minRebalanceGas`.
///         2. The price advances regardless of the rebalance outcome; a failed
///            rebalance never reverts the write or panics the caller.
///         3. Bounded staleness, anchored to the source publish time: the
///            market never reads a price whose Pyth-signed publish time is
///            older than `freshnessThreshold`, on either the stored or the
///            pass-through path. `update()` refuses source data older than
///            `maxSourceAge` and stamps `lastUpdate` with the publish time —
///            never the caller's block timestamp — so a caller cannot launder
///            aged source data into a fresh mark.
///         4. Permissionless: anyone can call `update()`, with or without a
///            Pyth payload.
contract RebalancingOracle is IOracle, Ownable2Step {
    /// @notice Underlying source price oracle (1e36-scaled, Morpho convention).
    ///         Owns the price *value* — the read path is the clean chain
    ///         `market -> this -> source`.
    IOracle public immutable source;
    /// @notice `T`: max publish-time age of any price served to the market,
    ///         stored or pass-through.
    uint256 public immutable freshnessThreshold;
    /// @notice Pyth contract backing `source`. The price *value* still comes
    ///         from `source`; Pyth is read only for the feed's signed publish
    ///         time (staleness is measured from when the data was true, not
    ///         from when a caller wrote it), plus the push-then-update path.
    IPyth public immutable pyth;
    /// @notice Pyth feed id `source` prices from.
    bytes32 public immutable feedId;
    /// @notice `F`: max publish-time age `update()` accepts (`F <= T`).
    uint256 public immutable maxSourceAge;
    /// @notice Gas floor checked before the rebalance attempt, so a caller
    ///         cannot advance the price while forcing the rebalance to OOG
    ///         inside the try/catch.
    uint256 public immutable minRebalanceGas;

    /// @notice Vault whose `rebalance()` is attempted on every price advance.
    ///         Wired once via `setVault` after the vault (which is built on the
    ///         market that bakes in this oracle) exists — the single trailing
    ///         edge in an otherwise one-directional price graph.
    IRebalancer public vault;

    /// @notice Last price written by `update()` (1e36-scaled).
    uint256 public storedPrice;
    /// @notice Pyth publish time of the data behind the last `update()`;
    ///         0 before the first.
    uint256 public lastUpdate;

    /// @notice Emitted on every `update()`.
    /// @param price      Source price written to storage.
    /// @param rebalanced Whether the best-effort `rebalance()` succeeded.
    event Updated(uint256 price, bool rebalanced);

    /// @dev `setVault` may only be called once.
    error VaultAlreadySet();
    /// @dev `update()` was called with less gas than the rebalance needs.
    error InsufficientGas();

    constructor(
        IOracle source_,
        uint256 freshnessThreshold_,
        IPyth pyth_,
        bytes32 feedId_,
        uint256 maxSourceAge_,
        uint256 minRebalanceGas_,
        address admin_
    ) Ownable(admin_) {
        require(maxSourceAge_ <= freshnessThreshold_, "maxSourceAge > freshnessThreshold");
        source = source_;
        freshnessThreshold = freshnessThreshold_;
        pyth = pyth_;
        feedId = feedId_;
        maxSourceAge = maxSourceAge_;
        minRebalanceGas = minRebalanceGas_;
    }

    /// @notice Wire the vault whose `rebalance()` `update()` fires. Write-once and
    ///         owner-gated: once set it can never be repointed (so the oracle
    ///         only ever rebalances its own vault), and a stranger can't
    ///         front-run the wiring to a bogus vault and break the coupling.
    function setVault(IRebalancer vault_) external onlyOwner {
        if (address(vault) != address(0)) revert VaultAlreadySet();
        vault = vault_;
    }

    /// @inheritdoc IOracle
    /// @dev Returns the stored price while its publish time is within
    ///      `freshnessThreshold`, otherwise the live source price — gated on
    ///      the same publish-time bound, so no path serves the market data
    ///      older than `freshnessThreshold` (reverts `StalePrice` instead:
    ///      fail-closed and loud, never silently mispriced).
    function price() external view returns (uint256) {
        if (lastUpdate != 0 && block.timestamp <= lastUpdate + freshnessThreshold) {
            return storedPrice;
        }
        _freshPublishTime(freshnessThreshold);
        return source.price();
    }

    /// @notice Advance the stored price to the live source price, then attempt a
    ///         best-effort `rebalance()` — which reads the just-written price.
    ///         The price is written whether or not the rebalance succeeds, and a
    ///         failing rebalance never reverts this call. Permissionless.
    function update() external {
        _update();
    }

    /// @notice `update()` preceded by a Pyth push: posts `pythUpdateData`
    ///         (paying the Pyth fee from `msg.value`), then runs the same gated
    ///         path — atomic push -> gate -> mark -> rebalance. Pyth silently
    ///         skips non-newer data, so the gate below is what proves
    ///         freshness, not the push itself.
    function update(bytes[] calldata pythUpdateData) external payable {
        pyth.updatePriceFeeds{value: msg.value}(pythUpdateData);
        _update();
    }

    function _update() internal {
        uint256 publishTime = _freshPublishTime(maxSourceAge);

        uint256 p = source.price();
        storedPrice = p;
        lastUpdate = publishTime;

        // Skip the rebalance in the deploy-only window before `vault` is wired.
        bool rebalanced = false;
        if (address(vault) != address(0)) {
            if (gasleft() < minRebalanceGas) revert InsufficientGas();
            try vault.rebalance() {
                rebalanced = true;
            } catch {}
        }

        emit Updated(p, rebalanced);
    }

    /// @dev The feed's publish time; reverts `StalePrice` unless it is within
    ///      `age` of block time.
    function _freshPublishTime(uint256 age) internal view returns (uint256) {
        // slither-disable-next-line pyth-unchecked-confidence -> the price value is never consumed from Pyth (it comes from `source`); only the signed publish time is read
        PythStructs.Price memory feed = pyth.getPriceNoOlderThan(feedId, age);
        return feed.publishTime;
    }
}
