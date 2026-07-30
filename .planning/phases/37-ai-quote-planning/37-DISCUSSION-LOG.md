# Phase 37: AI Quote Planning - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-29
**Phase:** 37-ai-quote-planning
**Areas discussed:** History matching & grounding, Confidence indicator, Review gate mechanics, Variance view & feedback loop, Cold start, Trigger placement & permissions, Regeneration & edit persistence

---

## History Matching

| Option | Description | Selected |
|--------|-------------|----------|
| Same trade, completed work | Match on trade/field against completed same-trade work using ACTUAL costs + variance; no new taxonomy | ✓ |
| Trade + project-size band | More precise but halves samples, and thin samples are what confidence must punish | |
| All company history | Cross-trade averages produce unrecognizable numbers | |

## Grounding

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, with derived rates allowed | Reuse ai_grounding; allowed set = precomputed historical rates/quantities the AI may cite | ✓ |
| Advisory only, no blocking | SC1's "grounded in company cost history" becomes unenforceable | |

## AI Output Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Full line items + cited basis | Exact QuoteLineItem shape plus a basis string naming the history | ✓ |
| Quantities and prices only | SC1 says pre-fill line items; user would still break down items by hand | |

---

## Confidence

### Signal

| Option | Description | Selected |
|--------|-------------|----------|
| Sample count + spread | Both axes, computed in code, three bands | ✓ |
| Sample count only | 12 wildly disagreeing comparables would read as high confidence | |
| AI self-assessed | Unverifiable self-report — the exact thing this milestone's discipline prevents | |

### Display

| Option | Description | Selected |
|--------|-------------|----------|
| Bands + basis string | Three-band chip (FinanceFlagChip vocabulary) plus the cited basis | ✓ |
| Numeric score | Implies rigor the sample doesn't support | |

---

## Review Gate (SC2)

| Option | Description | Selected |
|--------|-------------|----------|
| Per-line ack, send blocked until clear | Backend-enforced on the send transition, not UI-hidden | ✓ |
| One bulk approval | A single click over 12 lines is the rubber-stamp SC2 prevents | |
| UI-only warning | Makes SC2 unverifiable by test | |

---

## Variance

### Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Financials drill-down + quote detail | Both surfaces exist; no new nav | ✓ |
| New Variance page | A fourth financial surface right after the dashboard landed | |
| Quote detail only | SC4 requires project/scope level too | |

### "Completed" definition

| Option | Description | Selected |
|--------|-------------|----------|
| Invoiced work | Both halves settled; reuses Phase 33 revenue-basis logic | ✓ |
| Lifecycle status complete | A status-complete job with no invoice has no billed figure | |

### Feedback loop

| Option | Description | Selected |
|--------|-------------|----------|
| Variance-adjusted historical rates | Rates from ACTUAL costs self-correct; payload carries variance for the basis text | ✓ |
| Explicit correction factor | Compounds with the actual-cost basis; silent inflation | |

---

## Cold Start

| Option | Description | Selected |
|--------|-------------|----------|
| Refuse honestly below a threshold | AI never called; UI says why and what would create history | ✓ |
| Suggest with low confidence + caveat | SC1 would be false for those lines; validator has nothing to validate against | |

## Trigger & Gating

| Option | Description | Selected |
|--------|-------------|----------|
| Draft quote editor, finance.view + quote-manage | Cost-derived figures require the Phase 30 finance boundary | ✓ |
| Quote-manage only | Cost-derived unit prices would reach non-finance users | |

## Regeneration

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate only untouched lines | Accepted/edited lines preserved; edited lines keep an AI-originated marker | ✓ |
| Regenerate replaces everything | Silently discards user edits | |

---

## Claude's Discretion

- Minimum comparable threshold and band boundaries (named constants)
- Suggestion persistence shape (review-state columns vs side table); migration numbering
- Prompt/payload design satisfying the closed-set obligation; comparable-matching query design
- Variance presentation and UI-SPEC strings/states

## Deferred Ideas

- Project-size bucketing; explicit correction multipliers; cross-company benchmarks; mobile quote AI; burden-rate-aware pricing; a trained feedback model
