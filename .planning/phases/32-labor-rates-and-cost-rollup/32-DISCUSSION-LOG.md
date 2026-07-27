# Phase 32: Labor Rates and Cost Rollup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-26
**Phase:** 32-labor-rates-and-cost-rollup
**Areas discussed:** Labor cost derivation mechanics, Missing-rate handling, Time-tracking scope, Rates UI & itemized view details

---

## Labor Cost Derivation Mechanics

### How should labor cost be derived from time entries?

| Option | Description | Selected |
|--------|-------------|----------|
| Computed-on-read | Calculated at query time: duration × rate looked up by work date from append-only labor_rates. No recompute machinery; adjustments auto-consistent | ✓ |
| Materialized cost rows | CostEntry written on clock-out with snapshotted rate (PITFALLS.md #7 approach); needs recompute on adjustments/backdating | |

### Should backdated effective dates be allowed?

| Option | Description | Selected |
|--------|-------------|----------|
| Allow backdating | Forgotten rates can be entered late; labor for past days fills in retroactively; deterministic under computed-on-read | ✓ |
| Today/future only | Stricter immutability but no way to fix setup mistakes | |

### Should in-progress sessions count toward labor cost?

| Option | Description | Selected |
|--------|-------------|----------|
| Completed sessions only | Only clocked-out entries with final duration_seconds; totals never fluctuate mid-shift | ✓ |
| Include running sessions | Live elapsed-so-far cost; totals shift by the minute | |

---

## Missing-Rate Handling

### What should cost views show for tracked time with no effective rate?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit 'no rate' flag | Rated amount + visible "N hrs unrated" indicator; feeds Phase 33 incomplete-data flag | ✓ |
| Treat as $0 silently | Simplest but fabricates misleading totals (PITFALLS.md #9) | |
| Exclude those hours entirely | Hour counts would disagree with time-tracking screens | |

### How should the unburdened nature of labor cost be flagged?

| Option | Description | Selected |
|--------|-------------|----------|
| Info tooltip/note on labor rows | Tooltip (web) / caption (mobile): wage cost only, excludes payroll tax/insurance/overhead | ✓ |
| Explicit label in the text | "Labor (unburdened)" everywhere; noisier | |
| One-time banner per view | Dismissible; caveat gone after dismissal | |

---

## Time-Tracking Scope

### Job-only labor vs trade-scope time tracking for v4.0?

| Option | Description | Selected |
|--------|-------------|----------|
| Job-only for v4.0 | Existing job time entries; project labor via job→project link; no schema change or new clock-in surfaces | ✓ |
| Add trade-scope time tracking | TimeEntry trade-scope anchor + mobile clock-in; substantial new capability | |

### What should trade-scope views show for the labor category?

| Option | Description | Selected |
|--------|-------------|----------|
| Note: tracked at job level | Labor row present with honest explanation; consistent with missing-data posture | ✓ |
| Omit the labor row entirely | Inconsistent four-category breakdown; viewers may assume $0 | |

---

## Rates UI & Itemized View Details

### Where should rate management live?

| Option | Description | Selected |
|--------|-------------|----------|
| Web Team page only | Per Phase 30 D-07; one audited sensitive surface | ✓ |
| Web Team page + mobile admin | Second sensitive surface to build/gate/audit | |

### How should the itemized category breakdown be presented?

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing Costs sections | Category totals added to Phase 31 sections on job/scope/project screens | ✓ |
| Dedicated breakdown view | Separate tab/screen; splits cost info across surfaces | |

### Should the breakdown ship on both web and mobile?

| Option | Description | Selected |
|--------|-------------|----------|
| Both web and mobile | Matches Phase 31 pattern; labor figures from API, no local rate computation | ✓ |
| Web only this phase | Mobile parity becomes debt | |

---

## Claude's Discretion

- Rate-editor UX details (validation, future-dated rates, duplicate effective_from, history layout)
- API shape for breakdown totals; Decimal-as-string serialization
- Timezone convention for work-date mapping
- Derivation query/index design
- Mobile breakdown fetch/cache approach (online rollup pattern)

## Deferred Ideas

- Trade-scope/task-level time tracking (own future phase)
- Mobile rate management
- Burden rates/multiplier (explicitly out of v4.0; PITFALLS.md #2 documents the future design)
