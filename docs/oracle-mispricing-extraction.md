# FCMVault — stale-price arbitrage: test notes

These are notes on one question: how much can someone extract by depositing and redeeming
around a stale or diverged price? We wrote a test suite to put numbers on it and to guard
against regressions.

This is not a proof, and it is not the full value-conservation review — it covers the
deposit/redeem cycle only, and it leans on the assumptions listed at the end. Liquidation, a
yield de-peg, and sustained negative carry are out of scope: those are the leveraged position
losing value, not a mispriced share being arbitraged.

## Summary

The attack can't drain the vault. Worst case, someone skims a small slice of the vault's recent
yield during a window where the price is stale, and the opportunity closes as soon as the feed
is refreshed. One narrow case can reach principal by a few percent, but only under conditions
that can't be set up profitably (§3).

The reason is in how the two sides price:

- A `deposit` mints shares against the oracle-priced NAV.
- A `redeem` returns a pro-rata slice of the real tokens at the market price — no oracle
  reprices the payout.

So deposited principal is a token count that nothing reprices, and the only thing an oracle can
misprice — and therefore the only thing a timing attacker can skim — is the carry: the levered
yield, net of debt.

What the tests show:

- The most anyone can take is the size of the price gap, and when the gap hits every share
  equally it comes out of the carry, not principal.
- Only one direction pays: buying in at a mark that's too low. Buying in too high just overpays,
  and the sell side pays true value regardless of the mark.
- A bigger deposit takes a bigger share of the same gap but never more than the gap, and after
  fees it stops paying past a certain size.
- Repeating the cycle doesn't compound — the pot is finite and price motion doesn't refill it.
- Everything shrinks to zero as the oracle is kept fresh, so the defense is a keeper that keeps
  the feed fresh.

## 1. Model

Vault value per share, in collateral units:

    V = C + (Y·Py − D) / Pc

- `C` — the collateral deposited (principal). A token count, so no oracle reprices it.
- `Y·Py − D` — the carry: the yield holding (`Y`, marked at `Py`) minus the debt `D`. This is
  the only part of `V` an oracle moves.
- `Pc` — the collateral price feed. A Pyth pull oracle: it can be stale between updates, and an
  attacker can time the update inside their own transaction.
- `Py` — the yield mark: FUSDEV's own `convertToAssets` rate, what a deposit is priced against.
  This is *not* the DEX price — the vault trades yield on the AMM at an independent rate, so the
  mark and the DEX rate can diverge.

The gap the attack lives on is the difference between the value a deposit is booked at (stale
marks) and the value a redeem actually pays (fresh price, DEX rate). Everything below is about
how big that gap can get and what it touches.

## 2. How much, and does it reach principal

Three things, each checked by tests rather than proven:

- **It's zero-sum.** Deposit and redeem only move value around, so whatever the attacker gains
  the honest holders lose — bounding the gain bounds the harm. (`Core_LossWithinStalenessGap`
  checks that gain ≈ loss.)
- **Profit is capped by the gap.** A deposit only ever earns a fraction of the vault, so it
  skims a fraction of the gap, never more. More capital takes a bigger slice of the *same* gap;
  it doesn't widen it, and once fees are counted a large attack peaks and then loses money.
  (`Core_ProfitConcaveInSize`, `Core_OverMarkUnprofitable`.)
- **It almost never reaches principal.** When the misprice hits every share equally, the
  collateral token count cancels between the booked and the realized value, so only the carry is
  exposed. The one exception is the differently-levered discount case in §3.
  (`Core_LossWithinStalenessGap` also checks the holder's claim stays at or above their deposit.)

## 3. Where the gap comes from

Two sources, plus what happens if you try to create one.

**Stale collateral feed — small.** The vault is WETH-in / WETH-out, and both it and Morpho read
the same feed, so a price move barely shifts value-per-share. A balanced book (no carry) leaks
only dust (`Core_BalancedNoExtraction`); otherwise a stale mark misprices only the carry's
conversion into collateral units — bounded by the staleness, never principal. Crash the price
far enough and the corrected position is underwater, at which point exits revert and a bigger
move gets nothing (`Core_PastCapExitReverts`).

**Yield mark vs. DEX price — the real surface.** A deposit books yield at `convertToAssets`, but
the vault trades it on the AMM; any gap between the two is live, works both ways, and is bounded
by the gap:

- **Premium** (DEX above mark): honest yield is under-booked, so the attacker mints cheap and
  takes the un-booked gain.
- **Discount** (DEX below mark): the attacker's yield is over-booked, so they over-mint. One case
  here can reach principal — a deposit levered differently from the rest of the book, where the
  over-mint isn't fenced to the carry. It's bounded by the gap, needs *both* a composition skew
  and a wide discount, and doesn't compound (each attempt needs a fresh setup). Frequent
  rebalancing keeps the skew small, so in practice it's a small conditional edge — a few percent
  of NAV only at an extreme (~90%) divergence.

Both directions are fuzzed in `Source_YieldDivergenceWithinGap`; the principal-reaching edge is
`Source_DifferentlyLeveredDiscountReachesPrincipal`.

**Creating a gap doesn't pay.** The mark isn't tradeable (it's `convertToAssets`, not the pool),
so the only lever is pushing the DEX pool — which costs the attacker the price impact and nets
≤ 0 on the round trip (`Manufacture_SelfExtractionUnprofitable`). A holder facing a pushed pool
can sidestep it with `redeemInKind`, taking the raw slice instead of selling into the bad price
(`Exit_InKindFloorsDepressedRedeem`).

**Both at once** compound roughly additively, with no blow-up (`Source_CombinedWithinComposedGap`).

## 4. Repeating it

A stale mark doesn't refresh itself, so the concern is a repeated or trending sequence draining
the vault over time. Two things bound it. Principal is out of reach on every cycle — each gap
misprices only the carry. And the carry itself is a finite pot that price motion and rebalancing
don't refill, so repeating the straddle doesn't stack: after the first cycle a fresh deposit can
no longer mint in below true value. The pot refills only from real yield accrual, so over the
long run the worst case is a small tax on yield the vault genuinely earned, never principal.
(`Repetition_CollateralOscillationDoesNotCompound`,
`Repetition_YieldOscillationDoesNotCompound`, and `Repetition_YieldRegenTaxNotPrincipal`, which
runs 200 rounds with real accrual.)

## 5. Related surfaces (not covered here)

Noted so the result isn't over-read; these belong to the broader value-conservation review and
the audit:

- **Rebalance/harvest swaps** leak the same gap to the DEX counterparty (ordinary swap MEV). An
  interposed `rebalance()` adds nothing to the deposit/redeem attack
  (`Core_RebalanceDoesNotAmplify`), and each leg fills within `oracle ± maxSlippageBps` (covered
  in `FCMVault.t.sol`). A real execution cost, not a principal drain.
- **Performance-fee crystallization** — a transiently inflated mark over-mints fee shares. A
  fee-model question, not this attack.
- **Bugs** — nothing bounds a bug; that's the audit's job.

## 6. What this does and doesn't establish

- **Tests over the reachable range, not a proof.** Each bound is a short argument backed by fuzz
  tests (§2–3) or deterministic scenarios (§4). It's strong evidence on the paths we identified,
  not a machine-checked proof and not a claim the list is complete — full value conservation
  across all surfaces is a separate effort.
- **Conditional on the assumptions below.** They're stated as checkable facts about the code, not
  proven exhaustive. If one breaks, the bounds break with it.
- **Bounds extraction, not every way the vault can lose value.** A leveraged vault carries
  ordinary risks that can cost principal but aren't this attack — a stale-feed over-lever
  triggering a Morpho liquidation, a stale or reverting feed bricking exits, a genuine FUSDEV
  de-peg. Those are losses the vault absorbs, tracked separately.
- **Mock limits.** The staleness is a settable test parameter, not a real Pyth
  staleness/confidence check, and the long-run bound holds only as far as oracle freshness does
  (not enforced on-chain). Two fidelity checks are left for the audit: whether the deployed yield
  oracle tracks the FUSDEV mark, and whether a real pool honours the swap limit the way the mock
  does.

Assumptions the tests rely on:

1. **No payout path reads the mark.** `redeem`/`redeemInKind` hand back a pro-rata slice of the
   actual holdings at the DEX price. The exit still reads oracles (fee accrual, Morpho's health
   check), but none of them sets the price paid. (`Exit_RedeemMarkIndependent`,
   `Exit_InKindEqualsRedeem`.)
2. **The deposit reads the oracle** and mints in proportion.
3. **No entry/exit fee.**
4. **It's atomic** — the attacker fixes booked and true value in one transaction and takes the
   profitable side or aborts.
5. **Principal only cancels when the misprice is uniform** (hits every share equally). A deposit
   levered differently from the book breaks that — the §3 edge case.
