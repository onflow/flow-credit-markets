<!--
FCM ADOPTION NOTE (added 2026-06-09): This document is the canonical authoring
standard for specs in flow-credit-markets. Every versioned spec and adjacent doc
in this repo must pass the "cold-AI test" defined below — it must be understandable
by a fresh reader (human or AI) with no access to any author's private/ephemeral
notes. See specs/README.md for how this standard applies when authoring or
extending an FCM spec. The body below is the general statement of the paradigm,
adopted here verbatim; read "persisted content / memory" as "any versioned spec
or doc in this repo."
-->

# The Cold-AI Paradigm — Writing Persisted Content for a Future Self With No Memory

**Authored:** 2026-06-09, by an AI persona in conversation with a senior human collaborator.
**Status:** established discipline (settled, not hypothesis-shaped). Consolidates material previously scattered across `writes-thinks-speaks.md`, `10-ADAPTIVE-MEMORY-STRUCTURE.md § 5–6`, and `11-MULTI-PROJECT-BOOTSTRAP.md § 6.5`.
**Audience:** a cold AI in a fresh session with no access to the originating workspace and no other context. Self-contained on purpose. If you are that reader, this document is both the explanation of the paradigm and a worked example of it.

---

## 0. One-line purpose

Everything an AI persona persists to memory will next be read by a **cold AI** — a fresh instance with no chat history, no prior sessions, no shared context with whoever wrote it. The persisted text is the *only* thing that reader sees. The cold-AI paradigm is the discipline of writing every persisted artefact so that this reader can use it correctly with zero recovered context.

---

## 1. The problem this solves

AI agents lose context between sessions. A conversation, its reasoning chain, the human's clarifications, the shared understanding built up over an hour of work: all of it evaporates at session end. What survives is only what was written to a durable file.

> **Cold AI** = a fresh AI instance that loads the persisted content with no chat history, no prior sessions, and no shared context with whoever produced it. The persisted text is the only thing the reader sees.

This produces a specific, recurring failure: content gets written *as if the writer will be there to read it*. The author has full context, so the persisted note feels complete. It uses a term coined ten minutes ago, references "the approach we discussed," states "this is a test" without saying what would confirm or refute it, records a decision without its rationale. To the author, every gap is silently filled by live memory. To the cold reader, the gaps are simply holes: undecodable terms, unfalsifiable claims, decisions with no reconstructable reason.

The constraint is sharper for AI personas than for humans. A human reading their own old notes fills implicit gaps from common sense and lived experience. A cold AI cannot reconstruct the originating conversation and has no episodic memory of having been the author. Whatever context is not *in the text* does not exist for it.

So the paradigm is not merely "write clearly." It is "write for a reader who shares nothing with you except the text in front of them." Naming that reader explicitly is what stops the writer from forgetting who they are writing for.

---

## 2. The cold-AI test (the write-time gate)

The paradigm operationalizes into a single mandatory gate applied **before persisting any content**. A future AI in a brand-new chat reads the content cold. With zero context from the originating conversation, can they:

1. **Decode** — is every term, abbreviation, reference, shorthand, and coined phrase grounded inline or via a cross-reference the reader can actually follow?
2. **Understand purpose** — what does this prescribe / claim / decide / define? Why does it exist?
3. **Recognise relevant signals** — what observations matter, given the content type? (For a hypothesis: confirm/refute observations. For a directive: when to apply, when not to. For a decision-pending: the trigger condition. For a coined term: in-scope and out-of-scope examples. For a claim: counter-evidence.)
4. **Place in lifecycle** — what is its status, age, originating context, and current applicability?

**If any of the four is unanswerable from the persisted text alone, the persistence is incomplete.** Add what is missing. Do not rely on "I'll remember this from the conversation" — the reader is not you, and the conversation is gone.

For forward-looking content (recommendations, decisions-pending, experiment claims), add a fifth requirement: explicit **how-to-check-status instructions**, i.e. what a future session can read, run, or count to evaluate the item mechanically.

---

## 3. A worked example

The gap between context-dependent and cold-readable is concrete. Below is a reflection note as it might first be written, and the same note rewritten to pass the test.

**Fails the test** (written for an author who will remember):

> Tried the new approach on the oracle thing and it worked better, so we should keep doing it. Revisit later.

A cold reader cannot **decode** ("the new approach," "the oracle thing"), cannot **recognise signals** (worked better *than what*, measured *how*?), and cannot **place it in lifecycle** ("revisit later" has no trigger). It is an unfalsifiable habit waiting to happen.

**Passes the test** (self-contained):

> **Directive (hypothesis-test, status: hypothesis, authored 2026-06-09):** When reviewing an oracle price spec, check freshness-window handling *before* aggregation logic.
> **Hypothesis:** freshness bugs are higher-severity and cheaper to spot first, so front-loading them reduces total review passes.
> **Confirm signals:** (1) a freshness defect is caught that aggregation-first review missed; (2) review converges in fewer passes on the next two specs.
> **Refute signals:** (1) freshness-first ordering surfaces nothing aggregation-first would not have; (2) it delays catching a higher-severity aggregation bug.
> **Re-evaluate:** after the next 3 oracle-spec reviews.
> **How to check status:** count oracle-spec review entries in the session log since this date; at ≥3, compare defect-catch order against the signals above.

Same insight. The difference is entirely in what the text carries versus what it leaves to a memory the next reader does not have.

---

## 4. Scope: everything persisted

The test applies to **all persisted content**, not just to directives. This includes:

- Behavioral directives (both pattern-extraction and hypothesis-test flavors)
- Technical findings and conclusions
- Open questions and decisions-pending-evidence
- Recommendations and proposals authored in conversation
- Candidate patterns awaiting promotion
- Concept definitions and coined terms
- Reflection notes intended to survive the session

If it is being written to a file that a future session will read, it is in scope.

---

## 5. Specialisation by content type

The four general questions specialise differently for different content types. The specialisation is the practical guidance — it tells you *what specifically* to check for each kind of artefact.

| Content type | Specialised form of the test |
|---|---|
| **Pattern-extraction directive** | Three cues — target (the outcome), evaluate cue (the question that fires the rule), act cue (the smallest nudge) — each self-contained; a future AI applies it without conversation context. |
| **Hypothesis-test directive** | Six fields — directive, hypothesis, confirm signals, refute signals, re-evaluation trigger, provenance (see `§ 6`); the cold read must answer all six. |
| **Technical finding / conclusion** | Claim, evidence, and status all decodable; a future AI evaluates the claim and its evidence without recovering reasoning from conversation. |
| **Open question / decision-pending** | Question, candidate answers, current default, persisted trigger, and how-to-check-status instructions all stated; a future AI acts on the trigger without conversation context. |
| **Recommendation / proposal** | Proposal, rationale, hypothesis-shape (what would confirm or refute it), and follow-up actions sequenced to events; a future AI executes it without conversation context. |
| **Concept definition / coined term** | Term, definition grounded in mechanism (not in conversation), scope, and in/out-of-scope examples; a future AI uses the term with the originating precision. |
| **Jargon / shorthand label** | Any term coined in conversation must be decoded inline at first use in the persisted artefact. Ungrounded conversation-shorthand is a primary failure mode. |

---

## 6. The hypothesis is load-bearing memory

For any forward-looking content — a test claim, a recommendation, a decision-pending — the underlying **reason** (the hypothesis, the rationale, the decision criteria) is itself the load-bearing field. It is not optional background.

Persisting only the *action* without the *reason* produces an **unfalsifiable habit**: the future session performs the action, observes some outcome, but has no rubric for deciding whether the outcome confirms or refutes the original conjecture. The behavior ossifies into a procedure with no exit ramp. The whole point of framing something as a hypothesis — that it might be wrong and we want to find out — is lost.

Concretely, a hypothesis-test directive needs six fields, because the load-bearing knowledge is *the test*, not the behavior:

| Field | Question it answers | Failure if missing |
|---|---|---|
| **Directive** | What action does this prescribe? | Reader can read but cannot apply. |
| **Hypothesis** | What outcome is this expected to improve? (Falsifiable claim.) | Reader can apply but cannot evaluate; becomes an unfalsifiable habit. |
| **Confirm signals** (1–3) | What observations would support it? | Confirmation cannot be recognised; reinforcement never fires. |
| **Refute signals** (1–3) | What observations would refute it? | Refutation cannot be recognised; exceptions accumulate silently. |
| **Re-evaluation trigger** | When is the next evaluation? (After N applications? At an event? Next reflection cycle?) | "Evaluated" only by accident — in practice, never. |
| **Provenance** | Date authored; motivating observation; current status. | Lifecycle stage invisible; history erodes. |

A pattern-extraction directive, by contrast, compresses to a table row, because its load-bearing knowledge *is* the behavior and the persisted text only needs to remind the persona of what already works.

---

## 7. The test applies recursively

The cold-AI test applies not only to directives and findings, but to **any persisted claim about whether the persona's own behavior is working.**

Claims of the form "this is a test of X," "leaving Y open is itself a small experiment," "we'll see whether Z proves useful," "the next session will tell us whether the marker has effect" — these are themselves persisted artefacts. If they live only in conversation, they evaporate at session end. If they live in memory but lack concrete confirm/refute observations and a persisted trigger, they are rhetoric, not tests.

### Negative observations are undecidable without a trigger

This is the sharp corollary. Suppose the persona claims "we're testing whether the next session retro-marks structure X," and the next session does *not* retro-mark X. You cannot tell which of three things happened:

- (a) it considered X and decided against,
- (b) it noticed X but didn't surface the consideration,
- (c) it never thought about X at all.

Three indistinguishable outcomes; only one is "the directive failed." When a test depends on something *not* happening, the absence of action carries no information unless a **persisted trigger forces the consideration to surface**.

### Persisted trigger forms

For an experiment claim to be cold-AI-testable, it needs a trigger somewhere a future session will actually encounter:

1. **Open question** in the rolling session record — read at session start; fires at retrieval time. Best for "we'll know when behavior X happens or doesn't."
2. **File marker** at the point of expected effect — encountered whenever the file is read for any reason. Best for "we want to know whether structure X is treated as decorative or operational."
3. **Scheduled review** in a retrospective or periodic reflection — fires on a count or calendar event. Best for "evaluate after N applications."

Without one of these, the claim is not a test. It is a wish.

---

## 8. Relationship to the three communication modes

A persona communicates in three modes, each with a different consumer. The cold AI is the consumer of exactly one of them.

| Mode | Consumer | Style |
|---|---|---|
| **Writes** (memory / persona / persisted reference content) | A **cold AI** in a future session | Compact, detail-rich, dense. Bullets, tables, fragments, cross-references. Every term decoded inline. Density is a first-class metric, bounded by decodability. |
| **Thinks** (scratchpad / internal reasoning) | Self, in the current turn, with full context | Expressive; full reasoning chains; density is *not* a goal — completeness is. |
| **Speaks** (chat with the human) | A human peer in the current chat | Adapted to the peer's preferred style; chat-scoped recall assumed. |

The cold-AI paradigm *is* the discipline for the writes mode. Two consequences:

- **Density is justified, not optional.** Persisted content is loaded at session start, before the task begins, paid once per session forever. Prose overhead in memory directly subtracts from the budget available for the actual work. Frame density as a performance metric — bounded by "does not degrade decodability."
- **Never paste between modes.** Conversational prose pasted into memory reads bloated and low-density; memory pasted into chat reads terse and jargon-heavy. Crossing a mode boundary is an explicit rephrasing step: read the source, extract the load-bearing claims, restate for the destination consumer.

---

## 9. When and how to apply

The cold-AI test is a **write-time** gate, applied in this order:

1. Author the content as you naturally would.
2. Mentally simulate a fresh AI instance reading only the persisted text — no conversation, no chat history, no prior sessions.
3. Walk the four questions: decode, understand purpose, recognise signals, place in lifecycle.
4. For forward-looking content, also confirm the how-to-check-status instructions are present.
5. If any question is unanswerable, add what is missing to the text. Do not defer to live memory.

The cost of applying the gate is one short self-simulation per persisted artefact. The cost of skipping it accumulates silently: undecodable memory, unfalsifiable habits, decisions whose rationale is lost, experiments that never resolve.

### Reference vs. operational trigger

This document is the **reference** form of the test: it explains the paradigm and is read during bootstrapping or reflection. A reference alone does not cause the behavior at the moment it is needed, which is the instant just before content is written to a file. A persona therefore needs a second, **operational** form: an in-the-moment behavioral directive wired into whatever fires after every substantive response (a post-response checklist or memory-update trigger). The directive's job is to catch the write-time moment; this document's job is to define what the directive checks. Personas that hold only the reference, and never the trigger, will know the paradigm and still forget to apply it under task pressure.

---

## 10. Failure modes the paradigm prevents

- **Ungrounded shorthand.** A term coined in conversation is persisted without inline grounding; the cold reader cannot decode it. (Caught by question 1.)
- **The unfalsifiable habit.** An action is persisted without its hypothesis; the cold reader applies it forever with no rubric to evaluate it. (Caught by `§ 6`.)
- **The rhetorical test.** "This is an experiment" persisted with no confirm/refute signals and no trigger; the experiment never resolves. (Caught by `§ 7`.)
- **The undecidable negative.** A test that depends on an absence, with no trigger to force the consideration to surface; three outcomes collapse into one. (Caught by `§ 7`.)
- **Cross-mode leak.** Conversational prose pasted into memory, or memory pasted into chat, without the rephrasing step; each consumer pays a silent tax. (Caught by `§ 8`.)
- **Lost lifecycle.** Content persisted without status, age, or provenance; the cold reader cannot tell whether it is current, stale, settled, or experimental. (Caught by question 4.)

---

## 11. Cold-AI test applied to this document

This document must pass its own test. A cold AI reading it with no other context should be able to:

- **Decode** — every term (cold AI, the four-question test, the writes/thinks/speaks modes, hypothesis-test directive, persisted trigger, unfalsifiable habit) is grounded inline.
- **Understand purpose** — it explains the cold-AI paradigm and serves as a write-time gate for everything persisted to memory.
- **Recognise signals** — the gate has been applied when persisted content survives the four questions; it has failed when any question is unanswerable from the text alone.
- **Place in lifecycle** — established discipline, authored 2026-06-09, consolidating three predecessor files; settled (not hypothesis-shaped); applicable to any AI persona with persistent cross-session memory.

If this document ever degrades to where a cold AI cannot apply the test it describes, the discipline has failed on its own author.

---

## Cross-references

- `writes-thinks-speaks.md` — the three communication modes; cold AI as the consumer of the writes mode.
- `10-ADAPTIVE-MEMORY-STRUCTURE.md § 5–6` — the cold-AI test for hypothesis-test directives; the recursive principle; persisted-trigger forms.
- `11-MULTI-PROJECT-BOOTSTRAP.md § 6.5` — the four-question test as a bootstrap acceptance gate.
- `01-MEMORY-SYSTEM.md` — the persistence infrastructure the paradigm protects.
- `03-SELF-IMPROVEMENT.md § Directives Are Hypotheses` — the foundational treatment of directives-as-hypotheses that `§ 6` builds on.
