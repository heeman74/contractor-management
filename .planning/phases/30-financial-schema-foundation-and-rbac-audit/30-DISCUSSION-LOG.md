# Phase 30: Financial Schema Foundation and RBAC Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-24
**Phase:** 30-financial-schema-foundation-and-rbac-audit
**Areas discussed:** Permission granularity, Cost anchor & rollup, Legacy revenue reports, Labor rate handling, Budget shape, Cost categories, Audit depth

---

## Permission granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Coarse: view + manage | finance.view + finance.manage; 2 clean toggles | ✓ |
| Per-domain keys | ~7 keys (costs/budgets/rates/margins split) | |
| Fine-grained | 12+ keys, every domain × view/edit/delete | |

**User's choice:** Coarse view + manage (recommended)

## Rates permission

| Option | Description | Selected |
|--------|-------------|----------|
| Separate rates key | finance.rates.manage as its own toggle | ✓ |
| Fold into finance.manage | One less key | |

**User's choice:** Separate rates key (recommended)

## Cost anchor

| Option | Description | Selected |
|--------|-------------|----------|
| Job OR trade scope | Polymorphic XOR pair like Quote/Invoice | ✓ |
| Trade scope only | Standalone jobs couldn't carry costs | |
| Job only | Project-level costs get awkward | |

**User's choice:** Job OR trade scope (recommended)

## Rollup rule

| Option | Description | Selected |
|--------|-------------|----------|
| Follow the links | Trade-scope costs + costs of jobs with job.project_id set; orphans job-level only | ✓ |
| Require project anchor | Orphan jobs blocked from costs until linked | |

**User's choice:** Follow the links (recommended)

## Legacy revenue reports

| Option | Description | Selected |
|--------|-------------|----------|
| Admins keep revenue | finance.* gates only new money data (costs/margins/budgets/rates) | ✓ |
| Gate everything financial | Admins lose reports/invoice amounts without finance.view | |

**User's choice:** Admins keep revenue (recommended)

## Rates UI location

| Option | Description | Selected |
|--------|-------------|----------|
| Team page, gated | Rate field/history per member, finance.rates.manage only | ✓ |
| Separate Financials settings | New surface before Phase 35 exists | |

**User's choice:** Team page, gated (recommended)

## Own-rate visibility

| Option | Description | Selected |
|--------|-------------|----------|
| No — finance holders only | Zero per-user exceptions to audit | ✓ |
| Yes — own rate visible | More transparent, more leak surface | |

**User's choice:** No — finance holders only (recommended)

## Budget shape

| Option | Description | Selected |
|--------|-------------|----------|
| Total + optional breakdown | One total; optional per-category rows summing ≤ total | ✓ |
| Single total only | Categories would need mid-milestone migration | |
| Per-category required | Heavier data entry | |

**User's choice:** Total + optional breakdown (recommended)

## Cost categories

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed enum | labor/materials/subcontractor/other as DB CHECK | |
| Company-editable list | Per-company lookup table (trade-catalog pattern) | ✓ |

**User's choice:** Company-editable list (against recommendation — user wants per-company flexibility)
**Notes:** Follow-up locked built-in handling: 4 seeded protected system categories (renamable, non-deletable; labor reserved for derived labor cost), custom categories allowed beyond.

## Audit depth

| Option | Description | Selected |
|--------|-------------|----------|
| Tests + shared plumbing | Regression tests + permission-aware alert filter + AI finance-scrub helper now | ✓ |
| Tests + documented pattern only | Later phases build their own filtering | |

**User's choice:** Tests + shared plumbing (recommended)

## Claude's Discretion

- Table/column naming, indexes, migration numbering
- Matrix UI grouping for finance keys
- Regression-test structure
- Category/matrix seeding + backfill mechanics

## Deferred Ideas

- Fine-grained per-domain finance keys (future bookkeeper-style role)
- Worker self-service rate visibility (future employee portal)
