# Phase 35: Web Financial Dashboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-28
**Phase:** 35-web-financial-dashboard
**Areas discussed:** Margin trend definition, Dashboard structure & navigation, Chart content & company rollup, Performance & caching, Incomplete data in aggregates, Attention-list ranking, Date-range & filtering

---

## Margin Trend Definition

### Time-axis source

| Option | Description | Selected |
|--------|-------------|----------|
| Reconstruct from dated records | Cumulative margin from incurred_date / work days / invoice-quote dates; retroactive from day one; no new tables | ✓ |
| Start a snapshot table now | Chart empty at launch; history unbackfillable | |
| Both | Most machinery for marginal benefit | |

### Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Monthly | Construction rhythms; meaningful points; small bucket counts | ✓ |
| Weekly | Noisy for long projects | |
| Adaptive | Two code paths | |

---

## Performance & Caching

| Option | Description | Selected |
|--------|-------------|----------|
| Computed-on-read | Bounded queries; add a measured performance test to settle Phase 33 D-11 with data | ✓ |
| Denormalized cache now | Invalidation machinery for unmaterialized load | |

---

## Dashboard Structure & Navigation

### Navigation

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated 'Financials' nav item | Sibling to Reports, finance.view-only, route guard; clean D-06 boundary | ✓ |
| Gated tab inside Reports | Mixes gated content into an ungated route | |

### Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Company overview + project drill-down | /financials → /financials/[projectId]; glance→detail | ✓ |
| Single page with project picker | No company glance view; awkward deep links | |

---

## Chart Content & Company Rollup

| Option | Description | Selected |
|--------|-------------|----------|
| Full recommended set | Company: tiles + per-project bars + attention list; Project: trend + per-scope bars + category mix | ✓ |
| Minimal SC-mandated set | Thin rollup page | |

---

## Incomplete Data in Aggregates

| Option | Description | Selected |
|--------|-------------|----------|
| Include + count badge | Flagged projects roll in; tiles badge "N projects with incomplete data" | ✓ |
| Exclude from portfolio margin | Portfolio no longer reflects the actual company | |

## Attention-List Ranking

| Option | Description | Selected |
|--------|-------------|----------|
| Overrun > warning > incomplete | Ordered tiers from shipped signals; worst % over first; show all | ✓ |
| Composite severity score | New judgment formula — Phase 36 AI territory | |

## Date-Range & Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| Trend window only | Range selector on the trend chart; totals/budget-vs-actual stay lifetime | ✓ |
| Filter everything | Windowed spend vs lifetime budget = nonsense comparisons | |
| No filtering this phase | Trend loses its most natural control | |

---

## Claude's Discretion

- Trend bucket-edge + revenue-basis-per-bucket semantics; endpoint shapes; latency budget number
- Chart composition (Recharts config, states per Reports conventions); attention-row content; route-guard mechanics

## Deferred Ideas

- Snapshot/cache layer (only if the performance test fails)
- Composite attention scoring (Phase 36)
- Mobile financial dashboard; date-filtered totals
