# Decision & learnings record — flow-credit-markets

> The versioned, append-mostly log of decisions and learnings that are **not** otherwise captured as a constitution principle, a checklist item, or a CI/test check. This is the in-repo analog of "learned memory": durable lessons that survive across contributors and time, with provenance. **Prefer encoding a lesson as a check or a principle** ([`AUTHORING.md`](./AUTHORING.md) §9); use this file only when that isn't (yet) possible, and note the path to making it a check.

## Format

Each entry:

```
### DR-NNN — <title>   (status: accepted | superseded)
- **Date / provenance:** YYYY-MM-DD · PR/commit · who decided (GitHub handle)
- **Decision / learning:** <the durable statement>
- **Why:** <rationale — stated so it's explainable to a business stakeholder>
- **Scope:** [product] / [domain:<vault|evm|cadence>] / [spec:<NNN>]
- **Rule that failed or was missing:** <if this came from a fix/postmortem; else —>
- **Path to a check:** <how this could become a principle/test/lint, or "already encoded in <X>">
```

Supersede, don't delete: to revise a decision, add a new DR that sets the old one's status to `superseded` and references it.

---

### DR-001 — Adopt spec-driven development with cold-AI self-containedness for FCM   (status: accepted)
- **Date / provenance:** 2026-06-09 · initial spec-kit setup · `AlexHentschel`
- **Decision / learning:** FCM governs non-trivial work with versioned specs under `specs/<NNN-slug>/`, under a repo `constitution.md`; every versioned doc must be self-contained per [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) (no dependency on anything outside this repository).
- **Why:** real user funds are at stake irreversibly on-chain; contributors (and their AIs) must be able to extend specs autonomously without access to any author's private notes or chat history.
- **Scope:** [product]
- **Rule that failed or was missing:** —
- **Path to a check:** partially encoded — the lint enforces spec bookkeeping; the cold-reader gate ([`AUTHORING.md`](./AUTHORING.md) §11) is a PR-review checklist item.

### DR-002 — Encode memory/learning discipline as versioned files, not runtime state   (status: accepted)
- **Date / provenance:** 2026-06-09 · this change · `AlexHentschel` (+ AI analysis of an external authoring-discipline corpus)
- **Decision / learning:** Useful knowledge-gathering/memory/learning practices are adopted **only** in forms expressible as versioned in-repo artifacts: this index ([`_INDEX.md`](./_INDEX.md)), this decision log, per-spec `## Verification` tables and claim-status tags, supersession links, and `## Changelog` sections. Runtime-only mechanisms (session working-memory, retrieval-at-inference, reinforcement counters, always-injected checklists) are explicitly **not** adopted — they have no home a collaborator can see.
- **Why:** the repo is the only thing collaborators share; anything not in it doesn't exist for them. Versioned artifacts also avoid the drift that mutable counters/duplicated state cause.
- **Scope:** [product]
- **Rule that failed or was missing:** —
- **Path to a check:** the conventions live in [`AUTHORING.md`](./AUTHORING.md); the cold-reader gate and Verification-table requirement are enforced in PR review.
