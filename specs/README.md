# FCM Specs — how this repo governs its work

> **Read this first if you're about to author or extend a spec in flow-credit-markets** — whether you're a human contributor or an AI assisting one. This document is self-contained: it does not depend on any author's private notes. It explains *why* we spec, *what good looks like*, and *how* to write one so the next reader (human or AI, months later, with none of today's context) can pick it up cold.

## 1. Why spec-driven development here (condensed)

We govern non-trivial FCM work with a short, living **spec** before building it — not a 40-page upfront doc, but a checkable artifact that says what "good" looks like and changes as we learn. FCM puts **real user funds on-chain, irreversibly** (a levered-yield ERC4626 vault on Flow EVM with Cadence-driven rebalancing — see [`../docs/architecture.md`](../docs/architecture.md)), so the cost of underspecified, drifting intent is high. Specs move the disagreement to the cheap layer (a markdown doc) before code exists.

This repo also uses the top-level spec as a **business-strategy surface**: it is deliberately structured so that business-relevant information (target users, KPIs, risks, tradeoffs) *emerges from* the engineering process rather than being reconstructed afterward. Method lineage: GitHub Spec Kit + Dapper's "dapper-spec-kit" adaptation. The durable principles FCM is held to live in [`../constitution.md`](../constitution.md).

## 2. Design principles for specs in this repo (the meta level)

These are principles about *the specs themselves*, so contributors can extend them **autonomously**:

- **Self-contained / cold-readable.** Every spec and adjacent doc must be understood by a fresh reader with no access to chat history or anyone's local notes. This is non-negotiable — see the canonical standard in [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md). If a spec relies on context that isn't written down in a versioned in-repo doc, inline it or link a versioned doc.
- **Hierarchical, with the product spec as source of truth.** The top-level product spec carries the full business case. Deeper technical sub-specs **inherit** from it and **must consult it first** — reference upward, don't restate. (Constitution Principle VII.)
- **Tiered business coverage by altitude.** Required business depth scales with altitude (§4), never to zero for anything user- or fund-facing.
- **Living, not frozen.** A spec changes as you learn; mark sections that iterate. Findings from implementation flow back into the spec.
- **Checkable, not ceremonial.** Keep it short. Bureaucracy is itself a failure mode. A one-line change doesn't need a spec.
- **Riskiest-assumptions-first.** State what would make this wrong (an adversarial pre-mortem), cheaply, up front.

## 3. The spec hierarchy & index

```
specs/
├── README.md            # this file — authoring conventions + meta
├── COLD-AI-PARADIGM.md  # the canonical self-containedness standard
└── <NNN-slug>/
    ├── spec.md          # the what & why (required)
    ├── plan.md          # the how (added at plan stage)
    └── tasks.md         # the evidenced checklist (added at tasks stage)
```

**Index of specs** (keep current as specs are added):

| ID | Title | Altitude | Status |
| :--- | :--- | :--- | :--- |
| _(001-fcm-product, forthcoming)_ | FCM top-level product spec | product | — |

The **product spec is the root** of the hierarchy; technical sub-specs link up to it.

## 4. How to author or extend a spec

**Recommended tooling:** the `dapper-spec-kit` Claude Code plugin provides guided commands — `/dapper-spec-kit:speckit-specify` (spec), `…speckit-plan`, `…speckit-tasks`, `…speckit-clarify`, `…speckit-analyze`. You can also author by hand following the conventions below; the tooling is an aid, not a requirement.

**Frontmatter (required on every `spec.md`):**

```yaml
---
spec_id: NNN-slug          # MUST equal the directory name, e.g. 001-fcm-product
title: <one line>
status: draft              # draft | planned | in-dev | blocked | shipped | superseded
owner: <name or github handle>
created: YYYY-MM-DD
updated: YYYY-MM-DD
constitution: ../../constitution.md
# superseded_by: NNN-slug  # required ONLY if status: superseded
---
```

Rules a lightweight lint enforces (so keep them true): `status` must be one of the six values above (no `done`/`complete`); a `shipped` spec has zero open `[ ]` tasks in its `tasks.md`; a `superseded` spec names its replacement via `superseded_by`; `spec_id` equals the directory slug; spec references resolve to a real `specs/<id>/`.

**Body — use this section structure** (a Working-Backwards / problem-first shape):

1. **Problem & why now** — what's broken/needed, and why now.
2. **Target user & outcome** — who it's for and the value/yield to them.
3. **Definition of Done & Metrics** — what "good" is, measurably (KPIs).
4. **Non-goals** — what this explicitly does *not* cover.
5. **Riskiest Assumptions & Tests** — the adversarial pre-mortem: what would make this wrong, and how we'd find out.
6. **Prior Art & Build-vs-Buy** — what exists, what we reuse vs build.

Annotate where useful: `[USER]` = needs a human decision; `[AGENT→VALIDATE]` = AI drafts, then verify; `⟳` = section iterates over time.

**Business-coverage tier by altitude** (Constitution Principle VII):

| Altitude | Required business coverage |
| :--- | :--- |
| **Product** (top-level) | FULL: target users, value prop, market sizing, competitive framing, revenue model, KPIs, business risks/tradeoffs, status. |
| **Mid technical** | LIGHT: a few lines — KPIs moved, user value, risks/tradeoffs to escalate, status. **Consult the product spec first**; reference up, don't duplicate. |
| **Deep technical** | Encouraged, not gated — but still consult the product spec for already-captured context. |

**Before you call a spec done:** run the cold-AI test from [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) — could a fresh reader, with no other context, decode every term, understand its purpose, and place it in its lifecycle? If not, add what's missing.

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

## References (all in-repo, versioned)
- [`../constitution.md`](../constitution.md) — durable principles + governance.
- [`../OWNERS.md`](../OWNERS.md) — roles, the Approver binding, high-impact definition.
- [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) — the self-containedness standard.
- [`../docs/architecture.md`](../docs/architecture.md), [`../docs/vault-rebalancer.md`](../docs/vault-rebalancer.md), [`../README.md`](../README.md) — what FCM is.
