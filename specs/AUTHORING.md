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

### 2.0 Status & Open Questions block — the cold-AI entry point (read first / write first)

Every `spec.md` **opens** with a Status & Open Questions block (immediately after the frontmatter, before §1). This is the surface a fresh reader — human or AI checking out **someone else's commit** — reads first to catch up at a high level, and the part **every spec-changing commit updates in the same commit.** It is the versioned, collaborator-facing equivalent of a working-state note (do not rely on any author's private/local notes for it). Three parts:

- **Current state** — 1–3 sentences: where the spec stands and the latest significant change (the forward-looking complement to the backward-looking `## Changelog`, §8).
- **Next steps** — the ordered, most-important actions to progress the spec (blocking items first).
- **Open questions** — a per-spec register:

  | # | Question | Raised by | Directed to | Criticality | Status |
  | :-- | :-- | :-- | :-- | :-- | :-- |
  | Q1 | … | @handle | @handle / role | blocking \| urgent \| informative | open (YYYY-MM-DD) / answered → outcome |

  **Criticality:** **blocking** = progress cannot continue until it's answered; **urgent** = needed soon, not strictly blocking; **informative** = context / nice-to-know. When guiding next steps, surface **blocking** questions first. A question that gets answered *and yields a decision* graduates to a `DR-`/`MD-` record (§9) and is marked `answered →` here with a pointer; trivial answers just flip to `answered`.

*A reader catching up should be able to read this block + the `## Changelog` and know the current state, what's next, and what's blocked — without any out-of-repo context.*

### 2.1 The §1–6 content

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

- **Evidence links follow §12.** An external evidence reference needs an explicit link **and** a stable fallback (pinned commit / fileId), plus a registry entry if access-gated; in-repo evidence is cited by repo path. The cited evidence must be paraphrased enough that a cold reader grasps it without following the link.
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

**Consolidate, don't append.** When new or more precise information arrives (a fuzzy early result sharpened later is the normal path), first check whether a related record already exists and **correct/sharpen it in place** rather than piling on a new note. Records should get *more correct and more specific* over time, not just longer. Avoid bloat: incorporate and consolidate. (Where a store is immutable, e.g. the create-only Drive integration with no update/delete, an in-place fix is impossible and a dated correction note is a forced fallback, not the goal; resolving that editability gap is preferred.) See `MD-006`.

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

## 12. External sources & content references — link, name, fallback, inline

This governs **every reference a spec makes to content outside this repository** — not just access-gated documents, but also a **source cited for a claim**, an **evidence link in a Verification table** (§3), or **prior art** (§6). The cold-reader discipline (§11) applies to all of them:

- **Explicit link + stable fallback.** Give a working link AND a fallback that survives a link-resolution failure: for version-controlled sources, a **pinned-commit (immutable) URL** (plus the PR/branch page); for a Google Drive doc, the **fileId**; for a repo, the canonical repo URL. A bare branch/`HEAD` link alone is insufficient — it moves.
- **Human-understood name.** Name the source as a human would recognize it, so a reader lacking access can **request it by name** and the owner can **grant it without inspecting the link**.
- **Register access-gated sources.** Anything requiring a grant goes in the versioned registry [`../docs/external-sources.md`](../docs/external-sources.md) (human name, owner, access + content status). When requesting access, state the name **and** its known status (e.g. *"the FCM Primer, which I know is partially outdated"*).
- **In-repo references need no external link** — cite them by repo-relative path (the exception to the rules above).
- **Inline the substance.** A content reference is corroboration/provenance, never a load-bearing dependency: a cold reader with only this repo must understand the point **without** following the link (§11).
- **This repo is PUBLIC — keep versioned content public-appropriate.** Sensitive business detail (revenue/token/fee specifics, candid internal risk/people commentary, competitive or vendor intel) is **not** committed; it lives in an **access-gated source referenced by name** (the registry, category A). When you digest a gated source, **state what was omitted and that it's retrievable from the original** — don't silently drop it. (Methodology decision `MD-005`.)
- **The designated private store** for FCM's own sensitive spec detail is the **`FCM Top-Level Product Spec` gDrive folder** (see [`../docs/external-sources.md`](../docs/external-sources.md), "Private store"). Structure it cold-AI-style: an index points to detail, one purpose per doc, and each doc records provenance (source + date) and staleness, so the gated detail stays findable by a fresh reader.
- **Recurring meeting-transcript ingestion.** New meeting transcripts are dropped in the private store's `Relevant Meeting Transcripts` folder. Standing process: crawl that folder, compare against the ingestion log (`transcript-digests/_INGESTION-LOG`), and for each new or modified transcript write a digest in `transcript-digests/`, then reflect any **public-appropriate** product updates into the spec while sensitive detail stays in the store. Run it when working the spec or when asked. (A digest's PUBLIC-vs-SENSITIVE split follows §12 above.)

## 13. Bootstrap — catching up, or starting/extending a spec (human or AI)

**Catching up on an existing spec** (e.g. after checking out someone else's commit — the cold-AI case): read the spec's **§2.0 Status & Open Questions block** and its `## Changelog` first. That's the high-level entry point — current state, ordered next steps, and blocking questions — so you can immediately guide the most important next actions (surface **blocking** questions first). [`_INDEX.md`](./_INDEX.md) points to the active spec.

**Starting or extending a spec:**
1. Read `README.md`, this file, and `constitution.md`.
2. Create `specs/<NNN-slug>/` (next free number); copy the frontmatter (§1), the **§2.0 Status & Open Questions block**, and the §1–6 body skeleton.
3. Draft claims as `[unverified]`; gather evidence; promote to `[evidence-supported]` with inline references.
4. Fill the Verification table rows (status `[unverified]`/`[evidence-supported]` — author does not self-`[verified]`).
5. Run the cold-reader gate (§11); update the spec's §2.0 block and [`_INDEX.md`](./_INDEX.md) **in the same commit**.
6. Open a PR. A reviewer (not the author) verifies claims, fills/elevates the Verification table, and records any decision in [`DECISIONS.md`](./DECISIONS.md). High-impact changes need Approver sign-off — see [`../OWNERS.md`](../OWNERS.md).
