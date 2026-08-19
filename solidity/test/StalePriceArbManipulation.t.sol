// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISwapRouter02} from "../src/interfaces/external/ISwapRouter02.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";

import {StalePriceArbBase} from "./StalePriceArbBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStatefulCpmmRouter} from "./mocks/MockStatefulCpmmRouter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title Manufactured Py-divergence via the unfloored deposit/redeem legs
/// @notice The attacker *creates* a Py_oracle-vs-Py_dex divergence by trading the yield pool (rather
///         than waiting for staleness), then extracts through deposit/redeem. Two results:
///           - Manufacture_SelfExtractionUnprofitable: the manufacturing cost (convex) outruns the
///             maxTvl-bounded self-extraction — net PnL, marked at the TRUE price so the manipulation
///             slippage counts, is negative at every size and depth. No profitable size exists.
///           - Exit_InKindFloorsDepressedRedeem: a fuzzed floor showing a holder exiting via redeemInKind
///             (oracle-free, DEX-free) is never worse than the plain-redeem victim under a manufactured
///             depression, over the materially-depressed band swept by the manipulation size.
///         The stateful CPMM mock moves on trades, so manipulation carries real, depth-dependent cost.
///         Full treatment: docs/oracle-mispricing-extraction.md §3.
contract StalePriceArbManipulationTest is StalePriceArbBase {
    using SafeCast for uint256;
    // Larger than the sister suite's cap (1e24): the self-extraction size sweep needs the deposit
    // legs to be flow-bounded here, not TVL-capped, so the manufacturing cost is what dominates.
    uint256 internal constant MAX_TVL = 1e27;

    MockStatefulCpmmRouter internal router;

    function setUp() public {
        _etchCommon();
        vm.etch(address(SwapLib.SWAP_ROUTER), address(new MockStatefulCpmmRouter()).code);
        router = MockStatefulCpmmRouter(address(SwapLib.SWAP_ROUTER));
        _deployVault(MAX_TVL); // 1e27
    }

    // ---- helpers -------------------------------------------------------

    function _seedPools(uint256 fusdevDepth) internal {
        // FUSDEV/PYUSD at 1:1 (Py_dex = Py_oracle = 1.0), tunable depth.
        router.setPool(address(FUSDEV), fusdevDepth, address(PYUSD0), fusdevDepth);
        // WETH/PYUSD very deep at 1:2000 so the collateral reconcile leg is ~frictionless.
        router.setPool(address(WETH), 1_000_000e18, address(PYUSD0), 2_000_000_000e18);
    }

    function _swap(address who, address tin, address tout, uint256 amtIn) internal {
        vm.prank(who);
        router.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tin,
                tokenOut: tout,
                fee: 0,
                recipient: who,
                amountIn: amtIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @dev Attacker holdings marked at the TRUE (un-manipulated) price, in PYUSD units:
    ///      WETH = 2000 PYUSD, FUSDEV = 1 PYUSD (peg). Residual tokens are valued at true
    ///      price (conservative: assumes the attacker can exit them with no further impact).
    function _valueP(address who) internal view returns (uint256) {
        return WETH.balanceOf(who) * 2000 + PYUSD0.balanceOf(who) + FUSDEV.balanceOf(who);
    }

    /// @dev Full manufacture-then-extract cycle, returning the attacker's TRUE-value net PnL
    ///      (PYUSD units). The attacker is funded with the FUSDEV it dumps (counted in V0 at
    ///      true value, so the manipulation slippage shows up as a loss) plus the WETH it
    ///      deposits. Manipulation cost + vault extraction + residual are all captured.
    function _attackTrueNetPnl(uint256 depth, uint256 manip) internal returns (int256 pnl) {
        uint256 snap = vm.snapshotState();
        _seedPools(depth);
        _deposit(honest, 10 ether);

        MockERC20(address(FUSDEV)).mint(attacker, manip);
        MockERC20(address(WETH)).mint(attacker, 10 ether);
        uint256 v0 = _valueP(attacker);

        _swap(attacker, address(FUSDEV), address(PYUSD0), manip); // manufacture the depression

        vm.startPrank(attacker);
        WETH.approve(address(vault), 10 ether);
        uint256 sh = vault.deposit(10 ether, attacker);
        vault.redeem(sh, attacker, attacker);
        vm.stopPrank();

        pnl = SafeCast.toInt256(_valueP(attacker)) - SafeCast.toInt256(v0);
        vm.revertToState(snap);
    }

    // ---- tests ---------------------------------------------------------

    /// @notice A SELF-contained manufacture-then-extract round trip does not pay. The attacker
    ///         manufactures a Py_dex depression (dumping FUSDEV, eating the pool impact) and then
    ///         extracts through its OWN deposit+redeem — whose size is bounded by `maxTvl`. The
    ///         net PnL (marked at TRUE price, attacker-favorable) is negative across every
    ///         manipulation size and pool depth, and grows more negative with size: the
    ///         manufacturing round-trip cost outscales the flow-bounded self-extraction. The
    ///         profit peak is below zero, so no profitable size exists.
    ///
    ///         This covers the attacker extracting from THEMSELVES. Extraction from OTHER holders
    ///         (whose redeems the attacker sandwiches at the manipulated price) scales with the
    ///         victim's flow, not the attacker's — that surface is capped by `redeemInKind`, the
    ///         oracle-free / DEX-free exit (testFuzz_Exit_InKindFloorsDepressedRedeem).
    function test_Manufacture_SelfExtractionUnprofitable() public {
        uint256[5] memory manips = [uint256(50_000e18), 200_000e18, 500_000e18, 1_000_000e18, 3_000_000e18];
        int256 shallowPeak = type(int256).min;
        int256 deepPeak = type(int256).min;
        for (uint256 i = 0; i < manips.length; i++) {
            int256 shallow = _attackTrueNetPnl(500_000e18, manips[i]);
            int256 deep = _attackTrueNetPnl(50_000_000e18, manips[i]);
            emit log_named_uint("manip", manips[i] / 1e18);
            emit log_named_int("  shallow net PnL (PYUSD)", shallow);
            emit log_named_int("  deep    net PnL (PYUSD)", deep);
            if (shallow > shallowPeak) shallowPeak = shallow;
            if (deep > deepPeak) deepPeak = deep;
        }
        // No profitable size at either depth: the manufacturing cost beats the self-extraction.
        assertLe(shallowPeak, 0, "self-extraction profitable (shallow pool)");
        assertLe(deepPeak, 0, "self-extraction profitable (deep pool)");
    }

    /// @notice `redeemInKind` is a *floor* on a DEX `redeem` under a manufactured depression. An attacker
    ///         dumps FUSDEV into the stateful pool to depress Py_dex; a bystander honest holder then exits.
    ///         A `redeem` sells the yield slice into the depressed pool and is shortchanged; `redeemInKind`
    ///         hands over the raw slice, worth its true value. Fuzzes the manipulation size (which sweeps
    ///         the depression depth Py_dex from ~0.96 down to ~0.39 at this seeded depth) and asserts the
    ///         in-kind slice valued at true is never below the depressed redeem, over the materially-
    ///         depressed band. Near par the two converge — that equality regime is `Exit_InKindEqualsRedeem`'s
    ///         (see the bound note below).
    function testFuzz_Exit_InKindFloorsDepressedRedeem(uint256 manip) public {
        uint256 depth = 500_000e18;
        // Floor is a *depressed-pool* claim: the lower bound sits inside the genuinely-depressed regime
        // (Py_dex <~ 0.96). Below it the CPMM's deposit-time swap impact (baked into the carry) makes the
        // plain redeem marginally beat the true-valued in-kind slice — that near-par convergence is the
        // frictionless Exit_InKindEqualsRedeem's job, not this floor's.
        manip = bound(manip, 10_000e18, 300_000e18); // sweeps Py_dex ~0.96 -> ~0.39

        // Path A: victim redeems through the manufactured-depressed DEX.
        uint256 snap = vm.snapshotState();
        _seedPools(depth);
        uint256 hA = _deposit(honest, 10 ether);
        MockERC20(address(FUSDEV)).mint(attacker, manip);
        _swap(attacker, address(FUSDEV), address(PYUSD0), manip);
        vm.prank(honest);
        uint256 wethRedeem = vault.redeem(hA, honest, honest);
        uint256 redeemValue = wethRedeem * 2000; // PYUSD units, true price
        vm.revertToState(snap);

        // Path B: same depression, victim takes the raw slice via redeemInKind, valued at TRUE (FUSDEV @ 1).
        _seedPools(depth);
        uint256 hB = _deposit(honest, 10 ether);
        MockERC20(address(FUSDEV)).mint(attacker, manip);
        _swap(attacker, address(FUSDEV), address(PYUSD0), manip);
        MockERC20(address(PYUSD0)).mint(honest, 100_000_000e18); // buffer to repay the debt slice
        vm.startPrank(honest);
        PYUSD0.approve(address(vault), type(uint256).max);
        uint256 pyBefore = PYUSD0.balanceOf(honest);
        (uint256 collOut, uint256 yieldOut) = vault.redeemInKind(hB, honest, honest);
        uint256 debtPaid = pyBefore - PYUSD0.balanceOf(honest);
        vm.stopPrank();
        uint256 inKindValue = collOut * 2000 + yieldOut - debtPaid; // WETH@2000 + FUSDEV@1 - debt

        emit log_named_uint("redeem value (PYUSD, true)", redeemValue);
        emit log_named_uint("redeemInKind value (PYUSD, true)", inKindValue);
        // +4000 PYUSD (= 2 wei WETH × 2000) is rounding slack; across the depressed band it is never
        // engaged — in-kind clears redeem by >=190 PYUSD even at the shallow bound — so this is
        // effectively a strict floor.
        assertGe(inKindValue + 4000, redeemValue, "redeemInKind below the manipulated redeem");
    }
}
