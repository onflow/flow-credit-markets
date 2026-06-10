---
scope: repo
applies_to: "flow-credit-markets"
inherits: —
version: 0.1.0
ratified: 2026-06-09
last_amended: 2026-06-09
---

# flow-credit-markets Constitution

> The durable principles that govern how we build, decide, and operate FCM — the spine above every spec, plan, and task. Read at the start of every project in scope. Principle-only and evergreen; point-in-time specifics (tool versions, deployed addresses, the team roster, the concrete Approver binding) live in environment/owner docs, never here. Changes are deliberate, versioned, and rare.
>
> **Standalone.** FCM is a Flow Foundation product; this constitution inherits no parent and stands on its own.
>
> **What FCM is:** a levered-yield ("looping") product — an ERC4626 *outer vault* on Flow EVM that supplies user deposits to a lending protocol, borrows, and reinvests into an *inner vault* to amplify yield while holding asset exposure, with automated rebalancing driven by a Flow scheduled-transaction (Cadence) resource. Real user funds are at stake, on-chain and irreversibly.

## Core Principles

### I. Solvency before liveness; principal before uptime.
No failure mode may cause immediate loss of user principal or vault solvency. Failures must degrade *first* to liveness — paused, stale, or halted — in states recoverable without loss. *Removed, we would accept trading a solvency risk for convenience or uptime; with it, any such trade is rejected.*

### II. Economic invariants are conserved and property-tested, not assumed.
Share/asset accounting must never let anyone extract value they did not contribute; no value leaks on deposit, redeem, rebalance, or swap; inflation/donation exposure, rounding direction, and slippage are explicitly bounded. *Removed, example tests stand in for proof; with it, every value-moving change ships with invariant/property tests.*

### III. Least authority, bounded blast radius.
Every privileged capability — admin, the scheduler/automation caller, callbacks — is scoped to the narrowest action it needs. Compromise of any single key or component bounds to *liveness* impact, never fund movement; recovery paths stay permissionless and idempotent. *Removed, "admin can fix anything" creeps in; with it, god-mode designs are rejected.*

### IV. External inputs and dependencies are adversarial until verified at the boundary.
Price oracles, the AMM/DEX, the lending protocol, and the inner vault are unreliable by default — prices can be stale or manipulated, the inner vault may be illiquid, reported NAV may be days old. Every externally-sourced value is validated (freshness, slippage bound, liquidity/health check) before it can move funds. *Removed, a path could realize value at an unvalidated price; with it, none can.*

### V. The execution boundary is explicit and its failures contained.
FCM spans two execution environments — EVM (business logic) and Cadence (scheduling). The boundary's failure semantics must be reasoned about and preserved, and scheduling must stay separable from business logic so a fault in one cannot brick the other. *Removed, an entangled reschedule loop lets a business-logic fault kill liveness recovery; with it, separation is mandatory.*

### VI. Mainnet is irreversible; fund-controlling code passes adversarial review before it ships.
Code that controls user funds clears static analysis, adversarial security review, and explicit test evidence before mainnet. "It compiles and the happy path passes" is not done. *Removed, review becomes optional under deadline; with it, a fund-controlling change without security evidence is not shippable.*

### VII. Specs surface the business picture, tiered by altitude; the product spec is the source of truth.
This repo's specs are hierarchical. The **top-level product spec carries the full business case** — target users and value/yield proposition, market sizing, competitive framing, revenue model, the KPIs it moves, the risks/tradeoffs needing a *business* decision, and status — and is the canonical surface for catching strategy up. **Deeper technical sub-specs inherit from it:** they surface only the business-relevant slice at a lighter bar (KPIs moved, user value, risks/tradeoffs to escalate, status) and **must consult the product spec first**, referencing upward rather than restating what it already captures. Required business depth scales down with technical altitude but never reaches zero for anything user- or fund-facing. *Removed, Roham-level information must be reconstructed after the fact; with it, it emerges from the engineering process — the point of this repo's spec discipline.*

## Standards & Constraints

Concrete, review-verifiable bars. A violation is a finding, not a judgment call.

- **ERC4626 base safety.** The vault extends the OpenZeppelin ERC4626 base; the virtual-share inflation mitigation is preserved; overrides follow OZ's safe-extension guidance; rounding always favors the vault/existing shareholders, never the actor.
- **Slippage bound on every swap.** No swap executes without an explicit min-out/slippage bound; permissionless functions that swap vault funds are explicitly assessed for sandwich exposure.
- **Oracle freshness + sanity.** Every oracle price is staleness- and sanity-checked before it informs a fund-moving decision.
- **Health-factor safety.** No normal operation leaves the position liquidatable (HF < 1); where the path allows, debt is cleared before collateral moves; the HF ≈ 1 edge case is handled explicitly.
- **Least authority on privileged callers.** The scheduler/automation caller's on-chain authority is limited to the rebalance entrypoint (no fund-movement or admin entrypoints); flash-loan callbacks validate the caller and decode calldata defensively.
- **Reentrancy.** Every external state-changing function enforces and documents its reentrancy protection.
- **Static analysis + security harness clean.** Slither runs clean or every finding is triaged with rationale; the repo's adversarial security review (`security/`) runs on fund-controlling changes before mainnet.
- **Invariant tests for value flows.** Value-moving logic ships with Foundry invariant/property tests, not only example tests; `make ci` (fmt + build + test) passes.
- **Upgrade & parameter governance.** What is immutable vs admin-tunable is explicit; mutable parameters change only through the documented admin-entitlement path; the timelock/multisig posture is stated.
- **User disclosure.** User-facing surfaces disclose fees, that yield is variable and not guaranteed, and that liquidation and loss of principal are possible.

## Governance

This constitution supersedes ad-hoc practice. Compliance is verified at the spec/plan gates and in review — by structure, not by intention. Amendments require: a written rationale, Approver sign-off, a version bump, and a migration note. When a principle is proven wrong, correct it in place with a dated "was wrong because —" note; never let stale guidance stand beside new.

**Approver sign-off.** High-impact changes require the explicit sign-off of the **Approver** (a role; satisfied by Patrick Fuchs or Alex Hentschel), recorded in the governing spec/PR. A change is **high-impact** when it touches fund-controlling logic, an economic invariant, privileged authority, the EVM↔Cadence boundary, a mainnet deploy, or amends this constitution. (The concrete role→handle binding lives in the repo's owner doc / CODEOWNERS, not in this evergreen text.)

**Principle overrides.** Every principle here is subject to human-expert override — these bind the agent and the default process, not the accountable domain expert's judgment. The agent must never propose or encourage an override and must first exhaust ways to satisfy the principle. An override is valid only when a human expert explicitly invokes it for a specific, well-defined scenario; before it takes effect, the agent presents the consequences concisely but completely and obtains explicit approval of them. Every granted override is recorded in the governing spec — its exact scope (and no further) and the reasoning, stated so it can be explained to Roham. An override never generalizes beyond its recorded scope.

**Version:** 0.1.0  |  **Ratified:** 2026-06-09  |  **Last amended:** 2026-06-09
