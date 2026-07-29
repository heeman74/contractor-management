# Phase 36: AI Profitability Analysis - Context

**Gathered:** 2026-07-29
**Status:** Ready for planning

<domain>
## Phase Boundary

A nightly AI pass analyzes every eligible active project's financial health,
flags margin erosion with a specific suggested corrective action, and delivers
finance-gated alerts (dashboard + FCM) plus an in-context finding on the
project financials page — with every dollar figure in a finding validated
against real tool-sourced values before publication. (FINAI-01, FINAI-02.)

All financial inputs are the shipped Phase 33–35 aggregates (margin, trend
buckets, budget position, incomplete flags). This phase adds: candidate
detection, the AI analysis job, the grounding validator, finding persistence +
dedup, alert emission, and the findings UI.

NOT in this phase: AI quote planning (37), budget threshold alerts (shipped in
34 — not duplicated), burden rates, any change to margin/budget/trend math,
mobile UI beyond the FCM push.

</domain>

<decisions>
## Implementation Decisions

### Eligibility gate (resolves the STATE.md completeness-threshold blocker)
- **D-01:** AI analyzes only projects that are **active** AND have a revenue
  source AND at least some cost data AND **no incomplete-data flag** — all
  shipped Phase 33 signals; no new numeric thresholds invented. Skipped
  projects are recorded in the nightly run log with the skip reason, never
  alerted. The AI never reasons over understated costs (research Pitfall 9).

### Detection (deterministic candidates + AI analysis)
- **D-02:** Code computes candidate signals from shipped data; ONLY candidate
  projects go to the AI. The AI confirms/dismisses each candidate and writes
  the finding narrative + corrective action. Detection is testable and
  noise-bounded; the AI adds judgment and phrasing, not detection.
- **D-03:** **Candidate thresholds (named constants, tunable):**
  1. Margin % declined ≥ **5 percentage points** across the last **2 monthly
     trend buckets** (Phase 35 as-of buckets), OR
  2. Margin is **negative**, OR
  3. Billed margin sits ≥ **5 points below** the approved-quote-implied margin
     for the same anchor set.
- **D-04:** **One finding family:** `ai_profitability`, covering the erosion
  candidates. Budget threshold alerts remain Phase 34's — the AI's corrective
  action may reference budget context but never duplicates those alerts.

### Grounding (SC3)
- **D-05:** **Validate-and-block with one retry.** A validator extracts every
  dollar and percent figure from the AI's finding text and matches each
  against the tool payload's values. A finding citing an unmatched figure is
  rejected and retried once with the validation error appended; on second
  failure it is dropped and logged — never published. The unburdened-labor
  labeling (Pitfall 2) and estimated-revenue basis travel WITH the payload so
  the AI's analysis is honest about data quality.

### Alert lifecycle
- **D-06:** **Fingerprint dedup, re-fire on change.** Each finding carries a
  fingerprint (project + candidate signal + severity band). It alerts once
  (DashboardAlert + FCM); subsequent nights with the same fingerprint update
  the stored finding silently. A new alert fires only when the condition
  clears and recurs, or worsens into a different band. Phase 34's exactly-once
  discipline applied to AI findings.
- **D-07:** Delivery via the shipped finance-gated channels: new financial
  alert type(s) registered in `FINANCIAL_ALERT_TYPES` (permission filter comes
  free), FCM to `finance.view` holders only. Findings must also pass through
  the Phase 30 `finance_scrub` posture — no finance data reaches non-finance
  roles anywhere.

### Findings surface
- **D-08:** Findings render in the alert channels AND the latest finding (with
  its corrective action) renders on `/financials/[projectId]` so the action is
  visible in context. Web-only UI; mobile receives FCM pushes only (Phase 34
  precedent).

### Corrective action shape
- **D-09:** **Structured: target + direction + basis.** The action must name a
  concrete target from the payload (a category, scope, or rate situation), a
  direction (e.g., "renegotiate", "rebill", "backdate the missing rate"), and
  cite the payload figure motivating it — enforced by the prompt contract and
  the D-05 validator. ≤280 chars in the alert; full paragraph on the
  financials page. No "review your costs" filler.

### Model & cost posture
- **D-10:** Reuse the Phase 26 cron job's configured non-streaming Claude model
  and retry envelope. Circuit breakers: candidates only (already bounded by
  D-02/D-03), a per-project token ceiling, and a per-company nightly findings
  cap — all named constants. No new model-config surface.

### Claude's Discretion
- Exact alert_type name(s), severity-band definitions, fingerprint encoding,
  finding persistence schema (table shape, retention).
- Prompt design (payload format, tool-use vs single completion, dismissal
  contract), validator implementation (Decimal figure extraction/matching
  rules, tolerance for formatted-vs-raw representations).
- Cron scheduling relative to the 05:00 budget sweep and 06:00 checklists;
  idempotency/rerun semantics.
- Findings UI composition on the financials page (per 32-35 UI conventions —
  a Phase 36 UI-SPEC pass locks strings/states).
- Circuit-breaker constant values; run-log shape.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Financial data inputs (everything the AI sees comes from these)
- `backend/app/features/finance/portfolio_service.py` + `portfolio_repository.py` — company/project aggregates (Phase 35)
- `backend/app/features/finance/trend_math.py` — monthly as-of buckets (the D-03 trend signal source)
- `backend/app/features/finance/margin_math.py`, `budget_math.py` — margin/threshold semantics
- `.planning/phases/33-profit-margin-tracking/33-CONTEXT.md` — incomplete-flag semantics (D-05..D-07), revenue basis
- `.planning/phases/35-web-financial-dashboard/35-CONTEXT.md` — trend reconstruction, D-11 live thresholds, attention tiers

### AI infrastructure (patterns to reuse)
- Phase 26 nightly cron AI: backend cron/scheduler feature (`_run_for_all_companies`, non-streaming Claude API, idempotent upserts) — see `.planning/phases/26-ai-daily-checklists-and-monitoring-dashboard/` summaries and the shipped checklist job code (`backend/app/features/checklists/` or equivalent)
- `backend/app/core/` AI client config (model id, retry envelope from Phase 21/26)
- Phase 30 D-11 `finance_scrub` helper + `FINANCIAL_ALERT_TYPES` (`backend/app/features/dashboard/alert_types.py`)

### Alert plumbing (Phase 34)
- `backend/app/features/finance/budget_service.py` — evaluate/claim/alert emission + FCM targeting patterns to mirror
- `backend/app/features/dashboard/` — permission-filtered alerts; migration precedent for new alert types (0035)
- `backend/app/features/notifications/` — FCM dispatch to finance.view holders

### Research
- `.planning/research/PITFALLS.md` — #2 (unburdened labeling to AI), #9 (legacy margins poisoning AI), #6 (alert noise), performance note (feed AI pre-computed aggregates, never raw rows)

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — FINAI-01, FINAI-02
- `.planning/ROADMAP.md` — Phase 36 goal + 3 success criteria

### UI surfaces
- `web/src/app/(dashboard)/financials/[projectId]/` — where the finding renders (D-08)
- `web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx` — alert rendering
- Phase 32-35 UI-SPECs — copy/state conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 35's project aggregates + trend buckets — the complete AI payload; no new financial queries needed beyond composition
- Phase 34's alert emission + FCM targeting + exactly-once claim discipline — the fingerprint dedup mirrors it
- Phase 26's cron AI job structure — the nightly analysis job is its sibling
- `FINANCIAL_ALERT_TYPES` + permission-aware filter — register the new type(s), filtering comes free (needs the alert_type CHECK constraint migration, 0035 precedent)

### Established Patterns
- Non-streaming Claude API for batch (Phase 26); asyncio.create_task fire-and-forget FCM; Decimal-as-string; soft-delete; named constants
- Honest-data posture: basis labels and unburdened captions travel with the data — into the AI payload and out through findings

### Integration Points
- New migration: alert_type constraint expansion + findings table
- Nightly scheduler registration (after the 05:00 budget sweep; before/after 06:00 checklists — discretion)
- Phase 37 (AI quote planning) will reuse the grounding-validator pattern — build it as a reusable module, not inline

</code_context>

<specifics>
## Specific Ideas

- Keystone tests: (1) a finding citing a figure absent from the payload is blocked after one retry and never published; (2) the same erosion fingerprint alerts exactly once across three nightly runs, then re-fires when it worsens a band; (3) non-finance roles see no AI findings anywhere (dashboard, FCM, financials page — and finance_scrub keeps them out of chat/checklist AI surfaces)
- Corrective-action example shape: "Plumbing scope materials are $3,200 over the approved quote's allowance — rebill the change order or renegotiate supplier pricing before drywall starts"
</specifics>

<deferred>
## Deferred Ideas

- Broader AI finding menu (budget risk, unrated-labor nudges, estimated-revenue staleness) — revisit after erosion findings prove signal quality
- AI sensitivity control / per-company threshold tuning UI
- Mobile findings UI — FCM-only this milestone
- Burden-rate-aware analysis — blocked on the deferred burden-rate feature

</deferred>

---

*Phase: 36-ai-profitability-analysis*
*Context gathered: 2026-07-29*
