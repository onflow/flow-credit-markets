# Methodology decisions — flow-credit-markets

> Decisions about the **spec-authoring methodology itself** — how we write, evidence, govern, and maintain specs in this repo. These are **`MD-` (Methodology Decision)** entries, kept deliberately separate from FCM **content/product** decisions (which live in [`DECISIONS.md`](./DECISIONS.md) as `DR-` entries). A stakeholder asking "what decisions were made for the FCM *product*?" wants `DECISIONS.md`, **not** this file — this file is process/meta. See [`AUTHORING.md`](./AUTHORING.md) for the classification rule and what to do when a decision's class is unclear (ask).

## Format

```
### MD-NNN — <title>   (status: accepted | superseded)
- **Date / provenance:** YYYY-MM-DD · PR/commit · who decided (GitHub handle)
- **Decision:** <the durable methodology choice>
- **Why:** <rationale>
- **Path to a check:** <how this is/could be enforced — a principle, lint, or PR-review checklist item; or "convention only">
```

Supersede, don't delete: to revise, add a new MD that flips the old one's status to `superseded` and references it.

---

### MD-001 — Adopt spec-driven development with cold-AI self-containedness for FCM   (status: accepted)
- **Date / provenance:** 2026-06-09 · initial spec-kit setup · `AlexHentschel`
- **Decision:** FCM governs non-trivial work with versioned specs under `specs/<NNN-slug>/`, beneath a repo `constitution.md`; every versioned doc must be self-contained per [`COLD-AI-PARADIGM.md`](./COLD-AI-PARADIGM.md) (no dependency on anything outside this repository).
- **Why:** real user funds are at stake irreversibly on-chain; contributors (and their AIs) must extend specs autonomously without access to any author's private notes or chat history.
- **Path to a check:** the spec-lint enforces bookkeeping; the cold-reader gate ([`AUTHORING.md`](./AUTHORING.md) §11) is a PR-review checklist item.

### MD-002 — Encode memory/learning discipline as versioned files, not runtime state   (status: accepted)
- **Date / provenance:** 2026-06-09 · adoption of an external authoring-discipline corpus, analyzed and filtered · `AlexHentschel`
- **Decision:** Useful knowledge-gathering / memory / learning practices are adopted **only** in forms expressible as versioned in-repo artifacts: the spec index ([`_INDEX.md`](./_INDEX.md)), the decision records (this file + [`DECISIONS.md`](./DECISIONS.md)), per-spec `## Verification` tables and claim-status tags, supersession links, and `## Changelog` sections. Runtime-only mechanisms (session working-memory, retrieval-at-inference, reinforcement counters, always-injected checklists) are **not** adopted — they have no home a collaborator can see.
- **Why:** the repository is the only thing collaborators share; anything not in it does not exist for them. Versioned artifacts also avoid the drift that mutable counters / duplicated state cause.
- **Path to a check:** the conventions live in [`AUTHORING.md`](./AUTHORING.md); the cold-reader gate and the Verification-table requirement are enforced in PR review.

### MD-003 — Separate methodology decisions from content decisions   (status: accepted)
- **Date / provenance:** 2026-06-09 · `AlexHentschel`
- **Decision:** Two registers. **Methodology/spec-setup decisions** = `MD-` in this file. **FCM content/product decisions** = `DR-` in [`DECISIONS.md`](./DECISIONS.md). When a decision's class is genuinely ambiguous, the author asks rather than guessing.
- **Why:** people asking about FCM project decisions mean *business/product* decisions; methodology/process choices are noise to that audience and must not pollute the content record. Clean separation keeps each register answerable to its own audience.
- **Path to a check:** classification rule documented in [`AUTHORING.md`](./AUTHORING.md); enforced in PR review.

### MD-004 — Per-spec "Status & Open Questions" block as the cold-AI catch-up entry point   (status: accepted)
- **Date / provenance:** 2026-06-10 · `AlexHentschel`
- **Decision:** Every `spec.md` opens with a **§2.0 Status & Open Questions block** — current state, ordered next steps, and a **per-spec** open-questions register (columns: question, raised-by, directed-to, criticality `blocking|urgent|informative`, status). It is updated **in the same commit** as any spec change; [`_INDEX.md`](./_INDEX.md) points to the active spec. Registers are **per spec**, not one repo-wide register. Defined in [`AUTHORING.md`](./AUTHORING.md) §2.0 + §13.
- **Why:** a collaborator's cold-AI checking out someone else's commit must catch up at a high level and identify the next most important steps / blocking questions **without any out-of-repo context** (an author's local notes don't travel with the repo). This is the versioned, collaborator-facing equivalent of a working-state note.
- **Path to a check:** convention in [`AUTHORING.md`](./AUTHORING.md) §2.0/§13, enforced in PR review; could later add a lint that a PR touching a `spec.md` also updated its §2.0 block + `## Changelog`.
