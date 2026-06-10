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

*No FCM content/product decisions recorded yet. The first will arrive with the top-level product spec (`001-fcm-product`). Methodology/spec-setup decisions made so far are in [`METHODOLOGY-DECISIONS.md`](./METHODOLOGY-DECISIONS.md).*
