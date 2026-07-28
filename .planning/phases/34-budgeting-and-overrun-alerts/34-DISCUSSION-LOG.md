# Phase 34: Budgeting and Overrun Alerts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-28
**Phase:** 34-budgeting-and-overrun-alerts
**Areas discussed:** Overrun-alert semantics, Quote-revision → budget mechanics, Budget UI & breakdown scope, Alert delivery & lifecycle, Budget edit/delete semantics, Negative revision deltas, Alert content & granularity

---

## Overrun-Alert Semantics

### What alerting model should Phase 34 ship?

| Option | Description | Selected |
|--------|-------------|----------|
| Static 80/100 + strict dedup | Fire once per threshold crossing per budget; Pitfall 6 noise is repeated alerts, dedup solves it; velocity projection → Phase 36 AI | ✓ |
| Static + projected-overrun warning | Burn-rate projection with front-loading heuristics; large design surface | |

### When should thresholds be evaluated?

| Option | Description | Selected |
|--------|-------------|----------|
| On cost mutation + nightly sweep | Synchronous check on cost writes + APScheduler sweep to catch derived-labor drift | ✓ |
| Nightly sweep only | Huge sub invoice waits until tomorrow | |
| On mutation only | Labor-driven crossings never alert | |

---

## Quote-Revision → Budget Mechanics

### Which budget does an approved revision adjust?

| Option | Description | Selected |
|--------|-------------|----------|
| Scope→scope, job→project | Mirrors D-05/D-12 traversal; jobs without project adjust nothing; project quotes → project budget | ✓ |
| Scope-anchored quotes only | Job-quoting GCs get no BUDG-04 behavior | |

### No budget on the target?

| Option | Description | Selected |
|--------|-------------|----------|
| No-op, nothing to adjust | Owners opt into budgeting explicitly; no auto-created ceilings | ✓ |
| Auto-create at quote total | Surprising silent financial ceilings | |

---

## Budget UI & Breakdown Scope

### Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Extend the Costs sections | Budget rows join the finance-gated sections with inline "Set budget" | ✓ |
| Dedicated Budgets view | Splits surfaces pre-Phase-35 | |

### Per-category breakdown in v4.0 UI?

| Option | Description | Selected |
|--------|-------------|----------|
| Total-only in v4.0 | Schema rows stay dormant; no requirement backs category budgeting | ✓ |
| Full per-category editor | More validation UI, no requirement | |

### Who edits, where?

| Option | Description | Selected |
|--------|-------------|----------|
| finance.manage, web-edit + both-view | Matches rates precedent; mobile views via API | ✓ |
| Edit on both platforms | Second sensitive write surface | |

---

## Alert Delivery & Lifecycle

### Re-arm on budget change?

| Option | Description | Selected |
|--------|-------------|----------|
| Re-arm on budget increase | Raised budget clears fired thresholds; fresh alerts against new total | ✓ |
| Fire once forever | Raised-then-blown budgets stay silent | |

---

## Budget Edit/Delete Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Full edit + soft-delete, no floor | Any positive amount incl. below spend (honest instant alerts); soft-delete stops evaluation | ✓ |
| Block lowering below spend | Forbids a legitimate owner action | |

## Negative Revision Deltas

| Option | Description | Selected |
|--------|-------------|----------|
| Apply negative deltas too | Signed delta; budget tracks committed revenue both directions | ✓ |
| Positive deltas only | Stale ceilings after descoping | |

## Alert Content & Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Independent per budget | Each budget alerts against its own thresholds; copy names entity/threshold/figures | ✓ |
| Scope crossings roll up | Doubles alert volume — Pitfall 6 trap | |

---

## Claude's Discretion

- Threshold-state storage shape and re-arm reset mechanics
- alert_type names, copy strings (UI-SPEC pass), FCM payload/deep-link
- Spend computation reuse from Phase 33 queries; scope-spend consistency with the scope Costs display
- API shape (additive extension per mobile parsing contract); migration numbering; sweep scheduling

## Deferred Ideas

- Velocity/trend projection with front-loading heuristics (Phase 36 AI)
- Per-category budget UI + category thresholds
- Mobile budget editing
- Scope→project rollup notices
