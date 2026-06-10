# External sources & access registry — flow-credit-markets

> A versioned registry of documents that live **outside this repository** but that FCM specs/docs draw on, and that **may require granting a reader access** (e.g. a Google Doc, a private repo, an internal wiki).
>
> **Why this exists.** A reader who lacks access — especially a fresh AI with only this repo — can't describe a source beyond a bare link, which makes it awkward to request access and awkward for the owner to grant it. Recording each source's **human-understood name** (plus owner and status) lets a reader **request access by name**, and lets the owner **grant it without inspecting the link**.
>
> **How to request access (convention).** State the document's **human name and its known status**, e.g. *"I'm requesting read access to the **FCM Primer** (which I know is partially outdated)."* Name the owner from this table.
>
> **Note on dependency.** This registry is for **provenance and access**, not a content dependency. The substance a versioned doc relies on must be **inlined** into the repo (see [`../specs/AUTHORING.md`](../specs/AUTHORING.md) §11), so the repo stands alone even if a source is unreachable. External identifiers below may move or change.
>
> **Links.** Every external source carries an **explicit link**, plus a stable **fallback** where a resolution step could fail — for PR-based sources, the PR page **and** a pinned-commit (immutable) file link, so the exact version read is always recoverable even if the branch moves or is deleted. (Files versioned inside `flow-credit-markets` need no external link — reference them by repo path.)

Sources are grouped by **current applicability**: (A) sources that largely apply to the latest product design, and (B) legacy/historical sources from the prior ALP-era design. A source's origin (e.g. the legacy repo) does not determine its category — current applicability does.

## A. Currently-applicable references (largely apply to the latest product design)

> Created earlier (some in the legacy repo) but their **content still largely applies** to the current FCM design. Cite as live references; re-derive implementation specifics for the current stack (Solidity/EVM, Pyth, Morpho) where noted.

| Human name | Identifier / link | Owner / who grants | Access | Content status | Used for / digest |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Price Oracle spec** (author Jordan Ribbink, `jribbink`) | [file @ `main`](https://github.com/onflow/flow-credit-markets-old/blob/main/docs/price-oracle.md) · fallback: [repo](https://github.com/onflow/flow-credit-markets-old) (`docs/price-oracle.md`) | onflow org | Open (public) | **Largely applies** — oracle-safety principles (publish-time freshness, nil=hard-stop, source-disagreement + volatility breakers, fail-closed); re-derive implementation for Solidity/EVM + Pyth | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 1 |
| **Numeraire spec** (author Tim Barry, `tim-barry`) | [PR #13](https://github.com/onflow/flow-credit-markets-old/pull/13) · fallback: [file @ pinned commit `afb2a42`](https://github.com/onflow/flow-credit-markets-old/blob/afb2a42560944d912d79a5165e55b21868121491/cadence/contracts/Numeraire.md) | onflow org | Open (public) | **Largely applies** — unit-of-account discipline (one fixed numeraire, decoupled from a tradable token, used when querying oracles); re-derive for ERC4626 + Pyth | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 2 |

## B. Legacy / historical sources (prior ALP-era design — ice-boxed)

> The prior ALP-centric, full-Cadence design (ice-boxed; see [`./legacy-design-digest.md`](./legacy-design-digest.md) and `DR-001` in [`../specs/DECISIONS.md`](../specs/DECISIONS.md)). Cite for product vision and historical context, **with staleness disclaimers**.

| Human name | Identifier / link | Owner / who grants | Access | Content status | Used for / digest |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FCM Primer** | [Google Doc](https://docs.google.com/document/d/1Ph9xnx1JvvJQdMVZoEDtTagnx_FLo0wiQZCi1BjqxyE) ("(LIVE DOC) FCM Primer") · fallback: Drive fileId `1Ph9xnx1JvvJQdMVZoEDtTagnx_FLo0wiQZCi1BjqxyE` | asher.farooq@flowfoundation.org | Needs grant (Google Drive) | **Partially outdated** — a live business primer that still markets the ice-boxed ALP/MOET/FYV design; lagged the Morpho pivot | Product vision / value prop. Digested in [`./legacy-design-digest.md`](./legacy-design-digest.md) (Source 5) |
| **Legacy FCM repo** (`flow-credit-markets-old`) | [github.com/onflow/flow-credit-markets-old](https://github.com/onflow/flow-credit-markets-old) | onflow org | Open (public) | **ALP-era / ice-boxed** (but also hosts the currently-applicable specs in §A) | Container repo; digested in [`./legacy-design-digest.md`](./legacy-design-digest.md) |
| **Legacy Health-Trigger-Manager spec** (author Janez Podhostnik, `janezpodhostnik`) | [PR #12](https://github.com/onflow/flow-credit-markets-old/pull/12) · fallback: [file @ pinned commit `30cce52`](https://github.com/onflow/flow-credit-markets-old/blob/30cce52b4470a3a6366bb18c6c94b023fe8b33bb/docs/health-trigger-manager.md) | onflow org | Open (public) | ALP-era; trigger/automation concepts are close to the current rebalancer, but the health source targets the removed FlowALP | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 3 |
| **Legacy ALP State Mutation spec** (author Jordan Schalm, `jordanschalm`) | [PR #16](https://github.com/onflow/flow-credit-markets-old/pull/16) · fallback: [file @ pinned commit `78b7b94`](https://github.com/onflow/flow-credit-markets-old/blob/78b7b94b665cb92c78a9851f8535669433482b3f/docs/flow-alp-architecture.md) | onflow org | Open (public) | **Historical only** — describes the removed ALP | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 4 |

*Guideline: when a spec begins drawing on a new external document that might require access, add a row here under the right category with its human name, owner, and status. A source can graduate from B to A (or be demoted) as the design evolves. For GitHub PR sources, check the PR's status and read the newest version from the PR branch (or `main` if merged).*
