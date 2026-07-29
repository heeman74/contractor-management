# Phase 36: AI Profitability Analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-29
**Phase:** 36-ai-profitability-analysis
**Areas discussed:** Data-completeness gate, Erosion definition & finding types, Grounding enforcement, Alert volume & lifecycle, Candidate-signal thresholds, AI model & cost posture, Corrective-action shape

---

## Data-Completeness Gate

| Option | Description | Selected |
|--------|-------------|----------|
| Skip flagged/no-data projects | Active + revenue + cost data + no incomplete flag (shipped Phase 33 signals); skipped projects logged, never alerted | ✓ |
| Analyze all, caveat flagged | AI would "detect erosion" that is missing data — Pitfall 9 noise | |
| Minimum entry/age thresholds | New magic numbers where flags already encode quality | |

## Erosion Detection

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic candidates + AI analysis | Code computes signals; only candidates reach the AI, which confirms/dismisses + writes the action | ✓ |
| AI judges from full aggregates | Untestable detection, token cost on healthy projects, prompt-dependent noise | |

## Finding Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Margin-erosion family only | One ai_profitability type; budget alerts stay Phase 34's | ✓ |
| Broader finding menu | Overlaps shipped alerts, multiplies volume | |

---

## Grounding Enforcement (SC3)

| Option | Description | Selected |
|--------|-------------|----------|
| Validate-and-block with one retry | Every figure matched against the payload; unmatched → retry once with the error, then drop + log | ✓ |
| Strip or correct figures | Silently rewriting prose can garble the action | |
| Template findings, prose only | Actions like "cut spend ~$2k" become unphrasable | |

## Dedup

| Option | Description | Selected |
|--------|-------------|----------|
| Fingerprint dedup, re-fire on change | project+signal+severity band; once until clears-and-recurs or worsens | ✓ |
| Alert every night | Pitfall 6 alert fatigue | |

## Surfaces

| Option | Description | Selected |
|--------|-------------|----------|
| Alert channels + project financials page | AlertPanel + FCM + latest finding in context on /financials/[projectId] | ✓ |
| Alert channels only | The corrective action lives only in a transient feed | |

---

## Candidate Thresholds

| Option | Description | Selected |
|--------|-------------|----------|
| 5pts/2 buckets + absolutes | ≥5pt decline across last 2 monthly buckets, OR negative margin, OR ≥5pts below quote-implied margin; named constants | ✓ |
| Stricter (10pts/negative only) | Misses slow-bleed erosion | |
| Let AI set sensitivity | Reintroduces untestable detection | |

## Model & Cost Posture

| Option | Description | Selected |
|--------|-------------|----------|
| Same as Phase 26 cron + caps | Reuse checklist job's model/retry; per-project token ceiling + per-company findings cap | ✓ |
| Stronger model for finance | Figures are code-supplied; higher spend for prose | |

## Corrective-Action Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Structured: target + direction + basis | Names a payload target, a direction, cites the motivating figure; ≤280 chars in alert, paragraph on page | ✓ |
| Free-form suggestion | "Review your costs" is ignorable | |

---

## Claude's Discretion

- alert_type names, severity bands, fingerprint encoding, findings schema/retention
- Prompt + validator implementation; cron scheduling; UI composition (UI-SPEC pass); circuit-breaker values

## Deferred Ideas

- Broader finding menu; sensitivity tuning UI; mobile findings UI; burden-rate-aware analysis
