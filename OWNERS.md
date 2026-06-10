# OWNERS — flow-credit-markets

> Point-in-time roster and governance bindings for FCM. The [constitution](./constitution.md) is evergreen and names only *roles* (e.g. "the Approver"); this document binds those roles to real people and is expected to change as the team changes. When the CI gate is wired, a `.github/CODEOWNERS` will enforce the protected-path subset mechanically; until then this is the human-readable source of truth.

## People & roles

| Person | GitHub | Role |
| :--- | :--- | :--- |
| Alex Hentschel | `AlexHentschel` | Advisor — technical, leadership, product. Not a code contributor. **Approver.** |
| Patrick Fuchs | `holyfuchs` | Product lead & technical lead. **Approver.** |
| Dete | _(handle TBD)_ | CTO of Dapper & Flow; FCM's originating protocol designer/innovator (the legacy ALP variant and the newer product designs); DeFi/blockchain innovator. Core advisor & stakeholder on product + business strategy. Product role transitioning to Patrick for the execution phase. |
| Roham | _(handle TBD)_ | COO of Dapper & Flow; advisor & close collaborator on business + high-level product strategy. **Ultimate approver & stakeholder for all major business decisions.** |
| Tim Barry | `tim-barry` | Engineer. |
| Jordan Ribbink | `jribbink` | Engineer. |
| Jordan Schalm | `jordanschalm` | Engineer (temporary, as of 2026-06-09). |

**Two approval axes, kept distinct.** The constitution's **Approver** role (below) gates high-impact *spec/code* changes and is satisfied by **Patrick Fuchs or Alex Hentschel**. **Major *business* decisions ultimately gate on Roham (COO)** — the constitution's "explainable to Roham" bar means a decision's rationale must stand at the business-strategy level, not just the engineering level. **Dete (CTO)** is FCM's originating protocol designer and a core product/strategy stakeholder; the day-to-day product role is transitioning from Dete to Patrick for the execution phase.

*Name disambiguation:* a bare "Patrick" means **Patrick Fuchs** (`holyfuchs`) — not to be confused with **Patrick Permutter** ("Patrick P"), a different person in the broader team. A bare "Jordan" is ambiguous (Ribbink vs Schalm) — disambiguate as "Jordan R" / "Jordan S".

## The Approver role

"Approver" is a **role**, satisfied by **either Patrick Fuchs (`holyfuchs`) or Alex Hentschel (`AlexHentschel`)**. The constitution requires the Approver's explicit sign-off on:
- **High-impact changes** — any change that touches **fund-controlling logic, an economic invariant, privileged authority, the EVM↔Cadence boundary, a mainnet deploy, or amends the [constitution](./constitution.md).**
- **Constitution amendments** — recorded with a written rationale, a version bump, and a migration note (per the constitution's Governance section).

Sign-off is recorded in the governing spec or the PR.

## Sign-off conventions

- A **high-impact** change records Approver sign-off explicitly (e.g. an Approver's PR approval plus a note in the governing spec).
- For changes with **wide product impact** that may not meet the high-impact bar, contributors (and assisting AIs) are encouraged to ask whether Patrick Fuchs should be consulted before proceeding — a lightweight check, not a hard gate.
- **Principle overrides** (waiving a constitution principle for a specific, well-defined scenario) follow the constitution's override discipline: a human expert invokes it explicitly, the consequences are surfaced and approved, and the scoped override + reasoning are recorded in the governing spec.
