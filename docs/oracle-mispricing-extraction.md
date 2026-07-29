# FCMVault — Stale-Price Arbitrage: Unit-Test Findings

*Unit-test bounds on one attack: how much an attacker can pull out by depositing and redeeming around a
stale or diverged price. This is the **executable-evidence slice** for that single surface — it quantifies
and regression-guards it. It is **not** the general value-conservation question (whether any ordering of
legitimate operations can extract value, across all surfaces); that is a separate, broader effort, and every
whole-surface claim here defers to it. Liquidation, a yield de-peg, and sustained negative carry are out of scope — those are the leveraged
position losing value (solvency / credit), not a mispriced share being arbitraged.*

**Summary.** **This can't drain the vault** — worst case, an attacker skims a small, self-limiting slice of
the vault's recent *yield* during a stale-price window (one bounded edge can nick principal by a few percent),
and it vanishes once the price feed is kept fresh. Why: a `deposit` mints shares against the **oracle-priced
NAV**, while a `redeem` returns a **pro-rata slice of the real tokens** at the market price — so deposited
**principal (a token count) is essentially untouchable**, and the only term an oracle prices, and therefore
the only thing a stale-price attacker can skim, is the **carry** (the levered yield net of debt). The attack
is then **stale-price arbitrage**: deposit while that carry is mismarked (a stale collateral oracle, or a
yield mark diverged from where it trades), redeem once it corrects, keep the gap. Risk-free (one atomic
transaction) but tightly bounded. The tests show:

- The most it can take is that price gap — and for a *uniform* mispricing the gap only ever touches the
  **carry** (the yield the leveraged position holds, net of its debt), **not the principal** (the collateral
  you deposited). The lone exception — a deposit levered unlike the book during a pool dislocation — does
  reach principal, but is bounded by the divergence gap and can't be manufactured profitably (§3).
- Only *one* direction pays — buying in at a mark that's too **low**. Minting at one that's too high just
  makes the attacker overpay, and the sell side is dead (a redeem pays the true value regardless of the mark),
  so the whole surface is the deposit.
- A bigger deposit takes a bigger slice of the gap, but never more than the gap; after trading fees, it
  stops paying past a certain size.
- Repeating the cycle doesn't compound — the pot is finite and price motion can't refill it.
- All of it shrinks to zero as the oracle stays fresh.

Each finding is a short argument checked against fuzz tests over the reachable range — evidence, not a formal
proof (§7).

**What we're measuring.** The vault has two prices for the same share: the **booked** value `V̂`, computed
from the stale oracle when you `deposit`, and the **true value** `V*`, what `redeem` actually pays — no
oracle reprices the payout (A1). Their gap,

    Δ = V* − V̂,

is a **mispricing**: a quoted price that differs from the real one. The attack this doc measures is
**arbitrage** against it — mint at the cheap `V̂`, exit at the true `V*` — and its harm to holders is
**dilution**. Profit can't exceed the mispricing (the tests below bound how much), so the question reduces to
**how big `Δ` can get and what it touches**.

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

**Profit is capped by the gap.** A deposit only ever earns a *fraction* of the vault, so it skims a fraction
of the gap — never more:

    π < Δ.

More capital — leverage, flash loans — takes a bigger slice of the *same* gap; it never widens it. Net of
fees it's worse still: the DEX fee grows with size, so a large attack peaks then turns net-negative. *(`Core_LossWithinStalenessGap`: honest loss stays within `δ` of the holder's claim.
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
- **Discount** (DEX < mark): the attacker's yield is over-booked, so they over-mint and dilute holders. One
  edge case here can reach **principal**: a deposit *levered unlike the book*, whose over-mint isn't
  carry-fenced (A5 holds only for a uniform misprice). It's bounded by the gap, un-manufacturable, and
  non-compounding (each event needs a fresh setup), and it takes *both* a composition skew and a wide discount
  — frequent rebalancing keeps the skew small, so in practice it's a small, conditional edge (a few percent of
  NAV only at an extreme ~90% divergence). It's really a facet of the yield-oracle-fidelity question (§7 / R12),
  not a standing drain *(`Source_DifferentlyLeveredDiscountReachesPrincipal`; R24)*.

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

A stale mark sticks around — a deposit doesn't refresh it — so the worry is a repeated, possibly trending
sequence draining the vault over time. Two things bound it. **Principal is unreachable on every cycle** (A5):
each `Δ` misprices only the carry, so the collateral token count `C` never enters the surface, however many
cycles run.

**And the carry pot doesn't compound.** What's extractable is the *standing* carry — a finite pot that
price motion and rebalancing don't refill — so repeating the straddle can't stack: the gap persists but stops
being extractable after the first cycle (a fresh deposit can no longer mint in below true value). It refills
*only* from genuine yield accrual, so over the long run the drain is at most a small tax on the yield the
vault actually earned — never principal. *(`Repetition_CollateralOscillationDoesNotCompound`,
`Repetition_YieldOscillationDoesNotCompound`: jittered cycles, no per-round acceleration, principal intact.
`Repetition_YieldRegenTaxNotPrincipal`: 200 rounds with real accrual, loss ≤ earned yield, realized principal
floor held.)* A genuine `convertToAssets` de-peg is a credit loss the attacker front-runs, not extraction (§7).

## 5. Adjacent surfaces

This bound covers only the deposit/redeem cycle. The rest is noted so the result isn't over-read; the
untested channels belong to the value-conservation review and the audit (§7):

- **Rebalance/harvest swaps** leak the same gap to the DEX counterparty (ordinary swap MEV), but a
  `rebalance()` interposed in the straddle adds nothing (`Core_RebalanceDoesNotAmplify` = 0), and each leg
  fills no worse than `oracle ± maxSlippageBps` (`FCMVault.t.sol`). A real execution cost, not a principal drain.
- **Performance-fee crystallization** — a transiently-inflated mark over-mints fee-shares; a fee-model matter,
  not stale-price extraction. Flagged, out of scope.
- **Bugs** — no gap behind them, so no ceiling; the audit's.
- **Why A1 matters** — if any payout path read a mark, redeem would pay the booked value instead of the true
  one and profit could exceed `Δ`. The deposit/redeem legs are intentionally unfloored (per-user slippage is
  the ERC-4626 router's job).

## 6. Next steps

The practical control is a **staleness keeper** driving `δ → 0` — the leak scales with `δ`, and the DEX fee
is only a partial offset, not the defense (`Control_DexFeeOnlyPartiallyOffsets`). Harvest would keep the
carry small but never fires in these tests (§4).

## 7. Limitations

What this is, and isn't:

- **Evidence on identified paths, not formal verification.** Each bound is a short argument — closed-form
  algebra for §2–3, a conservation/saturation argument for §4 — checked by tests over the reachable range
  (fuzzed for §2–3, deterministic for repetition/controls). Strong evidence, not a machine-checked proof, and
  not a claim the identified list is complete: the universal question — full value conservation across all
  surfaces — belongs to the separate value-conservation review, not this deliverable.
- **Conditional on the assumptions (A1–A5).** Those are asserted as checkable facts about the code, not
  proven exhaustive. If one breaks — e.g. a payout path starts reading a mark (A1) — the bounds break with it.
- **We bound *extraction*, not every way the vault can lose value.** This doc covers what an attacker can
  *take* through the deposit/redeem/rebalance mispricing. Separately, a leveraged vault carries ordinary risks
  that can cost principal but aren't this arb — a stale-`Pc` over-lever (or stalled delever) triggering a
  Morpho liquidation (penalty bounded by the LIF), a stale or reverting feed bricking exits, and a genuine
  FUSDEV de-peg (credit risk). Those are losses the vault absorbs, not value an attacker pulls out through the
  gap, and are tracked separately (R21–R23, R6/R7).
- **Mocks and operational assumptions.** `δ` is a settable test parameter, not a real Pyth staleness check,
  and the long-run bound (§4) holds only as far as oracle freshness does — not enforced in-contract. The §5
  forced-swap skim is a real friction A5 does not fence from principal. Two *fidelity* checks stay for the
  audit: whether the deployed `yieldOracle` tracks the FUSDEV mark, and whether a real pool honours the swap
  limit as the mock does. Everything else is fuzz-tested or derives from a tested fact.
