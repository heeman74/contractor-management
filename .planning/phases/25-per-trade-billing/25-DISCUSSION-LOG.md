# Phase 25: Per-Trade Billing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 25-per-trade-billing
**Areas discussed:** Quote scope transition, Invoice generation, Project-level aggregation, Progress billing
**Mode:** --auto (all decisions auto-selected with recommended defaults)

---

## Quote Scope Transition

| Option | Description | Selected |
|--------|-------------|----------|
| Add trade_scope_id FK to existing tables | Nullable FK preserves backwards compat with job-scoped quotes | ✓ |
| New trade_quotes table | Separate entity, clean separation but duplicate schema | |
| Replace job_id with trade_scope_id | Breaking change, requires data migration | |

**User's choice:** [auto] Add trade_scope_id FK (recommended — least disruption, dual-scope support)
**Notes:** Existing job-scoped quotes continue to work. New quotes default to trade-scope-scoped.

---

## Invoice Generation from Completed Work

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-populate from completed tasks | Tasks → labor line items with hours | ✓ |
| Manual line item entry only | GC types everything manually | |
| Hybrid with suggestions | Show suggestions, GC confirms each | |

**User's choice:** [auto] Auto-populate from completed tasks (recommended — saves GC time, editable before send)
**Notes:** GC can always edit/add/remove line items after auto-population.

---

## Project-Level Aggregation

| Option | Description | Selected |
|--------|-------------|----------|
| Read-only aggregation views | Sum trade quotes/invoices, no editing at project level | ✓ |
| Editable project-level documents | Separate project quote/invoice entities | |

**User's choice:** [auto] Read-only aggregation (recommended — simpler, no data duplication)
**Notes:** Accessible from project detail screen as new sections.

---

## Progress Billing / Milestones

| Option | Description | Selected |
|--------|-------------|----------|
| Billing milestones table | GC defines milestones per trade scope with percentages | ✓ |
| Percentage-based without milestones | GC enters arbitrary percentage at invoice time | |
| Task-completion-based | Auto-calculate from task completion percentage | |

**User's choice:** [auto] Billing milestones table (recommended — structured, prevents double-billing)
**Notes:** Each milestone has name, percentage, description. Marked as "invoiced" when used.

---

## Claude's Discretion

- Migration strategy for nullable FK additions
- Project-level summary screen layout
- Billing milestone CRUD UI pattern
- Invoice number sequence handling
- Work item → line item mapping format
