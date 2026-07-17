// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {PythErrors} from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";

import {RebalancingOracle, IRebalancer} from "../src/RebalancingOracle.sol";
import {MockOracle} from "./mocks/MockOracle.sol";

/// @dev Vault stub: records rebalance calls, can be made to revert, and reads
///      the oracle's `price()` *during* the rebalance so a test can prove the
///      rebalance sees the just-written price.
contract MockRebalanceVault is IRebalancer {
    RebalancingOracle public oracle;
    bool public reverts;
    uint256 public rebalanceCount;
    uint256 public priceSeenDuringRebalance;

    function setOracle(RebalancingOracle o) external {
        oracle = o;
    }

    function setReverts(bool b) external {
        reverts = b;
    }

    function rebalance() external override {
        require(!reverts, "rebalance failed");
        rebalanceCount++;
        priceSeenDuringRebalance = oracle.price();
    }
}

contract RebalancingOracleTest is Test {
    MockOracle internal source;
    MockPyth internal pyth;
    MockRebalanceVault internal vault;
    RebalancingOracle internal oracle;

    uint256 internal constant T = 120; // freshnessThreshold
    uint256 internal constant F = 60; // maxSourceAge
    uint256 internal constant MIN_REBALANCE_GAS = 400_000;
    uint256 internal constant PYTH_FEE = 1 wei;
    bytes32 internal constant FEED_ID = bytes32(uint256(1));
    uint256 internal constant P0 = 100e36;
    uint256 internal constant P1 = 200e36;

    event Updated(uint256 price, bool rebalanced);

    function setUp() public {
        vm.warp(1_000_000); // non-zero base time so staleness math is meaningful
        source = new MockOracle(P0);
        pyth = new MockPyth(T, PYTH_FEE);
        _pushFeed(100, block.timestamp); // feed fresh-to-the-block
        // Deploy order mirrors production: oracle first (only depends on the
        // source), then the vault, then wire the vault in.
        oracle = _newOracle();
        vault = new MockRebalanceVault();
        vault.setOracle(oracle);
        oracle.setVault(vault);
    }

    function _newOracle() internal returns (RebalancingOracle) {
        return new RebalancingOracle(
            IOracle(address(source)),
            T,
            IPyth(address(pyth)),
            FEED_ID,
            F,
            MIN_REBALANCE_GAS,
            address(this)
        );
    }

    function _feedUpdate(int64 p, uint256 publishTime) internal view returns (bytes[] memory data) {
        data = new bytes[](1);
        data[0] = pyth.createPriceFeedUpdateData(FEED_ID, p, 0, -8, p, 0, uint64(publishTime));
    }

    /// @dev Push a feed update straight to the Pyth mock (the real Pyth skips
    ///      non-newer data, so `publishTime` must move forward to take effect).
    function _pushFeed(int64 p, uint256 publishTime) internal {
        pyth.updatePriceFeeds{value: PYTH_FEE}(_feedUpdate(p, publishTime));
    }

    // ---- price() ----------------------------------------------------------

    /// @notice Before the first `update()` the oracle passes through to the
    ///         live source (never returns the uninitialised stored 0).
    function test_Price_BeforeFirstUpdate_PassesThrough() public {
        assertEq(oracle.storedPrice(), 0, "stored uninitialised");
        assertEq(oracle.price(), P0, "passes through to source");

        source.setPrice(P1);
        assertEq(oracle.price(), P1, "tracks live source before any update");
    }

    /// @notice Within `T` of the stored publish time, `price()` returns the
    ///         stored price and ignores later source moves.
    function test_Price_Fresh_ReturnsStored() public {
        oracle.update(); // stores P0
        source.setPrice(P1); // source moves, but no update()

        assertEq(oracle.price(), P0, "returns stored, not live source");

        vm.warp(oracle.lastUpdate() + T); // at the boundary => still fresh
        assertEq(oracle.price(), P0, "fresh at exactly T");
    }

    /// @notice Past `T`, `price()` falls through to the live source — provided
    ///         the feed's publish time is itself within `T`.
    function test_Price_Stale_PassesThroughWhenFeedFresh() public {
        oracle.update(); // stores P0
        source.setPrice(P1);

        vm.warp(block.timestamp + T + 1);
        _pushFeed(200, block.timestamp); // feed republished, fresh
        assertEq(oracle.price(), P1, "passes through once stored is stale");
    }

    /// @notice Past `T` with the feed also aged past `T`, `price()` reverts:
    ///         no path serves the market data older than `T` (fail-closed).
    function test_Price_Stale_RevertsWhenFeedStale() public {
        oracle.update(); // stores P0, feed publish time = now

        vm.warp(block.timestamp + T + 1); // stored AND feed both past T
        vm.expectRevert(PythErrors.StalePrice.selector);
        oracle.price();
    }

    /// @notice While the stored price is fresh, `price()` never touches the
    ///         source — a reverting (stale) source cannot break market reads.
    function test_Price_Fresh_ShieldsRevertingSource() public {
        oracle.update(); // stores P0
        source.setReverts(true);

        assertEq(oracle.price(), P0, "stored price shields a dead source");

        vm.warp(block.timestamp + T + 1);
        _pushFeed(100, block.timestamp); // feed fresh, adapter still dead
        vm.expectRevert("StalePrice");
        oracle.price(); // pass-through propagates the source revert
    }

    // ---- update() ---------------------------------------------------------

    /// @notice `update()` writes the live source price and fires the rebalance.
    function test_Update_WritesPriceAndRebalances() public {
        source.setPrice(P1);
        oracle.update();

        assertEq(oracle.storedPrice(), P1, "stored = source");
        assertEq(vault.rebalanceCount(), 1, "rebalance attempted");
    }

    /// @notice `lastUpdate` is the feed's signed publish time, not the caller's
    ///         block timestamp — aged data cannot be laundered into a fresh
    ///         mark by calling `update()`.
    function test_Update_StampsPublishTime() public {
        uint256 publishTime = block.timestamp;
        vm.warp(block.timestamp + 30); // data is now 30s old, within F

        oracle.update();

        assertEq(oracle.lastUpdate(), publishTime, "stamped with publish time");
        assertLt(oracle.lastUpdate(), block.timestamp, "not the caller's timestamp");
    }

    /// @notice `update()` refuses source data older than `F`.
    function test_Update_RevertsOnStaleSourceData() public {
        vm.warp(block.timestamp + F + 1); // feed data ages past F

        vm.expectRevert(PythErrors.StalePrice.selector);
        oracle.update();
    }

    /// @notice A publish time slightly ahead of block time (Pyth allows it)
    ///         is within the age bound.
    function test_Update_AcceptsFuturePublishTime() public {
        _pushFeed(100, block.timestamp + 2);
        oracle.update();
        assertEq(oracle.lastUpdate(), block.timestamp + 2, "future publish time accepted");
        assertEq(oracle.price(), P0, "stored price fresh");
    }

    /// @notice The rebalance fired by `update()` reads the *just-written* price,
    ///         not the previous one — the core coupling property.
    function test_Update_RebalanceSeesJustWrittenPrice() public {
        oracle.update(); // stores P0
        assertEq(vault.priceSeenDuringRebalance(), P0, "first update sees P0");

        source.setPrice(P1);
        oracle.update(); // stores P1, then rebalances
        assertEq(vault.priceSeenDuringRebalance(), P1, "rebalance sees the new price");
    }

    /// @notice A failing rebalance is swallowed: the price still advances and
    ///         the call does not revert.
    function test_Update_SwallowsRebalanceFailure() public {
        vault.setReverts(true);
        source.setPrice(P1);

        oracle.update(); // must not revert

        assertEq(oracle.storedPrice(), P1, "price written despite failed rebalance");
        assertEq(vault.rebalanceCount(), 0, "rebalance did not complete");
    }

    /// @notice `update()` reverts below the gas floor instead of advancing the
    ///         price with a gas-starved (guaranteed-OOG) rebalance attempt.
    function test_Update_RevertsBelowGasFloor() public {
        vm.expectRevert(RebalancingOracle.InsufficientGas.selector);
        oracle.update{gas: MIN_REBALANCE_GAS / 2}();

        assertEq(oracle.lastUpdate(), 0, "price not advanced");
    }

    /// @notice `update()` reverts when the source itself reverts — the price
    ///         cannot advance without a live source.
    function test_Update_RevertsWhenSourceReverts() public {
        source.setReverts(true);

        vm.expectRevert("StalePrice");
        oracle.update();

        assertEq(oracle.lastUpdate(), 0, "no state written");
    }

    /// @notice `update()` is permissionless.
    function test_Update_Permissionless() public {
        vm.prank(makeAddr("anyone"));
        oracle.update();
        assertEq(oracle.storedPrice(), P0, "anyone can advance");
    }

    /// @notice Before `vault` is wired, `update()` still advances the price and
    ///         simply skips the rebalance (the deploy-only window).
    function test_Update_SkipsRebalanceBeforeVaultWired() public {
        RebalancingOracle fresh = _newOracle();
        source.setPrice(P1);

        fresh.update(); // must not revert with vault unset

        assertEq(fresh.storedPrice(), P1, "price advances without a vault");
    }

    /// @notice `Updated` reports the written price and whether the rebalance
    ///         succeeded.
    function test_Update_EmitsEvent() public {
        source.setPrice(P1);
        vm.expectEmit(false, false, false, true, address(oracle));
        emit Updated(P1, true);
        oracle.update();

        vault.setReverts(true);
        vm.expectEmit(false, false, false, true, address(oracle));
        emit Updated(P1, false);
        oracle.update();
    }

    // ---- update(bytes[]) --------------------------------------------------

    /// @notice The payable overload posts the Pyth payload (paying the fee),
    ///         then runs the same gated path: push -> gate -> mark -> rebalance.
    function test_UpdateWithPayload_PushesThenUpdates() public {
        vm.warp(block.timestamp + F + 1); // feed stale: bare update() would revert
        source.setPrice(P1);

        oracle.update{value: PYTH_FEE}(_feedUpdate(200, block.timestamp));

        assertEq(oracle.storedPrice(), P1, "mark written from just-pushed data");
        assertEq(oracle.lastUpdate(), block.timestamp, "stamped with pushed publish time");
        assertEq(vault.rebalanceCount(), 1, "rebalance attempted");
    }

    /// @notice Pyth silently skips non-newer payloads, so a push alone proves
    ///         nothing — the publish-time gate still rejects the stale feed.
    function test_UpdateWithPayload_NonNewerPushStillGated() public {
        uint256 stalePublish = block.timestamp; // what the feed already holds
        vm.warp(block.timestamp + F + 1);

        // Not newer than what's stored: Pyth skips it, and the gate catches it.
        bytes[] memory data = _feedUpdate(200, stalePublish);
        vm.expectRevert(PythErrors.StalePrice.selector);
        oracle.update{value: PYTH_FEE}(data);
    }

    // ---- wiring -----------------------------------------------------------

    /// @notice `setVault` is owner-only and write-once.
    function test_SetVault_OwnerOnlyAndWriteOnce() public {
        RebalancingOracle fresh = _newOracle();

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        fresh.setVault(vault);

        fresh.setVault(vault); // owner (this contract) sets it once
        assertEq(address(fresh.vault()), address(vault), "wired");

        vm.expectRevert(RebalancingOracle.VaultAlreadySet.selector);
        fresh.setVault(IRebalancer(makeAddr("other")));
    }

    /// @notice The constructor rejects `maxSourceAge > freshnessThreshold`.
    function test_Constructor_RejectsMaxSourceAgeAboveThreshold() public {
        vm.expectRevert("maxSourceAge > freshnessThreshold");
        new RebalancingOracle(
            IOracle(address(source)),
            T,
            IPyth(address(pyth)),
            FEED_ID,
            T + 1,
            MIN_REBALANCE_GAS,
            address(this)
        );
    }
}
