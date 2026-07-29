# FCMVault — Stale-Price Arbitrage: Unit-Test Findings

*Unit-test bounds on one attack: how much an attacker can pull out by depositing and redeeming around a
stale or diverged price. This is the **executable-evidence slice** for that single surface — it quantifies
and regression-guards it. It is **not** the general value-conservation question (whether any ordering of
legitimate operations can extract value, across all surfaces); that is a separate, broader effort, and every
whole-surface claim here defers to it. Liquidation, a yield de-peg, and sustained negative carry are out of
scope.*

**Summary.** The attack — **stale-price arbitrage**: deposit while the vault's share price is mismarked
— a stale collateral oracle, or a yield mark diverged from where it trades — redeem once it corrects, and keep
the gap between the price you minted at and the true value the vault pays out. It's risk-free
(one atomic transaction) but tightly bounded. The tests show:

- The most it can take is that price gap — and for a *uniform* mispricing the gap only ever touches the
  **carry** (the yield the leveraged position holds, net of its debt), **not the principal** (the collateral
  you deposited). The lone exception — a deposit levered unlike the book during a pool dislocation — is tiny
  (~0.04–0.1%) and unmanufacturable (§3).
- A bigger deposit takes a bigger slice of the gap, but never more than the gap; after trading fees, it
  stops paying past a certain size.
- Repeating the cycle doesn't compound — the pot is finite and price motion can't refill it.
- All of it shrinks to zero as the oracle stays fresh.

That ceiling is on the deposit/redeem *arbitrage*. Adjacent channels — §5's forced-swap skim, a sustained
negative carry — are bounded separately and not all principal-fenced.

Each finding is a short mathematical argument checked against property-based (fuzz) tests over the reachable
range — evidence, not a formal proof (§7).

**What we're measuring.** The vault has two prices for the same share: the **booked** value `V̂`, computed
from the stale oracle when you `deposit`, and the **true value** `V*`, what `redeem` actually pays — no
oracle reprices the payout (A1). Their gap,

    Δ = V* − V̂,

is a **mispricing**: a quoted price that differs from the real one. The attack this doc measures is
**arbitrage** against it — mint at the cheap `V̂`, exit at the true `V*`. This is **stale-price arbitrage**, the same
mechanism as mutual-fund *market-timing* (trading at a stale NAV), and its harm to holders is **dilution**. Profit can't exceed the mispricing — the tests below bound how
much. So the question this doc reduces to **how big `Δ` can get and what it touches** — the rest of
this doc.

Two things are *not* this arbitrage and are handled separately: a **bug** (mints value from nothing, so
nothing bounds it — out of scope, the audit's job) and **fee griefing** (the attacker gains nothing — §5).

## 1. Model and assumptions

Vault value per the code, in collateral units:

    V = C + (Y·Py − D) / Pc

- `C` — **principal**: the collateral (WETH) deposited. A token count, so no oracle reprices it.
- `Y·Py − D` — **carry** (call it `G`): the yield holding (`Y` FUSDEV marked at `Py`) minus the debt
  `D` (PYUSD). This is the only part of `V` an oracle moves.
- `Pc` — the collateral oracle (loan per collateral). A Pyth **pull** oracle: the attacker can time the
  update inside their own transaction, and it's stale between updates.
- `Py` — the yield **mark**: FUSDEV's own `convertToAssets` rate, what a deposit is priced against. It
  is *not* the DEX price — the vault trades yield on the AMM at an independent rate `Py_dex`, so the two
  can diverge.

**Booked vs. true (detail).** `V̂` uses the marks a deposit is priced at — stale `Pc`, yield at
`convertToAssets`; `V*` uses the marks a redeem realizes at — fresh `Pc`, yield at `Py_dex`. So the gap
`Δ` comes from a stale `Pc`, a `Py`-vs-`Py_dex` divergence, or both (§3). Write `δ` for how stale `Pc` is,
as a fraction (`|booked − true| / booked`, how the fuzz tests normalize it).

**Assumptions** — each a checkable fact about the code:

- **(A1) No oracle reprices the payout.** `redeem`/`redeemInKind` hand back a pro-rata slice of the *actual
  holdings*, realized at the **DEX** price — which this doc takes as the true value (a mispriced pool is the
  §3 / §7 real-pool-fidelity item; it doesn't break this bound). The exit path still *reads* oracles (fee accrual, Morpho's health check),
  but none of them sets the price paid. *(Redeem payout is independent of the mark in both directions —
  `Exit_RedeemMarkIndependent`; both exits deliver the same true value — `Exit_InKindEqualsRedeem`. So the
  sell side of the timing game is dead, and the whole attack surface is the deposit side.)*
- **(A2) The mint reads the oracle.** `deposit` credits the booked value and mints in proportion, so a
  deposit of `x` earns `≈ x/(V̂+x)` of the vault afterward (`FCMVault:615`).
- **(A3) No entry/exit fee.**
- **(A4) It's atomic — a free option.** The attacker fixes booked and true in one transaction: enter at
  booked, optionally rebalance, exit at true; take the profitable side or abort. No risk.
- **(A5) Principal cancels — for a *uniform* mispricing** *(a consequence of A1, not a separate assumption).* When the misprice hits every share equally (a stale `Pc`, or a yield-mark move applied to the whole book), `C` is the same token count in `V̂` and `V*` — only the oracle-priced carry
  differs — so principal drops out of `Δ`. A deposit levered differently than the standing book breaks that uniformity (§3).

## 2. The core bound: profit ≤ mispricing, and (for a uniform mispricing) it never reaches principal

Three claims, each a short derivation the tests confirm.

**It's zero-sum.** Deposit and redeem only move value around: a deposit adds `x`, a redeem returns a
slice worth `P` at true prices (A1). So the attacker's profit `π = P − x` is the honest holders'
loss (with real fees, their loss ≥ the attacker's gain — §6) —
bounding profit bounds the harm. *(`Core_LossWithinStalenessGap` checks gain ≈ loss.)*

**Profit is capped by the gap.** A deposit `x` earns only a `x/(V̂+x)` share of the vault, so extraction is a *fraction* of the gap:

    π < Δ,

rising toward `Δ` as `x` grows (`x/(V̂+x) → 1`) but never past it. So more capital — leverage, flash loans — takes a
bigger slice of the *same* gap; it never widens the gap. Net of trading costs it's worse still: the DEX
fee grows with `x` (real price impact only sharpens it), so the attacker's net profit peaks at some size and
then goes negative. *(`Core_LossWithinStalenessGap`: honest loss stays within `δ` of the holder's claim.
`Core_ProfitConcaveInSize`: net profit peaks at an interior size. `Core_OverMarkUnprofitable`: the
opposite direction — vault *over*-valued — neither pays nor harms holders.)*

**It (almost) never reaches principal.** For a *uniform* mispricing, `Δ` involves only the carry `G`;
principal `C` cancels (A5), so the attack surface is the yield the position holds, not the deposited collateral
*(`Core_LossWithinStalenessGap`: `honest_after ≥ deposit`)*. The one exception is the differently-levered
discount over-mint of §3 — bounded and un-manufacturable, not a carry-fenced arb.

## 3. Where the gap comes from

Two sources, plus what happens if you try to manufacture one.

**Stale collateral oracle (`Pc`) — small.** The vault is WETH-in/WETH-out, and both it and Morpho read
the same `Pc`, so a price move barely shifts value-per-share. A balanced book (no carry) leaks only dust
(`Core_BalancedNoExtraction`); otherwise a stale mark misprices just the carry's conversion into collateral
units — loss within `δ`, never principal. Push the crash far enough and the corrected position is
underwater, at which point exits revert and a bigger move yields *nothing* more (`Core_PastCapExitReverts`:
redeem works at the ~27% fuzz cap, both exits revert at a 50% crash).

**Yield mark vs. DEX price (`Py` vs. `Py_dex`) — the real surface.** A deposit books yield at
`convertToAssets`, but the vault trades it at the DEX rate; any gap is live and works both ways, bounded
by the gap:

- **Premium** (DEX > mark): honest yield is under-booked, so the attacker mints cheap and skims the
  un-booked gain.
- **Discount** (DEX < mark): the attacker's yield is over-booked, so they over-mint and dilute holders. If
  the deposit is *levered unlike the book*, that over-mint isn't carry-fenced (A5 holds only for a uniform
  misprice), so it can reach **principal** — bounded by the gap, un-manufacturable, needing both the mismatch
  and the discount *(`Source_DifferentlyLeveredDiscountReachesPrincipal`; R24)*. A carrying vault's accrued
  carry absorbs it (it eats carry, not the deposit); it reaches principal only when the mark holds no buffer —
  `convertToAssets` dipping rather than ratcheting up (R12) — which is itself the §7 credit edge. Each event
  needs its own fresh setup, so repetition doesn't grow it.

Both are fuzzed (discount to 90%, premium to +100%) in `Source_YieldDivergenceWithinGap`, which caps
honest harm at the gap. The one pure-timing play — an appreciation sandwich — is bounded by that same gap
regardless.

**Manufacturing a gap doesn't pay — self-extraction loses, and a bystander can opt out.** The mark isn't
tradeable (it's `convertToAssets`, not the pool), so the only lever is pushing the DEX pool — which costs the
attacker the price impact, netting ≤ 0 on their own round-trip (`Manufacture_SelfExtractionUnprofitable`,
self-extraction bounded by `maxTvl`). Sandwiching a *bystander's* plain redeem is ordinary MEV — bounded not
by attacker-unprofitability but by the victim taking `redeemInKind`: the raw slice, worth at least the
manipulated redeem (`Exit_InKindFloorsDepressedRedeem`) and equal to a normal redeem at par
(`Exit_InKindEqualsRedeem`).

**Both at once.** A stale `Pc` and a yield divergence compound — roughly additively, with a small
cross-term — but there's no blow-up (`Source_CombinedWithinComposedGap`).

## 4. Repeating the cycle over a long horizon

The stale mark sticks around — a deposit doesn't refresh it — so the worry is a repeated, adversarially
timed, possibly trending sequence draining the vault over time. **For a uniform mispricing, principal is
unreachable for a reason that holds on every single cycle** (A5): each `Δ` misprices only the carry, so the
collateral token count `C` is outside the surface no matter how many cycles run — no cross-cycle accumulator
on the principal axis for repetition to walk. What's left is the cumulative *carry* loss, and it splits cleanly.

**Price motion can't refill the pot.** The extractable pot is the *standing* carry — finite, and
value-conserving price motion and rebalancing add nothing to it. So repetition can't compound: the cumulative
carry loss stays ≤ that one standing pot. The gap itself doesn't *close* — it persists; it just stops being
**extractable** after the first cycle (a fresh deposit can no longer mint in below true value). This holds on
**both** oracle axes: a `Pc` move re-marks a `Pc`-**independent** carry (`G = Y·Py − D`), injecting nothing;
a yield-**mark** wobble only mis-prices the *mint* — redeem reads no oracle (A1).
*(`Repetition_CollateralOscillationDoesNotCompound` and `Repetition_YieldOscillationDoesNotCompound`: 10 jitter
cycles each, per-round extraction never accelerates (last ≤ first), cumulative ≤ ~2× a single event, principal
intact — the yield case also shows the composition converging to a fixed point, per-cycle motion falling below
1% of the first. The ~2× is a fixed-pot artifact at N=10; a real up-trend exceeds it — next.)* The one yield
motion that reaches principal — a genuine `convertToAssets` **de-peg** — is a real credit loss the attacker
front-runs, not extraction (§7).

**Real yield is the only refill.** The carry regenerates solely from genuine accrual (`Py` rising).
Conservation — with A1 and A5 — caps the cumulative: the attacker can't transfer out more carry than the
vault ever holds:

    Σ πᵢ  ≤  (standing carry)  +  (real yield accrued).

The standing-carry piece is taken at most once (a residue that doesn't compound — the oscillation tests); the
yield piece is bounded by what the vault genuinely earns (`Repetition_YieldRegenTaxNotPrincipal`), unbounded
over infinite time only because cumulative yield is. It's a loose ceiling — the tests show the real number
sits inside it — not a tight derivation. Debt interest only *shrinks* the pot, never amplifies; harvest
(which *would* sweep surplus above `yieldFactorMax` into collateral) only shrinks it further — but it's
code-inspected: it never fires in these tests, so the bound rests on the tested numbers and this loose
ceiling, not on harvest. The formal conservation proof is the separate value-conservation review's (§7).

## 5. Adjacent surfaces

Outside the deposit/redeem cycle:

- **Rebalance/harvest swaps.** When the vault swaps at a booked price it leaks the same gap to its DEX
  counterparty — ordinary swap MEV. Two things are tested: the swap mints no shares and interposing a
  `rebalance()` adds nothing to the straddle (`Core_RebalanceDoesNotAmplify` = 0 — with the yield pool
  aligned so a real delever fires, not a no-op), and every leg fills no
  worse than `oracle ± maxSlippageBps` (mechanism in `FCMVault.t.sol`), so the counterparty skim is bounded
  per leg by `(maxSlippageBps + that leg's oracle gap) · volume` — the yield-mark gap on the yield legs, the
  `Pc` staleness `δ` on the collateral leg. Unlike the
  deposit/redeem arbitrage this is a **real execution cost**: A5 does not fence it from principal and it does
  **not** saturate — it sums with price volatility (ordinary leveraged-vault drag), bounded *per event* by
  `maxSlippageBps`, throttled by the HF dead-band, killed as `δ→0`. Not a principal drain; real-pool fidelity
  is the audit's to check (§7).
- **Performance-fee crystallization — separate concern, flagged not analyzed.** `accrueFees` crystallizes
  the fee on the marked price-per-share, so a transiently-inflated mark (a stale one among others) over-mints
  permanent fee-shares. That's a fee-accounting/griefing matter rooted in the fee model and high-water mark —
  its own issue, not stale-price extraction — so it's out of scope here, noted only so it isn't missed.
- **Bugs — out of scope.** No gap behind them, so no ceiling (per the framing up top); the audit's job.
- **Why A1 matters.** If any payout path read a mark, redeem would pay the booked value instead of the true
  one and profit could exceed `Δ`. (A1 lists the reads that do occur — none reprices the payout.) The
  deposit/redeem swap legs are intentionally unfloored; per-user slippage is the ERC-4626 router's job.

## 6. Mitigations

How each mitigation bears on the measured extraction:

- **DEX fee** — only a partial offset. Net profit is still positive at the real 1 bp tier
  (`Control_DexFeeOnlyPartiallyOffsets` checks the sign; the magnitude is under 1 WETH at this test scale per
  `Core_ProfitConcaveInSize`, the general ceiling being `π < Δ`) and turns negative only at a much higher fee.
  The fee alone is not the defense.
- **Oracle freshness** — extraction scales with `δ` and vanishes as `δ → 0`. The long-run leak is bounded by
  the yield the vault earns (§4), so the danger is not any single stale event but **persistent** `δ` over an
  accruing carry. A staleness keeper drives `δ → 0`.
- **Harvest / slippage limit** — harvest would keep the carry small, but it's code-inspected only (never
  fires in these tests; the bound rests on conservation — §4). The swaps' `maxSlippageBps` limit is the §5 surface.

## 7. Limitations

What this is, and isn't:

- **Arguments + tests, not formal verification.** Each bound is a short argument — closed-form algebra for
  the §2–3 gap bounds, a conservation/saturation argument for the §4 repetition case — checked by tests over
  the reachable range (fuzzed for §2–3, deterministic scenarios for repetition and controls). Strong
  evidence, not a machine-checked proof.
- **Conditional on the assumptions (A1–A5).** Those are asserted as checkable facts about the code, not
  proven exhaustive. If one breaks — e.g. a payout path starts reading a mark (A1) — the bounds break with it.
- **Bounds on identified paths — not a proof of exhaustiveness.** Every extraction path we *identified* is
  bounded here; we do not claim the list is complete. The universal — "no attack vector at all" / full value
  conservation — is a formal, whole-surface question beyond what these unit tests can establish; it belongs
  to the separate value-conservation review, not this deliverable.
- **Extraction only — real losses that aren't extraction are out of scope.** This bounds what an attacker
  can *take* via deposit/redeem/rebalance. Three channels *do* reach principal but sit outside it, because
  each is a loss the vault takes, not value conjured from the gap: a stale-`Pc` over-lever (or stalled
  delever) → Morpho liquidation (penalty bounded by the LIF); a stale/reverting feed bricking exits; and a
  genuine FUSDEV de-peg (credit risk). The first two are tracked in the register (R21–R23, R6/R7).
- **The tests run on mocks.** `δ` is a settable test parameter, not a real Pyth staleness/confidence check;
  and the forced-swap counterparty skim can't be modeled here — its real-pool fidelity is one of the two
  audit checks below.
- **The long-run bound rests on operational assumptions.** The δ-tax bound (§4) holds as far as oracle
  freshness does — not enforced in-contract. The §5 forced-swap skim is a real friction A5 does not fence
  from principal. Two things stay unverified, both *fidelity* checks for the audit:
  whether the deployed `yieldOracle` tracks the (un-jumpable) FUSDEV mark, and whether a real pool honours the
  swap limit as the mock does. Everything else is fuzz-tested or derives from a tested fact.
