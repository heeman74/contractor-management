# Phase 31: Actual Cost Capture - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 31-actual-cost-capture
**Areas discussed:** Platform surface, Entry point, Receipts, Edit/delete

---

## Platform surface

| Option | Description | Selected |
|--------|-------------|----------|
| Mobile + Web both | Field capture on mobile (offline-first) AND desk entry on web; shared gated backend | ✓ |
| Mobile first only | Mobile-only capture this phase; web viewing deferred to Phase 35 | |
| Web first only | Web-only bookkeeping entry; mobile deferred | |

**User's choice:** Mobile + Web both
**Notes:** Most complete scope — backend + Flutter + Next.js.

---

## Entry point

| Option | Description | Selected |
|--------|-------------|----------|
| On job & trade-scope detail | Inline "Add cost" + costs list on existing job/scope detail screens | |
| Dedicated Costs section | New standalone project-level Costs screen with anchor picker | |
| Both | Inline on job/scope detail + project-level Costs tab aggregating them | ✓ |

**User's choice:** Both
**Notes:** Most discoverable; costs sit next to work AND aggregate at project level.

---

## Receipts

| Option | Description | Selected |
|--------|-------------|----------|
| Optional, one photo | Single optional receipt_url via authenticated /files | |
| Optional, multiple photos | Zero-to-many receipts per entry (separate attachment rows) | ✓ |
| Required, one photo | Every entry must have a receipt | |

**User's choice:** Optional, multiple photos
**Notes:** Flexible for multi-page receipts; new `cost-receipts` /files category.

---

## Edit/delete

| Option | Description | Selected |
|--------|-------------|----------|
| Edit + delete (soft) | Owner/PM can correct or soft-delete entries | ✓ |
| Delete only | Immutable; mistakes deleted and re-added | |
| Neither (record + view only) | Strictly the success criteria; edit/delete deferred | |

**User's choice:** Edit + delete (soft)
**Notes:** Practical for corrections; soft-delete consistent with the app.

## Claude's Discretion

- Receipt table shape, migration numbering, indexes
- Mobile Drift/sync-handler shape; project Costs tab create-path inclusion
- Web finance API client location, component structure, gating call sites
- Form UX (date default, category picker, amount validation), list ordering

## Deferred Ideas

- Analytics/totals-by-category beyond simple list + rollup (Phases 33/35)
- Full edit-history audit trail (soft-delete only this phase)
- Bulk import / OCR receipt scanning
