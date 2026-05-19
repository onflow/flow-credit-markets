# Tasks

[PRD](https://docs.google.com/document/d/1KnS7nPHIlQeLkTBBFZhSrop2J_tHpCMCnYKFDGqUaYY)

## Overview

### v0.2 Build

| Task                                           | Owner     | Status  | Complexity              |
| :--------------------------------------------- | :-------- | :------ | :---------------------- |
| Deposit function                               |           | TODO    | **weeks**               |
| Redeem function                                |           | TODO    | Included in deposit     |
| Deposit & Redeem slippage protection           | Patrick   | TODO    | days                    |
| Rebalancing                                    |           | TODO    | **weeks**               |
| Onchain Scheduled Rebalancing                  | Jordan R. | TODO    | **weeks**               |
| TVL Limit                                      | Tim       | Ongoing | days                    |
| Allowlist                                      | Peter     | Ongoing | days                    |
| Minimal testing                                |           | TODO    | days                    |
| Timelocked emergency recovery                  |           | TODO    | days                    |
| Happy path integration test                    |           | TODO    | days                    |
| Simple monitoring                              |           | TODO    | days                    |
| Rough High-assurance documentation wrt attacks |           | TODO    | **weeks**               |
| Rough Investigation into economic attacks      |           | TODO    | included in wrt attacks |
| AI pentest tooling                             |           | TODO    | days                    |

### Implementation Plans vMillions

We want to make sure all must have for vMillions are implementable.
A rough plan needs to be provided on how this could be implemented with a high certainty and time **estimates** (days, weeks, months).
If its simple enough, implementation is a possibility.

| Task                                          | Owner | Status |
| :-------------------------------------------- | :---- | :----- |
| Mint & Withdraw                               |       | TODO   |
| 4 preview implementations                     |       | TODO   |
| Async Deposit & Withdrawal                    |       | TODO   |
| Escape Hatch                                  |       | TODO   |
| Optimized thresholds & targets                |       | TODO   |
| Offchain Scheduled Rebalancing                |       | TODO   |
| Rebalancing resiliance                        |       | TODO   |
| Yield Harvesting                              |       | TODO   |
| Audit                                         |       | TODO   |
| Bug Bounty                                    |       | TODO   |
| Liquidation support                           |       | TODO   |
| Oracle circuit breaker                        |       | TODO   |
| Monitoring (Stats, Events, Dashboard, Alerts) |       | TODO   |
| Fees (Management, Performance)                |       | TODO   |
| Tests (Unit, Integration)                     |       | TODO   |
| High-assurance documentation wrt attacks      |       | TODO   |
| Investigation into economic attacks           |       | TODO   |
| Investigation into economic attacks           |       | TODO   |

## Details

### Deposit function

ERC4626-style `deposit`. User pays for any swaps required to enter the position; the user does **not** pay for protocol-wide rebalancing.

### Redeem function

ERC4626-style `redeem`. User can fully exit. User pays for any swaps required to exit. Must continue to work even when scheduled rebalancing is stopped.

### Deposit & Redeem slippage protection

User-facing slippage limits on both deposit and redeem flows.
Can be wrapped via the Yearn ERC4626 Router (`Yearn-ERC4626-Router`).

### Rebalancing

`rebalance()` function that adjusts collateral / debt "health":

- `health < lower_threshold` → moves health to `lower_threshold_target`.
- `health > higher_threshold` → moves health to `higher_threshold_target`.
- Borrowed debt is fully swapped to the yield token.
- Thresholds and targets settable at construction.

- **Liquidation recovery** — if the underlying Morpho position is liquidated, `rebalance()` continues on a best-effort basis instead of failing outright.
- **Price impact protection** — maximum allowed price impact when rebalancing swaps execute.

### Onchain Scheduled Rebalancing

On-chain scheduler that calls `rebalance()` automatically via Flow scheduled transactions.

### TVL Limit

Admin-EOA-adjustable TVL cap. Default `0`. Any deposit that would push total TVL above the limit reverts.

### Allowlist

Restrict deposits to a list of approved EOAs. Admin-managed.

### Minimal testing

Enough coverage that v0.2 can be demoed and the happy path is exercised end-to-end: deploy → deposit → rebalance → redeem.

### Timelocked emergency recovery

Simple timelock path that allows admin recovery of funds in case everything else fails.

### Rough High-assurance documentation wrt attacks

Scrappy but complete first draft of "what can go wrong, what do we do if it goes wrong". Must cover at minimum:

- Rounding as an attack vector / failure source — and an initial **dust strategy** listing where rounding errors occur and how they are managed.
- Donation attacks.
- Reentrancy.

Identify mitigations and ensure the current design is compatible with adding more later. Hardening pass lives in the Implementation Plans equivalent.

### Rough Investigation into economic attacks

First-pass economic threat model: enumerate the relevant vectors (sandwiching, flash-loan price manipulation, rebalancing cost as a drain vector, DoS via circuit-breaker triggering, liquidation games) and note current exposure. The full investigation is the vMillions item in the plan section.

## Implementation Plan Details

### Mint & Withdraw

ERC-4626 `mint` and `withdraw` entry points

### 4 preview implementations

`previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem` — on-chain simulation of deposit/withdraw outcomes. Required for ERC-4626 conformance and for integrators that need to quote before transacting.

### Async Deposit & Withdrawal

Scheduled flow for large deposits/withdrawals when swap-pool depth isn't sufficient to execute synchronously.

### Escape Hatch

Emergency mechanism allowing users to claim their share of collateral and yield tokens by repaying their share of debt and shares of the outer vault. Usable without executing swaps.

### Optimized thresholds & targets

Methodology and tooling to optimize rebalance thresholds/targets to maximize yield.

### Offchain Scheduled Rebalancing

Off-chain scheduler that calls `rebalance()` as a redundancy for on-chain scheduling.

### Rebalancing resiliance

Rebalancing continues to work on a best-effort basis even when swap-pool depth is shallow (graceful degradation, partial rebalances, retry logic).

### Yield Harvesting

Automated adjustment to keep asset exposure at 100% of TVL (harvest yield token gains back into the position).

### Audit

Comprehensive external security audit (e.g. Quantstamp).

### Bug Bounty

Standing bug bounty program (vendor, scope, payout tiers).

### Liquidation support

Beyond v0.2's "liquidation recovery", the protocol continues to operate **normally** through a liquidation event of its Morpho position.

### Oracle circuit breaker

Consolidates the three oracle-related safety mechanisms:

- **Spread circuit breaker (yield/debt)** — halt swap operations if swap price diverges too far from the yield vault's reported price.
- **Spread circuit breaker (collateral/yield)** — temporarily halt yield harvesting if the spread between oracle and swap price is too high.
- **Volatility circuit breaker (collateral/yield)** — temporarily halt yield harvesting if recent oracle price volatility is too high.

### Monitoring (Stats, Events, Dashboard, Alerts)

- **Stats** — e.g. NAV (Net Asset Value) reporting.
- **Events** — state mutations emit events for external traceability / auditability.
- **Dashboard** — visualization over events, with liquidation log alerts.
- **Alerts** — Slack alerts on liquidation, large single withdrawal/deposit, daily withdrawal/deposit value increased >100%.

### Fees (Management, Performance)

- **Management Fee** — collect and withdraw a flat yearly management fee.
- **Performance Fee** — collect and withdraw a yearly performance fee.

### Tests (Unit, Integration)

- **Unit tests** — individual components properly tested.
- **Integration tests** — full user-flow tests.

### High-assurance documentation wrt attacks

Hardened version of the v0.2 doc: complete, reviewed write-up of attack vectors (rounding, donation, reentrancy, exhaustive dust strategy) with confirmed mitigations and references into the code.

### Investigation into economic attacks

Full economic threat model covering liquidation recovery, rebalancing cost as a drain vector, sandwiching, flash-loan price manipulation, DoS via circuit-breaker triggering — with mitigations and exposure analysis.

