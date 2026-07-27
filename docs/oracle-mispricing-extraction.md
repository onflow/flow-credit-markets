# FCMVault — Stale-Price Arbitrage: Unit-Test Findings

*How much value an attacker can pull out of the vault by depositing and redeeming around a stale price
oracle. This measures the numbers; it doesn't rule on whether the vault is safe overall.*

**Summary.** The attack — **stale-price arbitrage**: deposit while the vault's share price is mismarked
— a stale collateral oracle, or a yield mark diverged from where it trades — redeem once it corrects, and keep
the gap between the price you minted at and the true value the vault pays out. It's risk-free
(one atomic transaction) but tightly bounded. The tests show:

- The most it can take is that price gap — and the gap only ever touches the **carry** (the yield the
  leveraged position holds, net of its debt), **never the principal** (the collateral you deposited).
- A bigger deposit takes a bigger slice of the gap, but never more than the gap; after trading fees, it
  stops paying past a certain size.
- Repeating the cycle doesn't compound — taking the gap closes it.
- All of it shrinks to zero as the oracle stays fresh.

That ceiling is on the deposit/redeem *arbitrage*: it redistributes the **carry** (dilution of existing
holders), never the principal. (Adjacent channels — §5's forced-swap skim, a sustained negative carry — are
bounded separately and are not all principal-fenced.)

**What we're measuring.** The vault has two prices for the same share: the **booked** value `V̂`, computed
from the stale oracle when you `deposit`, and the **true value** `V*`, what `redeem` actually pays — no
oracle reprices the payout (A1). Their gap,

    Δ = V* − V̂,

is a **mispricing**: a quoted price that differs from the real one. Any attack is just **arbitrage**
against it — mint at the cheap `V̂`, exit at the true `V*`. This is **stale-price arbitrage**, the same
mechanism as mutual-fund *market-timing* (trading at a stale NAV), and its harm to existing holders is
**dilution**. The classical result then applies: *profit can't exceed the mispricing.* So the whole
question reduces to **how big `Δ` can get and what it touches** — the rest of this doc.

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
  holdings* at true/DEX prices. The exit path still *reads* oracles (fee accrual, Morpho's health check),
  but none of them sets the price paid. *(Both exits deliver the same true value: `Exit_InKindEqualsRedeem`.)*
- **(A2) The mint reads the oracle.** `deposit` credits the booked value and mints in proportion, so a
  deposit of `x` earns `≈ x/(V̂+x)` of the vault afterward (`FCMVault:615`).
- **(A3) No entry/exit fee.**
- **(A4) It's atomic — a free option.** The attacker fixes booked and true in one transaction: enter at
  booked, optionally rebalance, exit at true; take the profitable side or abort. No risk.
- **(A5) Principal cancels.** `C` is the same token count in `V̂` and `V*` — only the oracle-priced carry
  differs — so principal drops out of `Δ`.

## 2. The core bound: profit ≤ mispricing, and it never reaches principal

Three claims, each a short derivation the tests confirm.

**It's zero-sum.** Deposit and redeem only move value around: a deposit adds `x`, a redeem returns a
slice worth `P` at true prices (A1). So the attacker's profit `π = P − x` is the honest holders'
loss (exactly so frictionlessly; with real fees their loss ≥ the attacker's gain, the excess to LPs — §6) —
bounding profit bounds the harm. *(`Core_LossWithinStalenessGap` checks gain ≈ loss.)*

**Profit is capped by the gap.** Since `x` earns `x/(V̂+x)` of the vault, extraction is

    π = x · Δ/(V̂+x) < Δ,

rising toward `Δ` as `x` grows but never past it. So more capital — leverage, flash loans — takes a
bigger slice of the *same* gap; it never widens the gap. Net of trading costs it's worse still: the DEX
fee grows with `x` (real price impact only sharpens it), so the attacker's net profit peaks at some size and
then goes negative. *(`Core_LossWithinStalenessGap`: honest loss stays within `δ` of the holder's claim.
`Core_ProfitConcaveInSize`: net profit peaks at an interior size. `Core_OverMarkUnprofitable`: the
opposite direction — vault *over*-valued — neither pays nor harms holders.)*

**It never reaches principal.** `Δ` involves only the carry `G`; principal `C` cancels (A5). So the
entire attack surface is the yield the position holds, never the deposited collateral
*(`Core_LossWithinStalenessGap`: `honest_after ≥ deposit`)*.

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
- **Discount** (DEX < mark): the attacker's yield is over-booked, so they over-mint and dilute holders.

Both are fuzzed (discount to 90%, premium to +100%) in `Source_YieldDivergenceWithinGap`, which caps
honest harm at the gap. The mark only ratchets up, so the one pure-timing play — an appreciation sandwich —
is bounded by that same gap; and FUSDEV's mark can't jump anyway (`convertToAssets`, a rate-limited Morpho
Vault V2), so there's no sandwichable step, modulo the `yieldOracle` tracking it (§7).

**Manufacturing a gap doesn't pay — self-extraction loses, and a bystander can opt out.** The mark isn't
tradeable (it's `convertToAssets`, not the pool), so the only lever is pushing the DEX pool — which costs the
attacker the price impact, netting ≤ 0 on their own round-trip (`Manufacture_SelfExtractionUnprofitable`,
self-extraction bounded by `maxTvl`). Sandwiching a *bystander's* plain redeem is ordinary MEV — bounded not
by attacker-unprofitability but by the victim taking `redeemInKind`: the raw slice, worth at least the
manipulated redeem (`Exit_InKindFloorsDepressedRedeem`) and equal to a normal redeem at par
(`Exit_InKindEqualsRedeem`).

**Both at once.** A stale `Pc` and a yield divergence `d` combine to `(1+δ)(1+d) − 1` — the cross-term
is real, but there's no blow-up (`Source_CombinedWithinComposedGap`).

## 4. Repeating the cycle over a long horizon

The stale mark sticks around — a deposit doesn't refresh it — so the worry is a repeated, adversarially
timed, possibly trending sequence draining the vault over time. **Principal is unreachable for a reason
that holds on every single cycle** (A5): each `Δ` misprices only the carry, so the collateral token count
`C` is outside the surface no matter how many cycles run — there's no cross-cycle accumulator on the
principal axis for repetition to walk. What's left is the cumulative *carry* loss, and it splits cleanly.

**Price motion only depletes the pot.** The extractable pot is the *standing* carry. Each skim takes a
fraction `f·c < 1` of the current mispriced carry and settles the rest into correctly-valued collateral —
**taking the gap closes it**. A price move — jitter *or* a sustained trend — re-marks the *same* carry and
injects nothing (`G = Y·Py − D` is `Pc`-independent). With no yield accrual the series telescopes and
**saturates** at ≤ the standing carry, independent of the cycle count. *(`Repetition_OscillationDoesNotCompound`:
10 jitter cycles, cumulative ≤ ~2× a single event, last ≤ first, principal intact. That ≤2× figure is a
fixed-carry jitter artifact calibrated to N=10 — it is **not** the general long-run bound; a trend with real
yield legitimately exceeds it.)*

**Real yield is the only refill.** The carry regenerates solely from genuine accrual (`Py` rising), and
harvest sweeps any surplus above `yieldFactorMax` into collateral, out of the priced term. Telescoping over
any horizon gives the N-independent bound

    Σ πᵢ  ≤  (standing carry at t₀)  +  δ̄ · (real yield accrued),

a δ-fraction of the yield the vault genuinely earned — unbounded over infinite time only because cumulative
yield is, and never a fraction of principal. Debt interest only *shrinks* the pot (it competes with the
attacker, never amplifies). The one route below principal is a sustained negative carry (borrow rate > yield
rate) — the levered position losing money on its own, attacker-independent.

**Coverage.** The tested `Repetition` case is the saturation half only — pure jitter, fixed carry, no
accrual, no harvest firing. The regeneration half — principal holding across many interleaved cycles of
accrual + harvest + trend — is checked by `test_Repetition_YieldRegenTaxNotPrincipal` below, which verifies
principal holds and the cumulative take stays within the yield genuinely earned. The tighter δ̄-*fraction* of
that yield (the bound above) is the telescoping derivation from the per-cycle A5 identity, not a separate test.

## 5. Adjacent surfaces

Outside the deposit/redeem cycle:

- **Rebalance/harvest swaps.** When the vault swaps at a booked price it leaks the same gap to its DEX
  counterparty — ordinary swap MEV. Two things are tested: the swap mints no shares and interposing a
  `rebalance()` adds nothing to the straddle (`Core_RebalanceDoesNotAmplify` = 0), and every leg fills no
  worse than `oracle ± maxSlippageBps` (mechanism in `FCMVault.t.sol`), so the counterparty skim is bounded
  by `(maxSlippageBps + δ) · volume` — `δ_Py` on the yield legs, `δ_Pc` on the collateral leg. Unlike the
  deposit/redeem arbitrage this is a **real execution cost**: A5 does not fence it from principal and it does
  **not** saturate — it sums with price volatility (ordinary leveraged-vault drag), bounded *per event* by
  `maxSlippageBps`, throttled by the HF dead-band, killed as `δ→0`. Not a principal drain; whether a real pool
  honours the limit as the mock does is the audit's to check (§7).
- **Performance-fee crystallization — separate concern, flagged not analyzed.** `accrueFees` crystallizes
  the fee on the marked price-per-share, so a transiently-inflated mark (a stale one among others) over-mints
  permanent fee-shares. That's a fee-accounting/griefing matter rooted in the fee model and high-water mark —
  its own issue, not stale-price extraction — so it's out of scope here, noted only so it isn't missed.
- **Bugs — out of scope.** No gap behind them, so no ceiling (per the framing up top); the audit's job.
- **Why A1 matters.** If any payout path read a mark, redeem would pay the booked value instead of the
  true one and profit could exceed `Δ`. The only mark reads during a redeem are `_accrueFees` (which
  *shrinks* the redeemer's slice) and Morpho's revert-only health check — neither reprices the payout.
  The deposit/redeem swap legs are intentionally unfloored; per-user slippage is the ERC-4626 router's job.

## 6. Mitigations

How each mitigation bears on the measured extraction:

- **DEX fee** — only a partial offset. Net profit is still positive at the real 1 bp tier
  (`Control_DexFeeOnlyPartiallyOffsets` checks the sign; the magnitude is under 1 WETH at this test scale per
  `Core_ProfitConcaveInSize`, the general ceiling being `π < Δ`) and turns negative only at a much higher fee.
  The fee alone is not the defense.
- **Oracle freshness** — extraction scales with `δ` and vanishes as `δ → 0`. The long-run leak is bounded by
  the yield the vault earns (§4; the tighter δ-fraction of that yield is analytical, not separately tested),
  so the danger is not any single stale event but **persistent** `δ` over an accruing carry. A staleness keeper drives `δ → 0`; yield smearing already exists
  at the source (FUSDEV is a Morpho Vault V2, whose `convertToAssets` accrues per block under a `maxRate` cap
  and cannot jump), so the residual is the yield-oracle's fidelity/freshness to that smeared mark, not a
  missing smear.
- **Harvest / slippage limit** — harvest keeps the carry (hence `Δ`) small; the swaps' `maxSlippageBps`
  limit is the §5 surface.
- **Minimum holding period** — removes the atomic free option outright (Pyth's suggested mitigation). A
  design lever; adoption not evaluated here.

## 7. Limitations

What this is, and isn't:

- **Derivations + tests, not formal verification.** Each bound is a short closed-form
  derivation checked by tests over the reachable range (§§2–4) — fuzzed for the §2–3 gap bounds,
  deterministic scenarios for the repetition and control cases. Strong evidence, not a
  machine-checked proof.
- **Conditional on the assumptions (A1–A5).** Those are asserted as checkable facts about the code, not
  proven exhaustive. If one breaks — e.g. a payout path starts reading a mark (A1) — the bounds break with it.
- **Completeness is not proven.** Every extraction path we *identified* is bounded; we have not shown the
  list is complete (that no other path exists). The universal — "no attack vector at all" / full value
  conservation — is deferred to the audit and the broader value-conservation review.
- **Extraction only.** This bounds what an attacker can *take* via deposit/redeem/rebalance. It does not
  cover two neighbouring staleness failures that aren't extraction — over-levering off a stale `Pc` (or a
  stalled delever) into a Morpho liquidation whose penalty hits principal, and a stale/reverting feed
  bricking exits. Those are value-destruction / availability, bounded by Morpho's liquidation incentive
  rather than the mispricing `Δ`, and tracked in the register (R21–R23, R6/R7).
- **A genuine yield de-peg is credit risk, not extraction.** A FUSDEV `convertToAssets` impairment *with*
  oracle lag reduces to the discount divergence and is bounded as extraction (§3); its *own* absolute loss —
  mark and DEX falling together, no gap to arbitrage — is credit risk, out of scope, and does not preserve
  absolute principal in that direction.
- **The tests run on mocks.** The oracle is a settable value — `δ` is a test parameter, not a real Pyth
  staleness/confidence check; fuzzing is bounded to the solvent/redeemable range (past it, exits
  revert — `Core_PastCapExitReverts`); and the attacker-as-DEX-counterparty skim on the vault's own swaps
  can't be modeled here (no reserve-backed, limit-honoring counterparty mock) — flagged for audit.
- **The long-run bound rests on operational assumptions.** The δ-tax bound (§4) holds only as far as oracle
  freshness and harvest cadence do — neither enforced in-contract; the *tested* envelope is the looser "full
  earned yield + one standing-carry skim", the δ̄-fraction being analytical. And the §5 forced-swap skim is a
  real friction A5 does not fence from principal. Two things stay unverified, both *fidelity* checks for the audit:
  whether the deployed `yieldOracle` tracks the (un-jumpable) FUSDEV mark, and whether a real pool honours the
  swap limit as the mock does. Everything else is fuzz-tested or derives from a tested fact.
