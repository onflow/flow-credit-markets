# Decision record — flow-credit-markets (content / product)

> The versioned log of **FCM content/product decisions** — the business- and product-level calls a stakeholder means when they ask "what was decided for FCM?" These are **`DR-` (Decision Record)** entries. Decisions about the *spec-authoring methodology itself* (how we write/govern specs) do **not** belong here — they live in [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md) as `MD-` entries. See [`AUTHORING.md`](./AUTHORING.md) for the classification rule; **if a decision's class is genuinely unclear, ask rather than guess.**
>
> Prefer capturing a durable rule as a constitution principle or a check where possible ([`AUTHORING.md`](./AUTHORING.md) §9); use this record for product/business decisions and for content lessons that aren't (yet) a check.

## Format

```
### DR-NNN — <title>   (status: accepted | superseded)
- **Date / provenance:** YYYY-MM-DD · PR/commit · decided by (GitHub handle)
- **Decision:** <the durable product/business choice>
- **Why:** <business rationale — stated so it's explainable to a business stakeholder (e.g. Roham)>
- **Scope:** [product] / [domain:<vault|evm|cadence>] / [spec:<NNN>]
- **Alternatives rejected:** <what else was considered, and why not>
- **Governing spec:** <specs/<NNN-slug>, if any>
```

Supersede, don't delete: to revise a decision, add a new DR that flips the old one's status to `superseded` and references it.

---

### DR-001 — Pivot from a bespoke in-house ALP to external Morpho Blue; ice-box the ALP/MOET design   (status: accepted)
- **Date / provenance:** pivot predates this record; current status articulated 2026-06-10 by `AlexHentschel`. Historical sources digested in [`../docs/legacy-design-digest.md`](../docs/legacy-design-digest.md).
- **Decision:** FCM's lending layer is the **external Morpho Blue** protocol (with an ERC4626 Solidity outer vault on Flow EVM), **not** a bespoke in-house Automated Lending Protocol (ALP). The earlier full-Cadence design centered on the ALP and the **MOET** stablecoin is **ice-boxed — paused, not abandoned** (a far-future ALP-centric build remains under potential consideration). The **automated-rebalancing premise is retained** post-pivot, now applied to Morpho positions rather than a homegrown lending engine.
- **Why:** the ALP-centric design carried too much implementation complexity (largely the in-house lending engine — see the ALP state-mutation pipeline in the digest); building on Morpho removes that burden while preserving FCM's differentiator (automation → liquidation protection + higher sustainable LTV).
- **Scope:** [product]
- **Alternatives rejected:** continue the full-Cadence ALP/MOET build — rejected for now on complexity/timeline grounds; may be revisited in the far future.
- **Governing spec:** (forthcoming `001-fcm-product`); historical context in [`../docs/legacy-design-digest.md`](../docs/legacy-design-digest.md).

*Methodology/spec-setup decisions are in [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md).*
