# Authoring & maintaining FCM specs — conventions

> The detailed conventions for writing, evidencing, and maintaining specs in this repo. Read [`README.md`](./README.md) first for orientation; read [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) for the self-containedness standard every doc here must pass. These conventions adapt proven knowledge-gathering, evidence, and learning disciplines into **versioned, in-repo** form — nothing here depends on any tool's runtime memory, chat history, or files outside this repository.

## 1. Spec frontmatter (required on every `spec.md`)

```yaml
---
spec_id: NNN-slug          # MUST equal the directory name, e.g. 001-fcm-product
title: <one line>
status: draft              # draft | planned | in-dev | blocked | shipped | superseded
owner: <name or github handle>
created: YYYY-MM-DD
updated: YYYY-MM-DD
constitution: ../../constitution.md
supersedes: NNN-slug       # optional — the spec this replaces
superseded_by: NNN-slug    # required ONLY if status: superseded
depends_on: [NNN-slug, …]  # optional — specs this builds on
---
```

A lightweight lint enforces: `status` ∈ the six values above (no `done`/`complete`); a `shipped` spec has zero open `[ ]` tasks in its `tasks.md`; a `superseded` spec names `superseded_by`; `spec_id` equals the directory slug; every referenced `specs/<id>` resolves.

## 2. Spec body — the §1–6 structure (problem-first / working-backwards)

1. **Problem & why now** — what's broken/needed, why now.
2. **Target user & outcome** — who it's for, the value/yield to them.
3. **Definition of Done & Metrics** — what "good" is, measurably (KPIs).
4. **Non-goals** — what this explicitly does not cover.
5. **Riskiest Assumptions & Tests** — the adversarial pre-mortem (see §5 below).
6. **Prior Art & Build-vs-Buy** — what exists, reuse vs build.

Annotate: `[USER]` = needs a human decision; `[AGENT→VALIDATE]` = AI drafts then verify; `⟳` = section iterates.

**Business-coverage tier by altitude** (Constitution Principle VII):

| Altitude | Required business coverage |
| :--- | :--- |
| **Product** (top-level) | FULL: target users, value prop, market sizing, competitive framing, revenue model, KPIs, business risks/tradeoffs, status. |
| **Mid technical** | LIGHT: a few lines — KPIs moved, user value, risks/tradeoffs to escalate, status. **Consult the product spec first**; reference up, don't duplicate. |
| **Deep technical** | Encouraged, not gated — still consult the product spec for already-captured context. |

## 3. Claims carry evidence: the status ladder + Verification table

This is the core discipline for a product where wrong claims can lose user funds. It encodes *verify-before-trust* and *doer ≠ verifier* (Constitution Principles II, IV, VI) as versioned text.

- **Tag every load-bearing claim** inline with one of: `[unverified]` · `[evidence-supported]` · `[verified]` · `[disputed]` · `[invalidated]`.
- New claims default to **`[unverified]`**. A claim becomes **`[evidence-supported]`** only with an inline evidence reference — a code path + symbol, a test name, or a link to an audit/doc. A claim becomes **`[verified]`** only via the Verification table, set by a reviewer who is **not** the author (doer ≠ verifier).
- **Exhaustive-claim rule.** Any statement using "never / always / all / none / zero" must cite the *mechanical* check that establishes it (a grep/AST query, an enumerating or invariant test) — reasoning alone is insufficient. (Mirrors Constitution's invariant-tests standard.)
- **Every `spec.md` ends with a `## Verification` table** — the spec's audit trail, edited in the same PR that reviews it:

  | Claim | Status | Evidence (path:symbol / test / link) | Reviewer (GitHub) | Commit/Date |
  | :--- | :--- | :--- | :--- | :--- |

- **Supersession of verification.** When a spec is revised or an upstream dependency changes, demote affected `[verified]` claims back to `[unverified]` in the new version. Never inherit `verified` across a material change — re-verify.

## 4. Single source of truth for invariants

Declare each financial/economic invariant (e.g. a TVL cap, a health-factor floor, a rounding direction) **once** — in the constitution or the owning spec — and have other specs **reference it by id**, never restate the value. Duplicated values drift and silently diverge; one authoritative location prevents it.

## 5. Riskiest assumptions are hypotheses with signals

Treat each spec assumption as a falsifiable hypothesis (not a hope). In §5 of the body, each entry states: **the assumption**, a **confirm signal**, and a **refute signal**. Implementation must resolve each — confirmed (close it) or refuted (amend the spec, in a commit) — before the spec is marked `shipped`. This makes "what would make this wrong" cheap and explicit, and makes confidence visible in git history.

## 6. `plan.md` — layered commitment (flexible plans)

When you write the plan, **fix** these and label the rest revisable:
- **Fix:** Targets · Constraints/invariants · Known-unknowns · Checkpoints · Authority handoffs.
- **Mark *Initial — revisable*:** Approach, Acceptance criteria.
- **Do NOT pre-fix:** file layouts, function signatures, or step sequences beyond the next action — leave shape to implementation.
- **Audible checkpoints:** each checkpoint records either a revision or an explicit "no-change" — silence is the failure mode. Scope growth requires escalation *before* expanding, never silent absorption.

## 7. `tasks.md` — evidenced checklist

Each task is `[ ]` until done, then `[x]` with a one-line evidence pointer (commit, test, or artifact). A `shipped` spec has zero open `[ ]` (lint-enforced). Implementation findings flow **back into `spec.md`** — but as a *separate* commit from the task work (one concern per change).

## 8. Lifecycle & maintenance

- **Supersede, never delete.** To replace a spec, create a new `NNN-slug`, set `supersedes`/`superseded_by` on both, flip the old to `superseded`. History stays auditable.
- **Amend via a `## Changelog` section**, not silent edits: each entry = date · change · reason. Reorganizing a doc and changing its content are **separate** commits (separation of concerns — the top failure vector).
- **3-amendment promotion.** If the same spec section is amended 3+ times for the same root cause, that's a latent rule — promote it to a constitution principle or a deterministic check, and record it (§9).
- **Tier caution.** `constitution.md` > these `specs/` conventions > an individual spec. Changing a higher tier needs stronger justification (constitution edits require a version bump + rationale per its Governance).
- **Keep [`_INDEX.md`](./_INDEX.md) current** — every new/changed spec updates its row in the same commit.

## 9. Capturing decisions & learnings — structural, and correctly classified

A lesson is only "captured" when it lands as **a constitution principle, a checklist/PR-template item, or a CI/test/lint check** — never as a buried paragraph (prose rules get satisfied syntactically and violated semantically). If a decision or lesson can't (yet) be a check, record it — in the **correct register**, because the two classes serve different audiences:

- **Content / product decisions** — FCM business and product calls (target users, fees, which markets, risk/return tradeoffs, …). → [`DECISIONS.md`](./DECISIONS.md), prefixed **`DR-`**. This is what a stakeholder means by "what was decided for FCM." Keep this record clean.
- **Methodology / spec-setup decisions** — how we author, evidence, govern, and maintain specs (the process itself). → [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md), prefixed **`MD-`**.

**Classification rule:** ask *"is this a decision about the FCM product/business (→ DR), or about the spec-authoring methodology (→ MD)?"* Methodology noise must never pollute the content record. **If the class is genuinely unclear, ask a maintainer rather than guessing.**

On any fix, ask **"which existing rule should have caught this?"** and fix that rule, not just the symptom.

## 10. Writing rules (for editing the constitution or these conventions)

Every normative rule should state four things, or it's a fact pretending to be a rule:
- **Target** — the outcome it protects.
- **Evaluate-cue** — when the rule fires (the situation to watch for).
- **Act-cue** — the smallest action it prescribes.
- **Scope** — `[product]` / `[domain:<vault|evm|cadence>]` / `[spec:<NNN>]`. Default to the narrowest scope; widen only with evidence.

Mark unproven rules `(experimental)`. Keep hard `must/never` prescriptions a minority, reserved for catastrophic-if-violated invariants — over-prescription drifts a guideline into noise.

## 11. Before you merge — the cold-reader gate

Apply the test in [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md): a fresh reader, with only this repository (no chat, no Slack, no author's local notes), must be able to **decode** every term, **understand** the purpose, **recognise** what evidence matters, and **place** the doc in its lifecycle. If any fails, inline what's missing. No versioned doc may reference anything outside this repo.

**Importing external context — inline, don't link out.** When you bring information from a source outside this repository (an external document, a chat, a tool's output, another repo) into a versioned doc, **inline the substance and remove the external pointer.** Never leave a link or path a collaborator's checkout won't contain — a reader has only the files under this repository. (Worked example: when [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) was adopted from an external corpus, its cross-references to that corpus were stripped and replaced with in-repo ones.) A reference to something outside the repo is a cold-reader-gate failure, not a convenience.

## 12. New-author bootstrap (human or AI)

1. Read `README.md`, this file, and `constitution.md`.
2. Create `specs/<NNN-slug>/` (next free number); copy the frontmatter (§1) and §1–6 body skeleton.
3. Draft claims as `[unverified]`; gather evidence; promote to `[evidence-supported]` with inline references.
4. Fill the Verification table rows (status `[unverified]`/`[evidence-supported]` — author does not self-`[verified]`).
5. Run the cold-reader gate (§11); update [`_INDEX.md`](./_INDEX.md).
6. Open a PR. A reviewer (not the author) verifies claims, fills/elevates the Verification table, and records any decision in [`DECISIONS.md`](./DECISIONS.md). High-impact changes need Approver sign-off — see [`../OWNERS.md`](../OWNERS.md).
