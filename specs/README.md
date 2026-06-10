# FCM Specs — how this repo governs its work

> **Read this first if you're about to author or extend a spec in flow-credit-markets** — whether you're a human contributor or an AI assisting one. This document is self-contained: it does not depend on any author's private notes. It explains *why* we spec, *what good looks like*, and *how* to write one so the next reader (human or AI, months later, with none of today's context) can pick it up cold.

## 1. Why spec-driven development here (condensed)

We govern non-trivial FCM work with a short, living **spec** before building it — not a 40-page upfront doc, but a checkable artifact that says what "good" looks like and changes as we learn. FCM puts **real user funds on-chain, irreversibly** (a levered-yield ERC4626 vault on Flow EVM with Cadence-driven rebalancing — see [`../docs/architecture.md`](../docs/architecture.md)), so the cost of underspecified, drifting intent is high. Specs move the disagreement to the cheap layer (a markdown doc) before code exists.

This repo also uses the top-level spec as a **business-strategy surface**: it is deliberately structured so that business-relevant information (target users, KPIs, risks, tradeoffs) *emerges from* the engineering process rather than being reconstructed afterward. Method lineage: GitHub Spec Kit + Dapper's "dapper-spec-kit" adaptation. The durable principles FCM is held to live in [`../constitution.md`](../constitution.md).

## 2. Design principles for specs in this repo (the meta level)

These are principles about *the specs themselves*, so contributors can extend them **autonomously**:

- **Self-contained / cold-readable.** Every spec and adjacent doc must be understood by a fresh reader with no access to chat history or anyone's local notes. This is non-negotiable — see the canonical standard in [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md). If a spec relies on context that isn't written down in a versioned in-repo doc, inline it or link a versioned doc.
- **Hierarchical, with the product spec as source of truth.** The top-level product spec carries the full business case. Deeper technical sub-specs **inherit** from it and **must consult it first** — reference upward, don't restate. (Constitution Principle VII.)
- **Tiered business coverage by altitude.** Required business depth scales with altitude (see [`AUTHORING.md`](./AUTHORING.md)), never to zero for anything user- or fund-facing.
- **Living, not frozen.** A spec changes as you learn; mark sections that iterate. Findings from implementation flow back into the spec. Supersede, never delete — history stays auditable.
- **Checkable, not ceremonial.** Keep it short. Bureaucracy is itself a failure mode. A one-line change doesn't need a spec.
- **Riskiest-assumptions-first.** State what would make this wrong (an adversarial pre-mortem), cheaply, up front — each assumption a hypothesis with confirm/refute signals.
- **Claims carry evidence; doer ≠ verifier.** Load-bearing claims are tagged by evidence status and verified by someone other than the author (see [`AUTHORING.md`](./AUTHORING.md) §3). Critical for a product where a wrong claim can lose funds.
- **Learnings & decisions are captured structurally, and classified.** A lesson becomes a constitution principle, a check, or a recorded decision — never just prose. Decisions split by audience: **FCM content/product** decisions go in [`DECISIONS.md`](./DECISIONS.md) (`DR-`); decisions about **the spec-authoring methodology itself** go in [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md) (`MD-`). If a decision's class is unclear, ask.

## 3. The spec hierarchy & index

```
specs/
├── README.md            # this file — orientation hub (why, principles, where things live)
├── AUTHORING.md         # the detailed authoring & maintenance conventions
├── COLD-AI-PARADIGM.md  # the canonical self-containedness standard
├── _INDEX.md            # the live index — one row per spec (status, relations)
├── DECISIONS.md         # FCM content/product decisions (DR-) — "what was decided for FCM"
├── METHODOLOGY-DECISIONS.md # decisions about the spec-authoring methodology itself (MD-)
└── <NNN-slug>/
    ├── spec.md          # the what & why (required)
    ├── plan.md          # the how (added at plan stage)
    └── tasks.md         # the evidenced checklist (added at tasks stage)
```

The live index of specs is [`_INDEX.md`](./_INDEX.md) (kept current in the same commit as any spec change). The **product spec is the root** of the hierarchy; technical sub-specs link up to it via `depends_on`.

## 4. How to author or extend a spec (summary — full detail in `AUTHORING.md`)

The complete conventions live in [`AUTHORING.md`](./AUTHORING.md). In brief:

- **Tooling (optional):** the `dapper-spec-kit` Claude Code plugin provides guided `/dapper-spec-kit:speckit-*` commands (specify, plan, tasks, clarify, analyze). You can also author by hand — the tooling is an aid, not a requirement.
- **Each `spec.md`** has required frontmatter (`spec_id`, `title`, `status`, `owner`, `created`, `updated`, `constitution`; plus `supersedes`/`superseded_by`/`depends_on` relations) and a problem-first body: **§1 Problem · §2 Target user & outcome · §3 Definition of Done & Metrics · §4 Non-goals · §5 Riskiest Assumptions & Tests · §6 Prior Art**. Annotate `[USER]` / `[AGENT→VALIDATE]` / `⟳`.
- **Business coverage is tiered by altitude** (Principle VII): product spec = full business case; technical sub-specs = lighter, and consult the product spec first.
- **Claims carry evidence:** tag load-bearing claims `[unverified]`/`[evidence-supported]`/`[verified]`, back them with inline references, and record verification (by a non-author) in each spec's `## Verification` table. "Never/always/zero" claims must cite a mechanical check.
- **Before merging:** run the cold-reader gate ([`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md)) and update [`_INDEX.md`](./_INDEX.md).

A lightweight lint enforces the bookkeeping: legal `status` value, a `shipped` spec has zero open `[ ]` tasks, `superseded` names `superseded_by`, `spec_id` equals the directory slug, and references resolve.

## 5. Governance touchpoints (don't skip)

- **Constitution** ([`../constitution.md`](../constitution.md)) is the spine — read it; specs are checked against it.
- **High-impact changes** (fund-controlling logic, economic invariants, privileged authority, the EVM↔Cadence boundary, mainnet deploys, constitution amendments) require **Approver sign-off** — see [`../OWNERS.md`](../OWNERS.md) for who the Approver is and how to record it.
- **Overriding a constitution principle** is allowed only via the documented override discipline (human expert invokes it for a well-defined scope, consequences surfaced and approved, scoped override + reasoning recorded in the spec). The constitution's Governance section is authoritative.

## 6. If you are an AI helping a human author a spec

- Treat the human as the decision-maker for `[USER]` calls (value, scope, tradeoffs); you draft, research, and verify (`[AGENT→VALIDATE]`).
- Keep everything you write **in the spec** cold-readable and free of references to any private/ephemeral notes — another engineer will edit this without your context.
- Never propose overriding a constitution principle; if one creates friction, first find a way to satisfy it (see Governance).
- For changes with wide product impact, ask whether the product lead (see [`../OWNERS.md`](../OWNERS.md)) should be consulted.
- Confirm who you are working with before acting on authority-dependent decisions.
- Default new claims to `[unverified]`; never self-`[verified]` your own work — that's a reviewer's call (doer ≠ verifier). Back exhaustive claims ("never/always/zero") with a grep/test, not reasoning.
- When a lesson or decision emerges, capture it structurally (a principle, a check, or a decision record) — not as prose that will be forgotten. Classify it: FCM content/product → [`DECISIONS.md`](./DECISIONS.md) (`DR-`); spec-authoring methodology → [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md) (`MD-`); if unclear, ask.

## References (all in-repo, versioned)
- [`AUTHORING.md`](./AUTHORING.md) — the detailed authoring & maintenance conventions.
- [`_INDEX.md`](./_INDEX.md) — the live spec index (status + relations).
- [`DECISIONS.md`](./DECISIONS.md) — FCM content/product decisions (`DR-`).
- [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md) — decisions about the spec-authoring methodology (`MD-`).
- [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) — the self-containedness standard.
- [`../constitution.md`](../constitution.md) — durable principles + governance.
- [`../OWNERS.md`](../OWNERS.md) — roles, the Approver binding, high-impact definition.
- [`../docs/architecture.md`](../docs/architecture.md), [`../docs/vault-rebalancer.md`](../docs/vault-rebalancer.md), [`../README.md`](../README.md) — what FCM is.
