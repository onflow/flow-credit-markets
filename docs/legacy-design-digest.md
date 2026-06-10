# Legacy FCM design — staleness-aware digest (ALP-era, ice-boxed)

> **Why this doc exists.** FCM has design history predating the current architecture. This is a self-contained digest of that history so a reader needs only this repository — not the original external sources — to understand what came before, what still applies, and what is superseded. It is **reference/product-context**, not a governing spec.
>
> **OVERARCHING DISCLAIMER.** Everything below derives from the **prior, now ICE-BOXED, ALP-centric FCM design**, which was planned as a **full-Cadence implementation** centered on a bespoke in-house **Automated Lending Protocol (ALP)**, a medium-of-exchange stablecoin **MOET** (a.k.a. "Moet"), and **Flow Yield Vaults (FYV)**. That design was paused mainly due to **implementation complexity** (largely the in-house ALP). **Ice-boxed means paused, not abandoned** — a far-future ALP-centric build remains under potential consideration, but is not active work.
>
> **What changed vs. what endured.** The bespoke **lending engine** was replaced by the **external Morpho Blue** protocol; the current build is an **ERC4626 outer vault in Solidity on Flow EVM** that supplies to Morpho, borrows, and reinvests into an **inner vault**, with **Pyth** pricing, **FlowSwap** swaps, and a **Cadence scheduled-transaction** rebalancer. Crucially, **the automated-rebalancing premise was retained across the pivot** — automation didn't go away, it is now applied to Morpho positions rather than a homegrown lending protocol. See [`architecture.md`](./architecture.md) and [`vault-rebalancer.md`](./vault-rebalancer.md) for the current design.
>
> **Assess staleness case by case:** the *product premises* and many *safety principles* endure; the *implementations* (Cadence contracts, the ALP, the MOET stablecoin, BandOracle) are superseded.

## Enduring product premises (survive the ALP → Morpho pivot)
- **Invert DeFi's capital-efficiency-vs-liquidation-risk tradeoff** via continuous **automated rebalancing** instead of reactive liquidation → **higher sustainable LTV + sharply reduced liquidation risk**. This is FCM's north star and is intact.
- **Principal protection:** on collateral downturn, **sell the investment/yield asset, not the core collateral**, to pay down debt; on appreciation, **reinvest excess equity to compound**.
- **Automation removes off-chain keepers / third-party providers** (via Flow scheduled transactions), lowering cost and counterparty risk.
- **Safety over liveness** for price/health decisions; fail-closed.

## Uniformly superseded on implementation
- **ALP** (bespoke in-house Cadence lending protocol) → **Morpho Blue** (external, on EVM).
- **MOET / "Moet"** (protocol-native stablecoin) → not in the current design; the vault borrows a debt token via Morpho.
- **FYV ("Flow Yield Vaults")** branding → the current ERC4626 outer/inner-vault structure.
- **Full-Cadence** business logic → **Solidity on Flow EVM** (Cadence retained only for the scheduled-transaction rebalancer).
- **BandOracle** → **Pyth**.

---

## Source 1 — Price Oracle  (principles STILL HIGHLY RELEVANT)
- **Origin:** legacy repo `onflow/flow-credit-markets-old`, `docs/price-oracle.md` (Draft; author Jordan Ribbink, `jribbink`).
- **Endures (re-derive for Pyth/EVM):** prices must carry a **source-attested publish time**, be rejected as **stale** against an explicit freshness bound, and **never** be silently replaced with defaults/zeros or relabeled with block time; **"no price ⇒ hard stop"** for every price-dependent decision; **manipulation defenses** = independent sources + a **source-disagreement (spread) check** + a **volatility circuit breaker**, with a single correlated source (e.g. a DEX/TWAP) as an interim sanity-gate; **fail-closed** (justified by Terra-LUNA-era insolvencies vs. protocols that paused). Pyth's confidence interval can feed the sanity layer.
- **Superseded:** the Cadence `PriceOracle`/`PriceReading` interface and capability topology; Cadence panic / no-try-catch reasoning (Solidity has reverts); hosting the breaker as a scheduled-transaction handler; consumers named ALP/FYV; `Type<USD>()` unit-of-account typing.

## Source 2 — Numeraire  (principle STILL HIGHLY RELEVANT)
- **Origin:** legacy repo, `cadence/contracts/Numeraire.md` (open PR "Spec: Numeraire", author Tim Barry, `tim-barry`).
- **Endures:** one **fixed, consistent unit of account** for all NAV/collateral/debt/health math, **set at init and never changed**, and **always used when querying oracles**; **USD** as the base unit (Pyth is USD-denominated too); the **unit of account is decoupled from any tradable token**; an **adapter maps the unit/asset to the oracle's feed id** (same problem with Pyth price IDs). ERC4626's "underlying asset" denomination is the modern embodiment.
- **Superseded:** the Cadence `FlowALP.PoolConfig`/`Type` field, `OffchainCurrency.cdc` non-constructible vault, the Type→symbol dictionary, **MOET as the future numeraire**, **BandOracle**.
- **Note:** the doc is silent on precision/rounding; the current design still needs explicit **round-against-the-user** discipline (not attributable to this doc).

## Source 3 — Health Trigger Manager (HTM)  (closest to the current rebalancer)
- **Origin:** legacy repo, `docs/health-trigger-manager.md` (open PR "spec: Health Triger Manager", author Janez Podhostnik, `janezpodhostnik` — no longer actively resourced to the project).
- **Endures (maps almost 1:1 to the current rebalancer):** the **health-band → trigger → action loop** (`Hmin`/`Hmax` ↔ in-band thresholds); a **self-rescheduling heartbeat** scheduled transaction driving an **idempotent, publicly-callable process pass** (↔ the permissionless `rebalance()`); **callbacks in isolated transactions** (panic isolation); **liveness/observability events** + **admin restart** on fund-exhaustion/stop; **idempotent re-runs**; liquidation-avoidance as the core value.
- **Superseded:** health sourced from the bespoke `FlowALP.Pool` (→ Morpho on EVM instead); the full-Cadence position model; FYV terminology; no Pyth / no EVM cross-VM bridging (which the current design requires).
- **Uncertain:** whether the heartbeat→process→callback latency floor + operational-vault funding model carry into the EVM-based rebalancer; whether the generic trigger-registry abstraction survived.

## Source 4 — ALP State Mutation Pipeline  (HISTORICAL ONLY — describes removed code)
- **Origin:** legacy repo, `docs/flow-alp-architecture.md` (open PR "ALP State Mutation Pipeline", author Jordan Schalm, `jordanschalm`).
- **Describes the REMOVED FlowALP engine:** a 4-phase state-mutation pipeline — `Pool.Orchestrator` → `applyTimeBasedMutations()` (roll interest indices/utilization) → an operation-specific **Mutator** (Cadence pre/body/post) → a universal `invariantsHold()` post-condition; layered entitlement access; `PoolState` fully `access(self)`.
- **Worth remembering:** this is the concrete record of **why ALP = complexity** (hand-rolled interest accounting, per-token invariants, health/caps, liquidation — all in-house) → the complexity that **motivated the pivot to Morpho**. Reusable Cadence patterns if ever building in-house Cadence again: view-only `pre`-block validation, **Mutator/applier separation** with compiler-enforced `access(self)` encapsulation, uniform post-condition invariants, "advance time-dependent state before validating."
- **Superseded:** the entire FlowALP protocol/APIs/invariants — removed, not live.

## Source 5 — "(LIVE DOC) FCM Primer"  (product vision; architecture is ALP/MOET-era)
- **Origin:** an internal Google Doc, "(LIVE DOC) FCM Primer" (owner asher.farooq@flowfoundation.org; created 2025-10-07; modified 2026-06-05). An academic-style whitepaper ("Overview and Quantitative Analysis"); its prose self-dates to ~Feb 2026.
- **Endures (product vision + value prop):** the core thesis (invert capital-efficiency-vs-liquidation-risk via active rebalancing), higher LTV via automation, and the principal-protection mechanic (sell investment not collateral; compound on appreciation).
- **Quantitative claims — treat as UNVERIFIED and model-specific:** the doc itself flags this section "WORK IN PROGRESS / UNVERIFIED (possibly incorrect) RESULTS" with an internal figure discrepancy. Reported figures (derived under the ALP/MOET model, Monte-Carlo + Uniswap-V3 tick math + 5yr BTC stress paths, Aave as benchmark): ~99.8% cost savings vs. liquidation; ~100% liquidation prevention / principal survival (vs. Aave ~44% agents liquidated); up to ~17.5:1 capital efficiency under 50% drawdown; ~4×–9× liquidity efficiency vs. industry.
- **Superseded architecture:** §3 is entirely ALP / MOET / FYV (tri-level health policy, micro-liquidations, MOET peg backstops, LayerZero-OFT yield tokens). **Morpho appears only as a competitor**; there is no mention of ERC4626/Solidity/Pyth/FlowSwap.
- **Status note (clarified 2026-06-10):** despite the "(LIVE DOC)" label and a recent edit, the primer **lagged the engineering pivot** — it still markets the ice-boxed ALP/MOET/FYV design. The enduring premises are valid; the architecture sections are historical. (See `DR-001` in [`../specs/DECISIONS.md`](../specs/DECISIONS.md).)

---

## How to use this digest (staleness, case by case)
- **Product premises** (the "endures" lists, Source 5 vision) are safe to cite for the business case — but **quantitative claims are unverified and ALP-model-specific**, so caveat them.
- **Oracle / numeraire / health-trigger principles** (Sources 1–3) are safe to cite as *requirements/patterns*, but their **implementations must be re-derived for Solidity/EVM + Pyth + Morpho** — never cite the Cadence specifics as current.
- **ALP mechanics** (Source 4, Source 5 §3.1) are **historical only** — cite solely to explain why the design was simplified.
- When drawing from any of these in a spec, attach a concise disclaimer: *"From the ice-boxed ALP-era design (full-Cadence); [principle X] endures; [implementation Y] is superseded by [current Morpho/Solidity/Pyth equivalent]."*

## Provenance & how to re-check the originals
The legacy specs live in the **external** public repo `onflow/flow-credit-markets-old` (price-oracle on `main`; Numeraire, Health-Trigger-Manager, and ALP-architecture on the open PRs noted above). The Primer is an internal Google Doc owned by asher.farooq@flowfoundation.org. These are **external to this repository and may move or change** — this digest inlines their substance so it stands alone. When consulting an original later, **check the PR's status and read the newest version from the PR branch (or `main` if merged).** As of 2026-06-10 the three PRs were all open.

For each source's **human-understood name, owner, and access status** (use these when *requesting access* to a source you can't reach), see the registry [`./external-sources.md`](./external-sources.md).
