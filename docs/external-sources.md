# External sources & access registry — flow-credit-markets

> A versioned registry of documents that live **outside this repository** but that FCM specs/docs draw on, and that **may require granting a reader access** (e.g. a Google Doc, a private repo, an internal wiki).
>
> **Why this exists.** A reader who lacks access — especially a fresh AI with only this repo — can't describe a source beyond a bare link, which makes it awkward to request access and awkward for the owner to grant it. Recording each source's **human-understood name** (plus owner and status) lets a reader **request access by name**, and lets the owner **grant it without inspecting the link**.
>
> **How to request access (convention).** State the document's **human name and its known status**, e.g. *"I'm requesting read access to the **FCM Primer** (which I know is partially outdated)."* Name the owner from this table.
>
> **Note on dependency.** This registry is for **provenance and access**, not a content dependency. The substance a versioned doc relies on must be **inlined** into the repo (see [`../specs/AUTHORING.md`](../specs/AUTHORING.md) §11), so the repo stands alone even if a source is unreachable. External identifiers below may move or change.

| Human name | Identifier / link | Owner / who grants | Access | Content status | Used for / digest |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FCM Primer** | Google Doc, fileId `1Ph9xnx1JvvJQdMVZoEDtTagnx_FLo0wiQZCi1BjqxyE` ("(LIVE DOC) FCM Primer") | asher.farooq@flowfoundation.org | Needs grant (Google Drive) | **Partially outdated** — a live business primer that still markets the ice-boxed ALP/MOET/FYV design; lagged the Morpho pivot | Product vision / value prop. Digested in [`./legacy-design-digest.md`](./legacy-design-digest.md) (Source 5) |
| **Legacy FCM repo** (`flow-credit-markets-old`) | GitHub `onflow/flow-credit-markets-old` | onflow org | Open (public) | **ALP-era / ice-boxed** | Holds the legacy specs below; digested in [`./legacy-design-digest.md`](./legacy-design-digest.md) |
| **Legacy Price Oracle spec** | `onflow/flow-credit-markets-old` → `docs/price-oracle.md` (`main`) | onflow org | Open (public) | ALP-era; principles still relevant | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 1 |
| **Legacy Numeraire spec** | `onflow/flow-credit-markets-old` → `cadence/contracts/Numeraire.md` (open PR #13) | onflow org | Open (public) | ALP-era; principle still relevant | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 2 |
| **Legacy Health-Trigger-Manager spec** | `onflow/flow-credit-markets-old` → `docs/health-trigger-manager.md` (open PR #12) | onflow org | Open (public) | ALP-era; closest to the current rebalancer | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 3 |
| **Legacy ALP State Mutation spec** | `onflow/flow-credit-markets-old` → `docs/flow-alp-architecture.md` (open PR #16) | onflow org | Open (public) | **Historical only** — describes removed ALP | [`./legacy-design-digest.md`](./legacy-design-digest.md) Source 4 |

*Guideline: when a spec begins drawing on a new external document that might require access, add a row here with its human name, owner, and status. For GitHub PR sources, check the PR's status and read the newest version from the PR branch (or `main` if merged).*
