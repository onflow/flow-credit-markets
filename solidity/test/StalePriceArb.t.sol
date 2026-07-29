// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {FCMVault, MORPHO} from "../src/FCMVault.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";

import {StalePriceArbBase} from "./StalePriceArbBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorpho} from "./mocks/MockMorpho.sol";
import {MockSwapRouter} from "./mocks/MockSwapRouter.sol";
import {MockOracle} from "./mocks/MockOracle.sol";

/// @title Stale-price arbitrage extraction bounds
/// @notice Measures the value an attacker extracts by sequencing deposit / redeem while the
///         vault's share price is marked off a stale oracle or a diverged yield mark — i.e.
///         stale-price arbitrage (the DeFi form of mutual-fund market-timing), whose harm is
///         dilution of existing holders. Each test isolates the effect via a counterfactual
///         (act on the mispriced mark vs. the fresh mark).
///
///         Coverage — a decision tree over the booked-vs-fresh gap Δ (not a flat list). The SIZE bound is
///         source-agnostic (§2), so it's tested once; the REPETITION bound is NOT source-agnostic — it
///         saturates for source-specific reasons (Pc: carry is Pc-independent; Py: redeem reads no oracle,
///         A1) — so it's tested per source. Manufacture / real-pool games live in StalePriceArbManipulation.
///           A. Anything to extract?   Core_BalancedNoExtraction          Δ=0 / k=1 ⇒ ~0 (baseline)
///           B. Bounded, per SOURCE?   Core_LossWithinStalenessGap (fuzz)     Pc stale-high (Δ>0): loss ≤ δ, never principal, zero-sum
///                                     Core_OverMarkUnprofitable (fuzz)       Pc stale-low (Δ<0): deposit overpays, edge ≤ 0 (over-mark is source-agnostic)
///                                     Source_YieldDivergenceWithinGap (fuzz) Py mark-vs-DEX gap: harm ≤ gap (both dirs)
///                                     Source_DifferentlyLeveredDiscountReachesPrincipal  differently-levered + discount: harm ≤ gap BUT reaches principal (needs both; R24)
///                                     Source_CombinedWithinComposedGap (fuzz) Pc + Py at once: bounds compose, no blow-up
///           C. Amplifiable, per AXIS? Core_ProfitConcaveInSize           size: interior max, then net-negative (concave)
///                                     Repetition_CollateralOscillationDoesNotCompound time: Pc jitter saturates (carry Pc-independent)
///                                     Repetition_YieldOscillationDoesNotCompound      time: Py mark jitter saturates (redeem oracle-free, A1)
///                                     Repetition_YieldRegenTaxNotPrincipal            time: real up-trend, δ-tax on yield, never principal
///                                     Core_PastCapExitReverts            past the leverage cap: no exit completes
///                                     Core_RebalanceDoesNotAmplify       interposed rebalance(): amplification = 0 (source-agnostic)
///           D. Manufacturable?        (StalePriceArbManipulation.t.sol) Manufacture_SelfExtractionUnprofitable       net < 0
///                                     (StalePriceArbManipulation.t.sol) Exit_InKindFloorsDepressedRedeem (fuzz)      bystander escapes in-kind ≥ redeem
///           E. Exit / controls sound? Exit_RedeemMarkIndependent         redeem payout independent of the mark (both dirs) → A1, sell side dead
///                                     Exit_InKindEqualsRedeem            in-kind == redeem (same rate) → A1
///                                     Control_DexFeeOnlyPartiallyOffsets fee ≠ the defense (keeper is)
///         Full write-up: docs/oracle-mispricing-extraction.md.
///
///         Scope / mock limits:
///           - Swaps are fee-less and zero-price-impact (MockSwapRouter). The
///             deposit/redeem swap legs are unfloored (SwapLib.swapExactIn,
///             amountOutMinimum=0), so AMM slippage on those legs is not modeled.
///           - The market oracle is a settable value (MockOracle); the staleness gap
///             δ is a test parameter, not a real Pyth staleness/confidence check.
///           - The stale-price (oracle-timing) fuzz is bounded to δ ≤ ~27% — the range where the
///             corrected position keeps HF ≥ 1 so the redeem exit executes. The suite
///             enforces Morpho's HF ≥ 1 withdraw gate (setUp), so this is verified across
///             the fuzz, not assumed.
///           - The rebalance oracle-anchored slippage limit (SwapLib.swapExactInToLimit) has mechanism-level
///             coverage in FCMVault.t.sol (test_Rebalance_PartialDeleverMakesProgress,
///             _PartialLeverMakesProgress, _RespectsLoosenedSlippage,
///             test_PriceLimit_OracleMathMatchesOracleAndSlippage); no per-share NAV bound
///             on a forced rebalance is asserted there or here.
contract StalePriceArbTest is StalePriceArbBase {
    // Largest oracle staleness (δ) the timing fuzz applies: a 27.5% gap between the stale mark and
    // the true price. Not arbitrary — the deposit levers to ~1.45x health factor, so a pro-rata
    // (Case-A) redeem reverts on real Morpho once the drop exhausts that buffer (~31.5%). The 27.5%
    // cap sits conservatively inside the redeemable region; test_Core_PastCapExitReverts
    // verifies the redeem succeeds here and reverts on a deep crash. MIN_TRUE_PRICE is that cap as a
    // price (the fuzz floor); the suite enforces Morpho's HF>=1 gate (setUp), so every fuzzed redeem
    // is verified solvent, not assumed.
    uint256 internal constant MAX_STALENESS_BPS = 2750; // 27.5%
    uint256 internal constant MIN_TRUE_PRICE = WETH_PRICE * (10_000 - MAX_STALENESS_BPS) / 10_000;

    function setUp() public {
        _etchCommon();
        vm.etch(address(SwapLib.SWAP_ROUTER), address(new MockSwapRouter()).code);
        _deployVault(1e24);

        // Enforce Morpho's real HF>=1 withdraw gate for the whole suite, so every redeem measured
        // here is one real Morpho would actually allow: the delta<=27.5% fuzz bound is verified
        // solvent, not assumed. (The lenient default would let an underwater redeem "complete" and
        // report a fictional extraction — so we hold the mock to Morpho's real behavior instead.)
        MockMorpho(address(MORPHO)).setEnforceHf(true);
    }

    // ---- helpers -------------------------------------------------------

    function _redeem(address who, uint256 shares) internal returns (uint256 assetsOut) {
        vm.prank(who);
        assetsOut = vault.redeem(shares, who, who);
    }

    /// @dev Honest holder's booked asset claim — the conservation quantity.
    function _honestClaim() internal view returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(honest));
    }

    /// @dev Set the DEX (priced router) so WETH<->PYUSD trades at `truePriceE36`
    ///      and yield<->PYUSD at `kWad` (Y worth k loan per unit). Returns the router.
    function _pricedDex(uint256 truePriceE36, uint256 kWad) internal returns (MockSwapRouter r) {
        vm.etch(address(SwapLib.SWAP_ROUTER), address(new MockSwapRouter()).code);
        r = MockSwapRouter(address(SwapLib.SWAP_ROUTER));
        r.setRate(address(WETH), address(PYUSD0), truePriceE36 / 1e18);
        r.setRate(address(PYUSD0), address(WETH), uint256(1e18) * 1e18 / (truePriceE36 / 1e18));
        if (kWad != 1e18) {
            r.setRate(address(FUSDEV), address(PYUSD0), kWad);
            r.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kWad);
        }
    }

    /// @dev The stale-price arbitrage cycle against a position with carry unbalance `k = Y·Py/D`
    ///      (1e18 = balanced). Attacker deposits on the stale mark (2000), posts the
    ///      correction to `truePriceE36`, redeems. Returns (attacker timing gain,
    ///      honest timing loss, honest baseline) in wei, isolated via a
    ///      counterfactual snapshot vs. the oracle-already-fresh world.
    function _stalePriceArbCycle(uint256 kWad, uint256 truePriceE36)
        internal
        returns (int256 extraction, int256 honestLoss, uint256 honestBaseline, uint256 honestAfter)
    {
        MockSwapRouter router = _pricedDex(truePriceE36, 1e18); // yield par at entry
        _deposit(honest, 10 ether);

        if (kWad != 1e18) {
            // Yield earns carry: Py and the yield DEX rise to k (internally consistent).
            yieldOracle.setPrice(kWad * 1e18);
            router.setRate(address(FUSDEV), address(PYUSD0), kWad);
            router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kWad);
        }

        // Attacker deposit (1000) >> honest (10): attacker holds ~all supply, which
        // maximizes honest loss as a fraction of the honest holder's claim.
        uint256 inAmt = 1000 ether;
        uint256 snap = vm.snapshotState();

        // World A: exploit the timing — enter stale, post the update, exit.
        uint256 sA = _deposit(attacker, inAmt);
        marketOracle.setPrice(truePriceE36);
        uint256 outA = _redeem(attacker, sA);
        int256 pnlA = int256(outA) - int256(inAmt);
        honestAfter = _honestClaim();
        uint256 honestA = honestAfter;

        // World B: no edge — oracle already fresh before the attacker acts.
        vm.revertToState(snap);
        marketOracle.setPrice(truePriceE36);
        uint256 sB = _deposit(attacker, inAmt);
        uint256 outB = _redeem(attacker, sB);
        int256 pnlB = int256(outB) - int256(inAmt);
        honestBaseline = _honestClaim();

        extraction = pnlA - pnlB;
        honestLoss = int256(honestBaseline) - int256(honestA);
    }

    /// @dev Attacker's ABSOLUTE round-trip PnL (out − in), WETH wei, with a DEX fee.
    ///      Enter on the stale mark, post the update, exit. Positive = the timing edge
    ///      beat the round-trip DEX cost; negative = the fee ate the edge.
    function _attackNetPnl(uint256 kWad, uint256 truePriceE36, uint256 feeBps) internal returns (int256) {
        return _attackNetPnlSized(kWad, truePriceE36, feeBps, 1000 ether);
    }

    function _attackNetPnlSized(uint256 kWad, uint256 truePriceE36, uint256 feeBps, uint256 inAmt)
        internal
        returns (int256)
    {
        MockSwapRouter router = _pricedDex(truePriceE36, 1e18);
        router.setFeeBps(feeBps);
        _deposit(honest, 10 ether);
        if (kWad != 1e18) {
            yieldOracle.setPrice(kWad * 1e18);
            router.setRate(address(FUSDEV), address(PYUSD0), kWad);
            router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kWad);
        }
        uint256 sA = _deposit(attacker, inAmt);
        marketOracle.setPrice(truePriceE36);
        uint256 outA = _redeem(attacker, sA);
        return int256(outA) - int256(inAmt);
    }

    /// @notice Concavity in size: a larger attack cannot be more profitable. The timing edge saturates
    ///         (bounded by the fixed victim carry) while the attacker's own levering fee grows linearly,
    ///         so net PnL rises to an interior maximum (~0.98 WETH at ~100 WETH) then falls negative.
    ///         The unimodality is the closed-form concavity argument (doc §2); these 4 points only
    ///         sample the curve to confirm the sign. The time axis (repetition) is bounded separately
    ///         by the test_Repetition_*OscillationDoesNotCompound tests (collateral + yield).
    function test_Core_ProfitConcaveInSize() public {
        uint256 small = 10 ether;
        uint256 opt = 100 ether;
        uint256 big = 10_000 ether;
        uint256 huge = 500_000 ether;

        int256 nSmall = _sizedPnl(small);
        int256 nOpt = _sizedPnl(opt);
        int256 nBig = _sizedPnl(big);
        int256 nHuge = _sizedPnl(huge);

        emit log_named_int("net @ 10 WETH", nSmall);
        emit log_named_int("net @ 100 WETH", nOpt);
        emit log_named_int("net @ 10k WETH", nBig);
        emit log_named_int("net @ 500k WETH", nHuge);

        // Interior maximum: the mid size beats both a smaller and a larger attack.
        assertGt(nOpt, nSmall, "profit not rising toward the optimum");
        assertGt(nOpt, nBig, "a larger attack was more profitable (not concave)");
        // Scaling far past the optimum is net-negative: unbounded size does not help.
        assertLt(nHuge, 0, "a very large attack still profited");
        // (No absolute WETH cap asserted — the peak is a test-scale artifact; the scale-free ceiling is
        // π < Δ. The property here is the shape: an interior maximum, net-negative once oversized.)
    }

    /// @notice Past the δ cap the crash puts the position underwater and NO exit completes, so a bigger move
    ///         yields no bigger extraction — closing the domain past the fuzz cap. Under MockMorpho's real
    ///         HF ≥ 1 gate, confirms: (a) redeem succeeds AT the cap (so the whole fuzz range is genuinely
    ///         redeemable, not a lenient-mock artifact); (b) a deep crash reverts `redeem` AND `redeemInKind`
    ///         (both do a pro-rata `withdrawCollateral` the HF check rejects underwater), and the Case-B
    ///         flash-loan path fails too — so the self-cap is complete, not Case-A-specific.
    function test_Core_PastCapExitReverts() public {
        _pricedDex(WETH_PRICE, 1e18);
        _deposit(honest, 10 ether);
        uint256 sA = _deposit(attacker, 1000 ether);
        MockMorpho(address(MORPHO)).setEnforceHf(true);

        // At the fuzz cap (27.5% drop) the position is still solvent: the redeem executes. This is
        // what makes the whole [cap, stale] fuzz range meaningful rather than an artifact of a
        // lenient mock.
        uint256 snap = vm.snapshotState();
        marketOracle.setPrice(MIN_TRUE_PRICE);
        vm.prank(attacker);
        vault.redeem(sA, attacker, attacker); // must not revert
        vm.revertToState(snap);

        // A deep crash (50% drop) puts the leverage underwater: neither exit can complete.
        marketOracle.setPrice(WETH_PRICE / 2);

        uint256 snap2 = vm.snapshotState();
        vm.prank(attacker);
        vm.expectRevert();
        vault.redeem(sA, attacker, attacker);
        vm.revertToState(snap2);

        // redeemInKind (the swap-free hatch) also can't escape underwater — same pro-rata withdraw.
        MockERC20(address(PYUSD0)).mint(attacker, 100_000_000e18);
        vm.startPrank(attacker);
        PYUSD0.approve(address(vault), type(uint256).max);
        vm.expectRevert();
        vault.redeemInKind(sA, attacker, attacker);
        vm.stopPrank();
    }

    function _sizedPnl(uint256 inAmt) internal returns (int256 pnl) {
        uint256 s = vm.snapshotState();
        pnl = _attackNetPnlSized(1.5e18, MIN_TRUE_PRICE, 1, inAmt); // δ=27.5%, real 1 bp pool fee
        vm.revertToState(s);
    }

    // ---- tests ---------------------------------------------------------

    /// @notice Balanced position (k = Y·Py/D = 1): asserts the attacker's timing PnL
    ///         (vs. the oracle-already-fresh counterfactual) is ≤ dust.
    function test_Core_BalancedNoExtraction() public {
        (int256 ext,,,) = _stalePriceArbCycle(1e18, 1800e36); // k=1
        assertLe(ext, 2, "balanced front-run must not extract");
    }

    /// @notice A permissionless `rebalance()` interposed in the straddle cannot amplify extraction. It mints
    ///         no shares to the caller (the only mint on that path is `_accrueFees` → `feeRecipient`), so the
    ///         attacker's share fraction is fixed and any swap cost is pro-rata: `π_rebalance = π_plain − f·cost
    ///         ≤ π_plain`. With a real gap present (carry + 27.5% stale-Pc drop → π_plain ≈ 1.11 WETH),
    ///         interposing `rebalance()` at either point — Pc still stale, or after it refreshes — changes the
    ///         take by 0 and never touches principal. (The `fA != fB` diagnostic shows whether the leg fired or
    ///         skipped at the swap limit; amplification is 0 either way.)
    function test_Core_RebalanceDoesNotAmplify() public {
        uint256 kWad = 1.5e18; // carry present → a real gap to extract (π_plain > 0)
        MockSwapRouter router = _pricedDex(MIN_TRUE_PRICE, 1e18); // 27.5% drop = the stale-Pc gap
        _deposit(honest, 10 ether);
        yieldOracle.setPrice(kWad * 1e18);
        router.setRate(address(FUSDEV), address(PYUSD0), kWad);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kWad);
        // Align the yield/debt pool to the oracle (k≈1.5) so the interposed rebalance's swap gate passes
        // and the leg actually FIRES — otherwise it skips against the 1:1 mock and the test is a no-op.
        yieldPool.setSqrtPriceX96(64500000000000000000000000000);

        uint256 inAmt = 1000 ether; // attacker holds ~all supply → maximal extraction
        uint256 snap = vm.snapshotState();

        // World P — plain straddle: deposit at the stale mark, refresh the oracle, redeem.
        uint256 s = _deposit(attacker, inAmt);
        marketOracle.setPrice(MIN_TRUE_PRICE);
        int256 piPlain = int256(_redeem(attacker, s)) - int256(inAmt);
        assertGt(piPlain, 0, "no gap to amplify - amplification bound would be vacuous");
        vm.revertToState(snap);

        // World R1 — interpose rebalance() while Pc is still STALE. fB1/fA1 record whether the leg
        // actually moved value (it may fire a lever or skip at the swap limit; amplification is 0 either way).
        s = _deposit(attacker, inAmt);
        uint256 fB1 = FUSDEV.balanceOf(address(vault));
        vault.rebalance();
        uint256 fA1 = FUSDEV.balanceOf(address(vault));
        marketOracle.setPrice(MIN_TRUE_PRICE);
        int256 piRebStale = int256(_redeem(attacker, s)) - int256(inAmt);
        uint256 honestStale = _honestClaim();
        vm.revertToState(snap);

        // World R2 — interpose rebalance() AFTER Pc refreshes. At the crashed Pc the position is below
        // the HF band, so the interposed rebalance FIRES a delever (sells yield → repays debt).
        s = _deposit(attacker, inAmt);
        marketOracle.setPrice(MIN_TRUE_PRICE);
        uint256 fB2 = FUSDEV.balanceOf(address(vault));
        vault.rebalance();
        uint256 fA2 = FUSDEV.balanceOf(address(vault));
        int256 piRebFresh = int256(_redeem(attacker, s)) - int256(inAmt);
        uint256 honestFresh = _honestClaim();

        emit log_named_int("plain straddle PnL (wei)", piPlain);
        emit log_named_int("rebalance-at-stale PnL (wei)", piRebStale);
        emit log_named_int("rebalance-at-fresh PnL (wei)", piRebFresh);
        emit log_named_int("amplification, stale-insert (wei)", piRebStale - piPlain);
        emit log_named_int("amplification, fresh-insert (wei)", piRebFresh - piPlain);
        emit log_named_uint("stale-insert rebalance moved value? (1/0)", fA1 != fB1 ? 1 : 0);
        emit log_named_uint("fresh-insert rebalance moved value? (1/0)", fA2 != fB2 ? 1 : 0);
        emit log_named_uint(
            "honest claim after, worst case (principal 10e18)", honestStale < honestFresh ? honestStale : honestFresh
        );

        // At least one interposed rebalance must actually FIRE (move value), or the amplification check is
        // vacuous. The pool is aligned above, so the fresh-insert delever fires at the crashed Pc.
        assertTrue(fA1 != fB1 || fA2 != fB2, "no interposed rebalance fired - amplification test vacuous");
        // Inserting a rebalance at EITHER point never amplifies (it mints the attacker no shares; any
        // swap cost is pro-rata), and never reaches honest principal.
        assertLe(piRebStale, piPlain + 2, "rebalance-at-stale amplified extraction");
        assertLe(piRebFresh, piPlain + 2, "rebalance-at-fresh amplified extraction");
        assertGe(honestStale, 10 ether - 2, "rebalance-at-stale reached principal");
        assertGe(honestFresh, 10 ether - 2, "rebalance-at-fresh reached principal");
    }

    /// @notice Fuzzes carry unbalance k ∈ [1, 2] and oracle staleness δ ∈ [0, ~27%].
    ///         Asserts the honest holder's loss is no more than the oracle staleness
    ///         gap itself (loss% ≤ δ%), and that the attacker's gain ≈ the honest
    ///         holder's loss (value is moved between them, not created).
    function testFuzz_Core_LossWithinStalenessGap(uint256 kWad, uint256 truePriceE36) public {
        kWad = bound(kWad, 1e18, 2e18);
        // δ bounded to the region where the corrected position keeps HF ≥ 1, so the
        // redeem exit executes on real Morpho (MockMorpho skips the HF ≥ 1 withdraw
        // check; below ~1400e36 real Morpho would revert the exit).
        truePriceE36 = bound(truePriceE36, MIN_TRUE_PRICE, WETH_PRICE);
        (int256 ext, int256 loss, uint256 base, uint256 honestAfter) = _stalePriceArbCycle(kWad, truePriceE36);
        uint256 lossBps = base == 0 ? 0 : uint256(loss > 0 ? loss : int256(0)) * 10000 / base;
        uint256 stalenessGapBps = (WETH_PRICE - truePriceE36) * 10000 / WETH_PRICE;
        assertLe(lossBps, stalenessGapBps, "honest loss exceeds the oracle staleness gap");
        // Conservation: any extraction is funded by honest loss, never minted.
        assertApproxEqAbs(
            uint256(ext > 0 ? ext : int256(0)),
            uint256(loss > 0 ? loss : int256(0)),
            base / 200,
            "attacker gain must ~equal honest loss"
        );
        // Principal preserved: the extraction comes out of the honest holder's GAIN, not
        // their deposit. Their post-attack claim (collateral units) stays >= the 10 WETH
        // they put in — so this is dilution of upside, not a principal loss.
        emit log_named_uint("honest principal (WETH)", 10 ether);
        emit log_named_uint("honest claim after attack", honestAfter);
        assertGe(honestAfter, 10 ether - 2, "extraction reached principal, not just the gain");
    }

    /// @notice The OPPOSITE staleness direction (Pc stale-LOW: collateral has risen but the oracle
    ///         still reads the old, lower price, so NAV is OVER-marked, Δ<0) is defender-favorable —
    ///         not a second attack. The mint prices off the over-marked mark, so the attacker OVERPAYS,
    ///         while redeem realizes at true (A1); the timing edge is therefore ≤ 0 and honest holders
    ///         are not harmed (the mistimed deposit subsidizes them). Demonstrates the deposit/redeem
    ///         asymmetry §3 argues for the Δ<0 case, rather than leaving it argued.
    function testFuzz_Core_OverMarkUnprofitable(uint256 kWad, uint256 truePriceE36) public {
        kWad = bound(kWad, 1e18, 2e18);
        // true > booked (2000): collateral rose, oracle stale-low → NAV over-marked (Δ < 0).
        truePriceE36 = bound(truePriceE36, WETH_PRICE + 1e36, 2 * WETH_PRICE);
        (int256 ext,, uint256 base, uint256 honestAfter) = _stalePriceArbCycle(kWad, truePriceE36);
        // Attacker's timing edge is not positive: depositing at the over-marked mark overpays (it is
        // strictly negative once there is a carry to mis-mark, k>1; ~0 dust when balanced).
        assertLe(ext, int256(base / 1000), "over-mark direction extracted value");
        // Honest holders are not harmed — the mistimed deposit subsidizes them.
        assertGe(honestAfter, base - base / 1000, "over-mark direction harmed honest holders");
    }

    /// @dev Honest-holder harm (bps of their realizable claim) from an attacker deposit
    ///      of `atkAmt` during a yield mark-vs-DEX divergence: DEX price `pyDexWad` vs the
    ///      convertToAssets backing (1e18). Works in BOTH directions — `pyDexWad < 1`
    ///      (discount: attacker's own yield over-booked) and `pyDexWad > 1` (premium /
    ///      oracle lags an increase: honest's yield under-booked, attacker mints cheap).
    ///      Counterfactual: honest redeem with vs. without the attacker deposit.
    function _divergenceHarmBps(uint256 pyDexWad, uint256 atkAmt) internal returns (uint256) {
        MockSwapRouter router = _pricedDex(WETH_PRICE, 1e18); // peg entry, oracle fresh
        uint256 honestShares = _deposit(honest, 10 ether);
        router.setRate(address(FUSDEV), address(PYUSD0), pyDexWad);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / pyDexWad);

        uint256 snap = vm.snapshotState();
        _deposit(attacker, atkAmt);
        uint256 withAtk = _redeem(honest, honestShares);
        vm.revertToState(snap);
        uint256 without = _redeem(honest, honestShares);

        uint256 harm = without > withAtk ? without - withAtk : 0;
        return without == 0 ? 0 : harm * 10000 / without;
    }

    /// @notice Attacker *profitability* (distinct from honest *harm*, which is fee-independent — the attacker's
    ///         DEX fees go to the pool's LPs, not back to holders). The DEX fee is only a PARTIAL offset, not
    ///         the defense: the dominant legs trade the low-fee yield/debt pool (1 bp here), where the attack
    ///         still nets a small positive profit (growing with δ) and only flips negative above a ~5-10 bp
    ///         break-even. So the operative controls are the staleness keeper (δ→0) and the never-principal
    ///         ceiling, not the fee. Asserts the break-even bracket to put the fee's limited role on the record.
    function test_Control_DexFeeOnlyPartiallyOffsets() public {
        // Largest-δ point (27.5%); the effect is monotone in δ so this is the strongest case.
        uint256 price = MIN_TRUE_PRICE;

        uint256 s0 = vm.snapshotState();
        int256 atLowFee = _attackNetPnl(1.5e18, price, 1); // 1 bp = the vault's yield/debt tier
        vm.revertToState(s0);
        uint256 s1 = vm.snapshotState();
        int256 atHighFee = _attackNetPnl(1.5e18, price, 30); // 30 bp
        vm.revertToState(s1);

        emit log_named_int("net PnL @ 1bp (wei)", atLowFee);
        emit log_named_int("net PnL @ 30bps (wei)", atHighFee);
        // At the real low pool fee the attack still profits: the fee is not the defense.
        assertGt(atLowFee, 0, "fee assumed to defeat the attack, but it profits at 1 bp");
        // It only flips negative at a much higher fee -> break-even is in between.
        assertLt(atHighFee, 0, "attack unexpectedly still profitable even at 30 bps");
    }

    /// @notice DEX-*execution* divergence (NOT a credit de-peg). The vault BOOKS the yield leg at
    ///         `Py_oracle` (convertToAssets) but a redeem SELLS it into the DEX at `Py_dex`; this
    ///         fuzzes a divergence between the two — the harness moves the DEX **router rate**, not
    ///         `yieldOracle` — in both directions and over attacker size, and asserts honest harm ≤
    ///         the divergence magnitude `|Py_dex/Py_oracle − 1|`. (A genuine credit de-peg —
    ///         `convertToAssets` itself falling — is a separate credit-risk matter, out of scope here.)
    function testFuzz_Source_YieldDivergenceWithinGap(uint256 pyDexWad, uint256 atkAmt) public {
        pyDexWad = bound(pyDexWad, 0.1e18, 2e18); // execution divergence down to 90% / up to +100%
        atkAmt = bound(atkAmt, 1 ether, 100000 ether);
        uint256 gapBps = (pyDexWad > 1e18 ? pyDexWad - 1e18 : 1e18 - pyDexWad) * 10000 / 1e18;
        uint256 harmBps = _divergenceHarmBps(pyDexWad, atkAmt);
        assertLe(harmBps, gapBps + 2, "honest harm exceeds the DEX-execution divergence");
    }

    /// @notice COLLATERAL-axis oscillation does not compound. If `Pc` bounces stale(2000)↔fresh(1800)
    ///         and the attacker sandwiches each swing, the drain SATURATES — it does not stack per
    ///         bounce — because the carry is `Pc`-INDEPENDENT (`G = Y·Py − D`), so a swing re-marks the
    ///         same fixed pot and injects nothing. Asserts no per-round acceleration (last ≤ first),
    ///         cumulative within ~2× one event, principal preserved, and the composition converging to a
    ///         fixed point (per-round motion → 0). (Yield-axis twin below saturates the same way — the
    ///         composition converges — its pot stays bounded for a source-specific reason: redeem reads no oracle, A1.)
    function test_Repetition_CollateralOscillationDoesNotCompound() public {
        MockSwapRouter router = _pricedDex(1800e36, 1e18);
        _deposit(honest, 10 ether);
        uint256 kWad = 1.5e18; // carry so an edge exists each swing
        yieldOracle.setPrice(kWad * 1e18);
        router.setRate(address(FUSDEV), address(PYUSD0), kWad);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kWad);

        uint256 inAmt = 1000 ether;
        uint256 rounds = 10;
        marketOracle.setPrice(1800e36);
        uint256 baseline = _honestClaim();
        int256 firstExtraction;
        int256 lastExtraction;
        uint256 ybStart = FUSDEV.balanceOf(address(vault)); // composition before any attack
        uint256 yb0;
        uint256 ybPrev;
        uint256 ybLast;
        for (uint256 i = 0; i < rounds; i++) {
            marketOracle.setPrice(2000e36); // jitter: re-stale
            uint256 s = _deposit(attacker, inAmt);
            marketOracle.setPrice(1800e36); // bounce back to fresh
            int256 pnl = int256(_redeem(attacker, s)) - int256(inAmt);
            if (i == 0) firstExtraction = pnl;
            if (i == rounds - 1) lastExtraction = pnl;
            // Attacker fully unwound → end-of-round is the honest-only composition.
            uint256 yb = FUSDEV.balanceOf(address(vault));
            if (i == 0) yb0 = yb;
            if (i == rounds - 2) ybPrev = yb;
            if (i == rounds - 1) ybLast = yb;
        }
        uint256 endClaim = _honestClaim();
        uint256 cumulativeLoss = baseline > endClaim ? baseline - endClaim : 0;
        assertGt(firstExtraction, 0, "setup no longer extracts in round 1; saturation bounds vacuous");
        assertLe(lastExtraction, firstExtraction, "extraction accelerates across bounces (compounds)");
        assertLe(cumulativeLoss, 2 * uint256(firstExtraction), "jitter drain accumulates instead of saturating");
        assertGe(endClaim, 10 ether, "jitter drain reached principal");

        // Saturation IS convergence to a composition fixed point: the deposit/redeem straddle settles the
        // composition, so per-round motion decays toward zero (same mechanism as the yield twin below).
        uint256 firstMove = ybStart > yb0 ? ybStart - yb0 : yb0 - ybStart;
        uint256 lastMove = ybPrev > ybLast ? ybPrev - ybLast : ybLast - ybPrev;
        assertLt(lastMove, firstMove / 100, "collateral composition still moving at horizon end - not converging");

        // Principal floor on a REALIZED redeem (oracle-free, A1), mirroring the yield twin — so the claim
        // doesn't rest on a mark-based preview alone.
        assertGe(_redeem(honest, vault.balanceOf(honest)), 10 ether - 2, "collateral-jitter drain reached principal");
    }

    /// @notice YIELD-axis oscillation does not compound — the twin of the collateral case, and the one
    ///         the suite was missing. The yield *mark* (`yieldOracle`) jitters stale-low↔true each round
    ///         while the true realization value (the DEX rate) is held FIXED, and the attacker sandwiches
    ///         each dip. It saturates too — but NOT because the carry is source-independent (it isn't; the
    ///         carry IS the yield mark's value). It saturates because redeem reads no oracle (A1): a
    ///         wobbling mark can only mis-price the MINT; the composition settles so a fresh mint self-cancels
    ///         and the persistent gap stops being extractable. A genuine *true-value* de-peg down-move is different
    ///         (credit risk, out of scope — §7); here the realization is pinned, so only the mark moves.
    function test_Repetition_YieldOscillationDoesNotCompound() public {
        uint256 kTrue = 1.5e18; // true yield value — held FIXED (stable realization)
        uint256 kStale = 1.35e18; // the mark reads ~10% low when "stale" (under-marks NAV → over-issue)
        MockSwapRouter router = _pricedDex(1800e36, 1e18);
        _deposit(honest, 10 ether);
        // Realization (DEX) pinned at the true value; Pc fresh & fixed — isolate the yield mark.
        router.setRate(address(FUSDEV), address(PYUSD0), kTrue);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kTrue);
        marketOracle.setPrice(1800e36);

        uint256 inAmt = 1000 ether;
        uint256 rounds = 10;
        yieldOracle.setPrice(kTrue * 1e18);
        uint256 baseline = _honestClaim();
        int256 firstExtraction;
        int256 lastExtraction;
        uint256 ybStart = FUSDEV.balanceOf(address(vault)); // honest-only composition, before any attack
        uint256 yb0;
        uint256 ybPrev;
        uint256 ybLast;
        for (uint256 i = 0; i < rounds; i++) {
            yieldOracle.setPrice(kStale * 1e18); // mark jitters stale-low → NAV under-marked
            uint256 s = _deposit(attacker, inAmt);
            yieldOracle.setPrice(kTrue * 1e18); // mark back to true
            int256 pnl = int256(_redeem(attacker, s)) - int256(inAmt);
            if (i == 0) firstExtraction = pnl;
            if (i == rounds - 1) lastExtraction = pnl;
            // Attacker fully unwound → end-of-round is the honest-only composition.
            uint256 yb = FUSDEV.balanceOf(address(vault));
            if (i == 0) yb0 = yb;
            if (i == rounds - 2) ybPrev = yb;
            if (i == rounds - 1) ybLast = yb;
        }
        uint256 endClaim = _honestClaim();
        uint256 cumulativeLoss = baseline > endClaim ? baseline - endClaim : 0;
        emit log_named_int("yield-jitter first extraction (wei)", firstExtraction);
        emit log_named_int("yield-jitter last  extraction (wei)", lastExtraction);
        emit log_named_uint("yield-jitter cumulative honest loss over 10 rounds (wei)", cumulativeLoss);

        assertGt(firstExtraction, 0, "setup no longer extracts in round 1; saturation bound vacuous");
        assertLe(lastExtraction, firstExtraction, "yield-mark jitter extraction accelerates (compounds)");
        assertLe(cumulativeLoss, 2 * uint256(firstExtraction), "yield-jitter drain accumulates instead of saturating");

        // Saturation IS convergence to a composition fixed point: cycle 0 shifts the yield balance hard
        // (the one-time extraction), then per-round motion decays toward zero. A re-arming dynamic would
        // keep moving the composition by a comparable amount every round instead of settling.
        uint256 firstMove = ybStart > yb0 ? ybStart - yb0 : yb0 - ybStart;
        uint256 lastMove = ybPrev > ybLast ? ybPrev - ybLast : ybLast - ybPrev;
        assertLt(lastMove, firstMove / 100, "yield composition still moving at horizon end - not converging");

        // Principal floor on a REALIZED redeem (oracle-free, A1) — the mark that jittered can't mask it.
        uint256 realized = _redeem(honest, vault.balanceOf(honest));
        emit log_named_uint("yield-jitter honest realized (WETH wei; principal = 10e18)", realized);
        assertGe(realized, 10 ether - 2, "yield-jitter drain reached principal");
    }

    /// @notice The one deposit/redeem path that reaches PRINCIPAL — a conditional edge, not a first-class
    ///         finding. A deposit levered unlike the book during a yield-mark *discount* (mark above the DEX,
    ///         §3): the cheaply-bought yield is credited at the high mark and over-mints, and because the
    ///         deposit is levered unlike the book the misprice no longer cancels (A5 needs uniformity), so it
    ///         lands on PRINCIPAL. Needs BOTH the skew and the discount — either alone extracts ~0. Assumes
    ///         normal operation: a keeper rebalance() re-levers the skew first (un-rebalanced would relitigate
    ///         liveness/liquidation, out of scope), and a residual survives because rebalance restores the HF
    ///         band, not the leverage a fresh deposit assumes. Sweeps to the 90% in-scope divergence: harm ≤
    ///         gap throughout, growing with it (~3% of NAV at 90%). Un-manufacturable; register R24.
    function test_Source_DifferentlyLeveredDiscountReachesPrincipal() public {
        uint256 q = 1.5e18; // pool rate for yield
        MockSwapRouter router = _pricedDex(1800e36, 1e18);
        router.setRate(address(FUSDEV), address(PYUSD0), q);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / q);
        marketOracle.setPrice(1800e36);
        yieldOracle.setPrice(q * 1e18);
        yieldPool.setSqrtPriceX96(64500000000000000000000000000); // align pool so the delever fires
        _deposit(honest, 10 ether);

        // Create the mismatch: crash Pc → HF below band → delever sells yield (pool under-dense), restore Pc.
        // Crash deep (1300) for a strong mismatch — a deeper delever leaves the vault further under-levered.
        marketOracle.setPrice(1300e36);
        vault.rebalance();
        marketOracle.setPrice(1800e36);

        uint256 base = vm.snapshotState();

        // Control — mismatch present, NO discount (mark == pool). The one-sided condition extracts nothing.
        yieldOracle.setPrice(q * 1e18);
        uint256 sc = _deposit(attacker, 1000 ether);
        int256 pnlNoDisc = int256(_redeem(attacker, sc)) - int256(1000 ether);
        vm.revertToState(base);
        assertLe(pnlNoDisc, int256(2), "mismatch alone (no discount) extracted value");

        // Principal reference: honest's realized claim with no attacker (redeem is mark-independent, A1).
        uint256 clean = _redeem(honest, vault.balanceOf(honest));
        vm.revertToState(base);

        // Each point: the attack extracts, is zero-sum from holders, reaches principal, and stays under the
        // divergence gap; the hit grows with the gap. (`_leveredHit` interposes the keeper rebalance — natspec.)
        uint16[3] memory ePcts = [uint16(5), 20, 90];
        uint256 wideLoss;
        for (uint256 i = 0; i < ePcts.length; i++) {
            uint256 ePct = ePcts[i];
            (int256 pnl, uint256 dirty) = _leveredHit(q * (100 + ePct) / 100 * 1e18);
            vm.revertToState(base);
            uint256 loss = clean > dirty ? clean - dirty : 0;

            emit log_named_uint("discount %", ePct);
            emit log_named_uint("  honest realized (principal 10e18)", dirty);

            assertGt(pnl, int256(0), "combined case did not extract");
            assertGe(loss, uint256(pnl), "holders should lose at least the attacker's gain");
            assertLe(loss * 100, clean * ePct, "harm exceeds the divergence gap");
            assertLt(dirty, 10 ether, "did not reach principal");
            wideLoss = loss;
        }
        // At the wide (90%) end the hit is a few percent of principal — not "tiny".
        assertGe(wideLoss, 0.1 ether, "wide-divergence principal hit too small");
    }

    /// @dev Realistic operation at yield `mark`: a keeper rebalance() re-levers the mismatch, then the
    ///      attacker deposits 1000 and redeems. Returns the attacker PnL and honest's realized claim after.
    ///      Caller snapshots/reverts around it.
    function _leveredHit(uint256 mark) internal returns (int256 pnl, uint256 dirty) {
        yieldOracle.setPrice(mark);
        vault.rebalance();
        uint256 s = _deposit(attacker, 1000 ether);
        pnl = int256(_redeem(attacker, s)) - int256(1000 ether);
        dirty = _redeem(honest, vault.balanceOf(honest));
    }

    /// @notice The sell side is dead (A1): a shareholder's redeem payout is independent of the yield mark.
    ///         Redeeming at a stale-HIGH or stale-LOW mark pays exactly what a fair mark pays — the payout
    ///         is the DEX-realized value of the slice, never the mark. So you can't be over- or under-paid
    ///         on the way OUT by a diverged mark, in either direction; the whole attack surface is the
    ///         deposit side. (Assumes the DEX is the true price — a depressed DEX is Exit_InKindFloors*.)
    function test_Exit_RedeemMarkIndependent() public {
        MockSwapRouter router = _pricedDex(1800e36, 1e18);
        router.setRate(address(FUSDEV), address(PYUSD0), 1.5e18);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / 1.5e18);
        marketOracle.setPrice(1800e36);
        yieldOracle.setPrice(1.5e18 * 1e18);
        _deposit(honest, 10 ether);
        uint256 as_ = _deposit(attacker, 10 ether);

        uint256 base = vm.snapshotState();
        uint256 fairOut = _redeem(attacker, as_); // fair mark
        vm.revertToState(base);

        base = vm.snapshotState();
        yieldOracle.setPrice(1.575e18 * 1e18); // stale-HIGH mark
        uint256 highOut = _redeem(attacker, as_);
        vm.revertToState(base);

        yieldOracle.setPrice(1.35e18 * 1e18); // stale-LOW mark
        uint256 lowOut = _redeem(attacker, as_);

        emit log_named_uint("redeem @ fair mark", fairOut);
        emit log_named_uint("redeem @ stale-high mark", highOut);
        emit log_named_uint("redeem @ stale-low mark", lowOut);
        assertApproxEqAbs(highOut, fairOut, 2, "redeem paid off a stale-HIGH mark - sell-side exploit");
        assertApproxEqAbs(lowOut, fairOut, 2, "redeem paid off a stale-LOW mark - sell-side exploit");
    }

    /// @notice Long-horizon REGENERATION variant of the oscillation test: real yield accrues each round,
    ///         harvest fires, and the attacker straddles every round for N rounds. Confirms the cumulative
    ///         bound is a δ-tax on the yield the vault genuinely earned — never principal. The principal
    ///         floor is checked on REALIZED redeem (reads no oracle, A1) so regeneration can't mask a leak,
    ///         via a no-attacker counterfactual from the same snapshot. Debt interest is not modeled
    ///         (MockMorpho accrual is a no-op) — omitting it is conservative (it would only shrink the pot).
    function test_Repetition_YieldRegenTaxNotPrincipal() public {
        MockSwapRouter router = _pricedDex(1800e36, 1e18);
        _deposit(honest, 10 ether);
        uint256 k = 1.5e18; // initial carry
        yieldOracle.setPrice(k * 1e18);
        router.setRate(address(FUSDEV), address(PYUSD0), k);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / k);

        uint256 inAmt = 1000 ether;
        uint256 rounds = 200;
        uint256 stepBps = 10; // +0.10% real yield per round
        marketOracle.setPrice(1800e36);
        uint256 snap = vm.snapshotState();

        // CLEAN run: identical accrual + harvest, NO attacker.
        uint256 kC = k;
        for (uint256 i = 0; i < rounds; i++) {
            kC = kC * (10_000 + stepBps) / 10_000;
            yieldOracle.setPrice(kC * 1e18);
            router.setRate(address(FUSDEV), address(PYUSD0), kC);
            router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kC);
            vault.rebalance();
        }
        marketOracle.setPrice(1800e36);
        uint256 realizedClean = _redeem(honest, vault.balanceOf(honest));

        vm.revertToState(snap);

        // DIRTY run: identical accrual + harvest, WITH attacker straddle each round.
        uint256 kD = k;
        int256 firstExtraction;
        int256 lastExtraction;
        for (uint256 i = 0; i < rounds; i++) {
            kD = kD * (10_000 + stepBps) / 10_000;
            yieldOracle.setPrice(kD * 1e18);
            router.setRate(address(FUSDEV), address(PYUSD0), kD);
            router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / kD);
            vault.rebalance();

            marketOracle.setPrice(2000e36); // re-stale
            uint256 s = _deposit(attacker, inAmt);
            marketOracle.setPrice(1800e36); // fresh
            int256 pnl = int256(_redeem(attacker, s)) - int256(inAmt);
            if (i == 0) firstExtraction = pnl;
            if (i == rounds - 1) lastExtraction = pnl;
        }
        marketOracle.setPrice(1800e36);
        uint256 realizedDirty = _redeem(honest, vault.balanceOf(honest));

        // Load-bearing: principal floor on REALIZED value (oracle-independent, unmasked by regeneration).
        assertGe(realizedDirty, 10 ether - 2, "regen arb reached principal");

        // Attacker-caused loss <= yield the vault genuinely earned + one initial standing-carry skim.
        // A per-cycle principal leak would make this ~N*eps and blow the envelope.
        uint256 attackerLoss = realizedClean > realizedDirty ? realizedClean - realizedDirty : 0;
        uint256 injectedCarry = realizedClean > 10 ether ? realizedClean - 10 ether : 0;
        assertGt(firstExtraction, 0, "setup no longer extracts in round 1; bound vacuous");
        assertLe(attackerLoss, injectedCarry + uint256(firstExtraction) + 2, "loss outran earned yield");

        // No per-round acceleration even as real yield refills the pot (harvest holds the standing carry).
        assertLe(lastExtraction, firstExtraction, "extraction accelerates as yield regenerates");
    }

    /// @notice Both sources off at once: Pc stale by δ AND the yield DEX diverged by d. Both hit the same
    ///         carry term (Y·Py − D)/Pc, so this checks they just ADD UP rather than amplify each other — the
    ///         combined honest loss is no worse than the two gaps summed (δ + d, plus a negligible δ·d
    ///         cross-term).
    function testFuzz_Source_CombinedWithinComposedGap(uint256 kWad, uint256 truePriceE36, uint256 pyDexWad) public {
        kWad = bound(kWad, 1e18, 2e18);
        truePriceE36 = bound(truePriceE36, MIN_TRUE_PRICE, WETH_PRICE); // δ ≤ ~27% (HF ≥ 1 region, as above)
        pyDexWad = bound(pyDexWad, 0.7e18, 1.5e18); // divergence d, both directions

        MockSwapRouter router = _pricedDex(truePriceE36, 1e18);
        _deposit(honest, 10 ether);

        // Carry at k on the oracle; the yield DEX diverges from that backing by pyDex.
        yieldOracle.setPrice(kWad * 1e18);
        uint256 dexK = kWad * pyDexWad / 1e18;
        router.setRate(address(FUSDEV), address(PYUSD0), dexK);
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / dexK);

        uint256 snap = vm.snapshotState();

        // Attack world: enter on the stale Pc mark and the diverged DEX, post the update, exit.
        uint256 sA = _deposit(attacker, 1000 ether);
        marketOracle.setPrice(truePriceE36);
        _redeem(attacker, sA);
        uint256 honestWith = _honestClaim();

        // Baseline world: no attacker at all, same fresh mark.
        vm.revertToState(snap);
        marketOracle.setPrice(truePriceE36);
        uint256 honestWithout = _honestClaim();

        uint256 loss = honestWithout > honestWith ? honestWithout - honestWith : 0;
        uint256 lossBps = honestWithout == 0 ? 0 : loss * 10000 / honestWithout;
        uint256 gapBps = (WETH_PRICE - truePriceE36) * 10000 / WETH_PRICE;
        uint256 divBps = (pyDexWad > 1e18 ? pyDexWad - 1e18 : 1e18 - pyDexWad) * 10000 / 1e18;
        uint256 composedBps = gapBps + divBps + gapBps * divBps / 10000;
        assertLe(lossBps, composedBps + 2, "combined loss exceeds the composed per-oracle bound");
    }

    /// @notice `redeemInKind` (raw pro-rata slice, no DEX swap) vs `redeem` (unwinds
    ///         the same slice through the DEX). Under a DEX discount, asserts the two exits
    ///         deliver equal value (WETH-equivalent, to ~1 wei) — so the redeem-based
    ///         bounds above also apply to the redeemInKind exit.
    ///         Pins the WITHDRAW side: `redeem` pays out the DEX-realized value of your slice, not an
    ///         internal mark — so you can't be over/under-paid by a stale mark on the way out. ("True" here
    ///         = the DEX price, i.e. assumes the DEX is accurate; a depressed/manipulated DEX is floored by
    ///         Exit_InKindFloorsDepressedRedeem, where holding the tokens beats selling into the bad pool.)
    function test_Exit_InKindEqualsRedeem() public {
        MockSwapRouter router = _pricedDex(WETH_PRICE, 1e18);
        uint256 hs = _deposit(honest, 10 ether);
        router.setRate(address(FUSDEV), address(PYUSD0), 0.9e18); // 10% discount
        router.setRate(address(PYUSD0), address(FUSDEV), uint256(1e18) * 1e18 / 0.9e18);
        uint256 snap = vm.snapshotState();

        // Exit A: redeem — the vault unwinds the slice through the DEX to WETH.
        uint256 wethRedeem = _redeem(honest, hs);

        // Exit B: redeemInKind — take the raw slice, then unwind it through the same
        // DEX by hand (sell yield at Py_dex=0.9, net the debt repaid, PYUSD→WETH @2000).
        vm.revertToState(snap);
        MockERC20(address(PYUSD0)).mint(honest, 1_000_000 ether); // buffer to repay the debt slice
        vm.startPrank(honest);
        PYUSD0.approve(address(vault), type(uint256).max);
        uint256 pyBefore = PYUSD0.balanceOf(honest);
        (uint256 collOut, uint256 yieldOut) = vault.redeemInKind(hs, honest, honest);
        uint256 debtPaid = pyBefore - PYUSD0.balanceOf(honest);
        vm.stopPrank();

        int256 netPy = int256(yieldOut * 9 / 10) - int256(debtPaid);
        int256 wethKind = int256(collOut) + netPy / 2000;

        assertApproxEqAbs(uint256(wethKind), wethRedeem, 2, "redeemInKind value != redeem value");
    }
}
