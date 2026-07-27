# Phase 33: Profit Margin Tracking - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-27
**Phase:** 33-profit-margin-tracking
**Areas discussed:** Revenue definition, Estimated-revenue labeling, Incomplete-data flag semantics, Margin presentation & surfaces, Compute strategy

---

## Revenue Definition

### What is the revenue source rule for margin?

| Option | Description | Selected |
|--------|-------------|----------|
| Invoices, else approved quote | Sum of invoice totals; approved-quote fallback before any invoice exists; invoices win outright once any exist (PITFALLS.md #3) | ✓ |
| Greater of invoiced or quoted | max() avoids mid-billing understatement but mixes actual and estimated revenue | |
| Invoices only | Purest but margins empty until billing starts | |

### Which invoice statuses count as revenue?

| Option | Description | Selected |
|--------|-------------|----------|
| All issued invoices | unpaid + partially_paid + paid — billed/accrual basis | ✓ |
| Paid only | Cash basis; conflates profitability with collections | |

### Which quote statuses qualify for the fallback?

| Option | Description | Selected |
|--------|-------------|----------|
| Approved only | Only an approved quote is a revenue commitment | ✓ |
| Approved or sent | Earlier but speculative signal | |

---

## Estimated-Revenue Labeling

| Option | Description | Selected |
|--------|-------------|----------|
| Label it explicitly | Caption like "Based on approved quote — not yet invoiced"; consistent with honest-data posture; Phase 36 AI needs the distinction | ✓ |
| Identical presentation | One number regardless of source | |

---

## Incomplete-Data Flag Semantics

### What triggers the flag? (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Unrated labor hours | Phase 32 unrated-seconds signal; labor understated until backdated rate | ✓ |
| Zero cost entries + zero labor | Pitfall 9 legacy case — revenue with no recorded cost would fabricate ~100% margin | ✓ |
| No revenue source | Not selected — absence of revenue means margin is simply absent, not flagged | |

### When flagged, does a partial number still display?

| Option | Description | Selected |
|--------|-------------|----------|
| Show partial number + flag | Best available number with the flag beside it (Phase 32 pattern) | ✓ |
| Flag only, suppress the number | Strictest reading; hides useful partial information | |

---

## Margin Presentation & Surfaces

### Where should margin live?

| Option | Description | Selected |
|--------|-------------|----------|
| Extend the Costs sections | Margin block in the finance-gated Costs sections from Phases 31/32, web + mobile | ✓ |
| Separate Margin card | More prominence but splits financial info pre-Phase-35 | |

### How should the figure be presented?

| Option | Description | Selected |
|--------|-------------|----------|
| Both $ and % | e.g. "$4,200 · 21%"; Phase 36 AI speaks in percentages | ✓ |
| Dollars primary, % on detail | Hides the cross-job-comparable number | |
| Percent primary | Abstracts away real money | |

---

## Compute Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Computed-on-read | Query-time derivation matching Phase 32; revisit caching in Phase 35 | ✓ |
| Denormalized cache now | Invalidation complexity for load that doesn't exist yet | |

---

## Claude's Discretion

- API shape (extend breakdown endpoints vs sibling margin endpoints); serialization
- Percentage precision, zero-revenue division handling
- Exact flag/label/no-revenue copy (Phase 33 UI-SPEC pass locks strings)
- revenue_basis representation in API responses
- Bounded revenue aggregation query design

## Deferred Ideas

- Denormalized/cached margin summaries (Phase 35 if needed)
- Cash-basis (paid-only) margin view as a future toggle
