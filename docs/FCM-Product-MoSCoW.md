<!-- In-repo copy of the Google Doc "FCM Product (MoSCoW breakdown)"
     https://docs.google.com/document/d/1KnS7nPHIlQeLkTBBFZhSrop2J_tHpCMCnYKFDGqUaYY
     Markdown export dated 2026-06-10. -->

# FCM Product — PRD / MoSCoW breakdown (in-repo copy)

> **⚠ ALWAYS CHECK THE ORIGINAL FOR A NEWER VERSION before relying on this copy.** This is an in-repo copy of the central product PRD/MoSCoW for quick reference. The **source of truth is the Google Doc "FCM Product (MoSCoW breakdown)"** — https://docs.google.com/document/d/1KnS7nPHIlQeLkTBBFZhSrop2J_tHpCMCnYKFDGqUaYY (a live doc; last modified 2026-06-10, when this copy was taken). Re-sync if the original has advanced. Access: see [`external-sources.md`](./external-sources.md).
>
> **Milestones:** **v0.2** (a.k.a. "v0.2 Rebuild") is the **current near-term target** (MVP — validate the product idea); **vMillions** (security + revenue) follows closely and is already accounted for in the architecture/testing harness where possible.
>
> **Where this sits:** the post-April-'26-onsight redesign basis is in [`onsight-april-2026-digest.md`](./onsight-april-2026-digest.md); current architecture in [`architecture.md`](./architecture.md). This PRD's MoSCoW **supersedes** the legacy ALP-era roadmap ([`legacy-design-digest.md`](./legacy-design-digest.md), Source 6).
>
> **Terminology (so this PRD is self-contained — deeper context in the legacy roadmap digest):**
> - **FUSDEV** — a USD-yield token/strategy (lending-backed yield, e.g. a Morpho ERC4626 vault); the yield token for the ETH/BTC→PYUSD0 strategy.
> - **ayWFLOW** — the yield token for the Flow-looping strategy (leveraged WFLOW exposure).
> - **PYUSD0** — the stablecoin debt token borrowed in the strategies.
> - **Flow Looping** — leveraged exposure via a borrow-and-buy loop to keep ~100% asset exposure.
> - **Health factor / LTV** — effective collateral ÷ effective debt vs oracle prices; LTV ≈ 80% with a ~10% buffer (≈ 70% effective).
> - **Circuit breakers (spread / volatility)** — halt swaps/harvesting when DEX-vs-oracle price diverges or volatility is high.
> - **Escape hatch** — a user can always repay their debt share to recover their collateral share.
> - **Warmup / dust** — warmup = post-unpause window blocking withdrawals; dust = sub-minimum residual balances to manage (rounding).
> - **Scheduled rebalancing** — the Cadence scheduled-transaction rebalancer poking the Solidity `rebalance()` (legacy name: "AutoBalancer").

---

# PRD: FCM

## Executive Summary

Users holding an asset are seeking higher returns than the direct yield opportunities of that asset. Using the asset as collateral to borrow a debt token can gain those higher yields, but requires permanent user interaction to keep asset exposure, maximize yield and prevent liquidation.   
We utilize flow's unique feature of scheduled transactions to automate this process, constantly adjusting the position to keep asset exposure at 100%, maximizing the potential debt to maximize yield while making sure the user doesn’t get liquidated.  
This will bring TVL and users to Flow, provide a revenue stream through fees, and demonstrate a practical application of Flow’s unique feature of scheduled transactions.

## Viability & Risks

**holding an asset are seeking higher returns than the direct yield opportunities of that asset**   
Which asset??

On flow ETH & BTC manifold yield source with 10% APY, will try to get it insured.

10% – Manifold Vault risk  
5%   – Jons Vault risk \+ Morpho risk \+ Volatility risk \+ Scheduled rebalancing risk

[https://defisaver.com/](https://defisaver.com/)  
[https://instadapp.io/](https://instadapp.io/)

## User Persona

DeFi natives  
NO Bitcoin Maximalist  
NO Cypherpunk

Wants to stay fully exposed to the asset they are holding.  
Is willing to take on additional risk to maximize their yield.

## Success Metrics

**Primary Metric: Total Value Locked (TVL)**  
	Reach $1M TVL.  
**Secondary Metric: Active User Growth**  
Onboard 1000 unique depositors.

## Yield Strategies

LTV ≈ 80%  
Our buffer ≈ 10%  
≈ 70%

APY \= Health Factor \* (Yield Token APY \- Borrow APY)

| Asset / Collateral | Debt | BorrowAPY | Yield Token | Yield Token APY | APY |
| :---- | :---- | :---- | :---- | :---- | :---- |
| ETH / BTC | PYUSD0 | 4% | FUSDEV | 10% | **5.4%** |
| PYUSD0 / ETH / BTC | Flow | 1% | ayWFLOW | 25% | **21.6%** |

## Versions

v0.2		\- MVP (validate product idea)  
vMillions 	\- security, revenue

## User Stories

## Functional Requirements

We want to make sure **all must have for vMillions are implementable**  
If Should Have or Could Have is NOT implemented in v0.2 and its Must Have for vMillions:  
A rough plan needs to be provided on how this could be implemented with a high certainty and time estimates (days, weeks, months, years)  
If it's simple enough, implementation is a possibility.

**Complexity Sizing**: we explicitly embrace and explicitly account for uncertainty and the empirical learning that more precise estimates require outsized time investment and often only marginally reduce the uncertainty (unknown unknowns remain) for cutting-edge engineering projects. We classify problems in three buckets: requiring Order(days) or Order(Weeks) or Order(months) single person time. 

| Requirement | Description | MSCW Priority | Milestone |
| :---- | :---- | :---- | :---- |
| **Constructor** |  |  |  |
| Lending position | Single MORPHO lending position created. | Must Have | v0.2 |
| **Deposit & Withdrawal** |  |  |  |
| Deposit & Withdrawal | Core functionality for users to synchronously add and remove assets to a position in the protocol. The User can fully exit the position. 99% \< 30min | Must Have | v0.2 |
| Deposit & WithdrawalCost | The user pays for necessary swaps to enter or exit the protocol. The user doesn’t pay for rebalancing the whole protocol. | Must Have | v0.2 |
| Deposit & Withdrawal | Ability for user to limit slippage on Deposit & Withdrawal (Yearn ERC4626 Router) | Must Have | v0.2 |
| EVM access  ([web3.js](http://web3.js), or similar) | Deposit & Withdrawal through Flow EVM | Must Have | v0.2 |
| Deposit & Withdrawal without rebalance | The user can withdraw funds when scheduled rebalancing stops. | Should Have Must Have | v0.2 vMillions |
| ERC-4626 conformance | The implemented functionality conforms to ERC4626 conventions. Not all functionality must be implemented. Needed for wallets, composability, etc. | Should Have Must Have | v0.2 vMillions |
| Async Deposit & Withdrawal | Enable optional scheduled large deposits & withdrawals, swap pool not enough depth. | Could Have Must Have | v0.2 vMillions |
| Deposit & Withdrawal Onchain Simulation | Ability to simulate withdrawal & deposit. | Could HaveMust Have | v0.2 vMillions |
| Escape Hatch | Emergency mechanism that allows users to claim their share of collateral and yield tokens by repaying their share of debt and shares of “outer vault”. | Could Have Should Have | v0.2 vMillions |
| **Rebalancing** |  |  |  |
| Logic | Protocol stakes all assets as collateral. Protocol invests borrowed debt into a yield token. | Must Have | v0.2 |
| Rebalancing | Function to rebalance collateral / debt “health”. \< lower\_threshold \-\> moves health to lower\_threshold\_target \> higher\_threshold \-\> moves health to higher\_threshold\_target Debt fully swapped to yield. Thresholds and targets settable during construction. | Must Have | v0.2 |
| Onchain Scheduled Rebalancing | Onchain scheduled system to call rebalance. | Must Have | v0.2 |
| Optimized thresholds, targets | Optimize the thresholds to maximize yield. | Must Have | vMillions |
| Offchain Scheduled Rebalancing | Offchain scheduled system to call rebalance. | Could Have Must Have | v0.2 vMillions |
| Rebalancing resiliance | Rebalancing must continue to work on a best effort basis even if swap pool isn’t deep | Could Have Must Have | v0.2 vMillions |
| Yield Harvesting | Automated adjustment to keep asset exposure at 100% of TVL. | Could Have Must Have | v0.2 vMillions |
| **Safety** |  |  |  |
| TVL Limit | Admin EOA adjustable limit parameter. Default 0\. If a deposit would move TVL \> limit, revert. | Must Have | v0.2 |
| Allowlist | Allow only specific EOAs to deposit. | Must Have | v0.2 |
| Timelocked emergency recovery | Simple timelocked emergency fund recovery | Must Have | v0.2 |
| Audit | The protocol must undergo a comprehensive external security audit, such as with Quantstamp. | Must Have | vMillions |
| Bug Bounty |  | Must Have | vMillions |
| **External Edge cases** |  |  |  |
| Liquidation recovery | If liquidation happens, protocol has means to continue in a best effort, instead of complete failure. | Must Have | v0.2 |
| Price impact protection | Admin configurable maximum allowed price impact on rebalancing. | Must Have | v0.2 |
| Liquidation support | Protocol must continue to normally operate even in case of lending position liquidation. | Could Have Must Have | v0.2 vMillions |
| Spread circuit breaker yield / debt | Halts swap operations if swap price diverges too far from yield vault reported price. | Could Have Must Have | v0.2 vMillions |
| Spread circuit breaker collateral / yield | Temporarily halts yield harvesting if spread between oracle and swap price is too high. | Could Have Must Have | v0.2 vMillions |
| Volatility circuit breaker collateral / yield | Temporarily halt yield harvesting if recent oracle price volatility is too high.  | Could Have Must Have | v0.2 vMillions |
| **Monitoring** |  |  |  |
| Stats | NAV (Net asset value) | Should Have Must Have | v0.2 vMillions |
| Events | state mutations emit events for traceability (external reproducibility / auditability).  | Should Have Must Have | v0.2 vMillions |
| Dashboard | Dashboard with access to all events. Alerts on:\- Liquidation log  | Should Have Must Have | v0.2 vMillions |
| Alters | Slack alters on: Liquidation (external log\!) Large single withdrawal / deposit Daily withdrawal / deposit value increased \> 100% | Could Have Must Have | v0.2 vMillions |
| **Fees** |  |  |  |
| Management Fee | Mechanisms to collect, and withdraw a flat yearly management fee. | Could Have Should Have | v0.2 vMillions |
| Performance Fee | Mechanisms to collect, and withdraw a yearly performance fee. | Could Have Should Have | v0.2 vMillions |

## Non-Functional Requirements

|  |  |  |  |
| :---- | :---- | :---- | :---- |
| High-assurance documentation wrt attacks  | What can go wrong, what do we do if it goes wrong (scrappy but complete draft). • rounding as attack vector or failure source • Donation • Reentrency Investigate and identify mitigations. Make current design extends to future mitigations | Must Have | v0.2 |
| Investigation into economic attacks e.g. Sandwiching | • Liquidation recovery• Rebalancing Cost (as drain vector) • Sandwiching• Flash Loan Price Manipulation• Dos attack by triggering circuit breaker | Must Have | vMillions |
| Dust strategy | Exhaustive list of managing all places where rounding errors occur and how they must be managed | Must Have Must Have | v0.2 vMillions |
| Clean code | clean, auditable and minimal system | Should Have Must Have | v0.2 vMillions |
| Unit tests | Individual components need to be properly tested | Should Have Must Have | v0.2 vMillions |
| Integration tests | Tests to fully test the user flow | Should Have Must Have | v0.2 vMillions |

## External Dependencies

- [FlowSwap](https://flowswap.io/) (dex)  
  - PYUSD0 / FUSDEV  
  - Deep liquidity  
- MORPHO Blue (Needs to still be deployed)  
  - Collateral? / PYUSD0  
  - Deep liquidity  
- FUSDEV (yield source)  
  - Asset is PYUSD0  
- Frontend

vMillions:

- Reliable Oracles in $  
  - Collateral  
  - PYUSD0

## Future

- ERC7540  
- Resilience to single Price Source Failures  
- Dynamic rebalancing schedule  
- Dynamic rebalancing thresholds & targets  
- Optimized Swap routing  
- Cross Chain deposits & withdrawals  
- Full ERC-4626 implementation  
- FVM access  
- Rewards farming  
- Disable liquidations via custom oracle?