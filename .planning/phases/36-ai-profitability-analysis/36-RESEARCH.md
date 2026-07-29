# Phase 36: AI Profitability Analysis - Research

**Researched:** 2026-07-28
**Domain:** Nightly batch AI analysis over shipped financial aggregates; deterministic candidate detection; LLM output grounding/validation; exactly-once alert dedup; finance-gated delivery
**Confidence:** HIGH (this is a codebase-integration phase — nearly every finding is verified against shipped source with line references; the only MEDIUM/LOW items are flagged in Open Questions)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Eligibility gate (resolves the STATE.md completeness-threshold blocker)**
- **D-01:** AI analyzes only projects that are **active** AND have a revenue source AND at least some cost data AND **no incomplete-data flag** — all shipped Phase 33 signals; no new numeric thresholds invented. Skipped projects are recorded in the nightly run log with the skip reason, never alerted. The AI never reasons over understated costs (research Pitfall 9).

**Detection (deterministic candidates + AI analysis)**
- **D-02:** Code computes candidate signals from shipped data; ONLY candidate projects go to the AI. The AI confirms/dismisses each candidate and writes the finding narrative + corrective action. Detection is testable and noise-bounded; the AI adds judgment and phrasing, not detection.
- **D-03:** **Candidate thresholds (named constants, tunable):**
  1. Margin % declined ≥ **5 percentage points** across the last **2 monthly trend buckets** (Phase 35 as-of buckets), OR
  2. Margin is **negative**, OR
  3. Billed margin sits ≥ **5 points below** the approved-quote-implied margin for the same anchor set.
- **D-04:** **One finding family:** `ai_profitability`, covering the erosion candidates. Budget threshold alerts remain Phase 34's — the AI's corrective action may reference budget context but never duplicates those alerts.

**Grounding (SC3)**
- **D-05:** **Validate-and-block with one retry.** A validator extracts every dollar and percent figure from the AI's finding text and matches each against the tool payload's values. A finding citing an unmatched figure is rejected and retried once with the validation error appended; on second failure it is dropped and logged — never published. The unburdened-labor labeling (Pitfall 2) and estimated-revenue basis travel WITH the payload so the AI's analysis is honest about data quality.

**Alert lifecycle**
- **D-06:** **Fingerprint dedup, re-fire on change.** Each finding carries a fingerprint (project + candidate signal + severity band). It alerts once (DashboardAlert + FCM); subsequent nights with the same fingerprint update the stored finding silently. A new alert fires only when the condition clears and recurs, or worsens into a different band. Phase 34's exactly-once discipline applied to AI findings.
- **D-07:** Delivery via the shipped finance-gated channels: new financial alert type(s) registered in `FINANCIAL_ALERT_TYPES` (permission filter comes free), FCM to `finance.view` holders only. Findings must also pass through the Phase 30 `finance_scrub` posture — no finance data reaches non-finance roles anywhere.

**Findings surface**
- **D-08:** Findings render in the alert channels AND the latest finding (with its corrective action) renders on `/financials/[projectId]` so the action is visible in context. Web-only UI; mobile receives FCM pushes only (Phase 34 precedent).

**Corrective action shape**
- **D-09:** **Structured: target + direction + basis.** The action must name a concrete target from the payload (a category, scope, or rate situation), a direction (e.g., "renegotiate", "rebill", "backdate the missing rate"), and cite the payload figure motivating it — enforced by the prompt contract and the D-05 validator. ≤280 chars in the alert; full paragraph on the financials page. No "review your costs" filler.

**Model & cost posture**
- **D-10:** Reuse the Phase 26 cron job's configured non-streaming Claude model and retry envelope. Circuit breakers: candidates only (already bounded by D-02/D-03), a per-project token ceiling, and a per-company nightly findings cap — all named constants. No new model-config surface.

### Claude's Discretion
- Exact alert_type name(s), severity-band definitions, fingerprint encoding, finding persistence schema (table shape, retention).
- Prompt design (payload format, tool-use vs single completion, dismissal contract), validator implementation (Decimal figure extraction/matching rules, tolerance for formatted-vs-raw representations).
- Cron scheduling relative to the 05:00 budget sweep and 06:00 checklists; idempotency/rerun semantics.
- Findings UI composition on the financials page (per 32-35 UI conventions — a Phase 36 UI-SPEC pass locks strings/states).
- Circuit-breaker constant values; run-log shape.

### Deferred Ideas (OUT OF SCOPE)
- Broader AI finding menu (budget risk, unrated-labor nudges, estimated-revenue staleness) — revisit after erosion findings prove signal quality
- AI sensitivity control / per-company threshold tuning UI
- Mobile findings UI — FCM-only this milestone
- Burden-rate-aware analysis — blocked on the deferred burden-rate feature
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **FINAI-01** | AI analyzes each active project's financial health on a nightly schedule, flagging margin erosion with suggested corrective actions | § Architecture Patterns 1 (cron sibling of Phase 26), 2 (eligibility from shipped Phase 33/35 signals), 3 (candidate detector `profitability_math.py`), 6 (prompt + payload contract) |
| **FINAI-02** | Owner/PM receives finance-gated alerts for AI profitability findings | § Architecture Patterns 7 (alert_types registration + migration 0036), 8 (claim-first exactly-once + FCM to `finance.view` holders), 9 (findings endpoint + web mount behind `FinanceGate` **and** hook `enabled`) |
| **SC1** | Every active project analyzed nightly; erosion flagged with a specific suggested corrective action | § Architecture Patterns 1–3, 6; § Validation Architecture rows SC1 |
| **SC2** | Finance-gated alerts invisible without `finance.*` | § Architecture Patterns 7–9; keystone test `test_non_finance_sees_no_ai_findings_anywhere` |
| **SC3** | Every dollar figure traces to a real tool-sourced value, never an AI estimate | § Architecture Patterns 4–5 (grounding validator, closed allow-set); keystone test `test_unmatched_figure_blocked_after_one_retry` |
</phase_requirements>

---

## Summary

This phase adds **no new financial math and no new financial queries**. Everything the AI reasons over already ships: `PortfolioService._fetch_portfolio_inputs()` + `_project_figures()` produce a per-project `ProjectFinancialFigures` block (cost, resolved revenue + basis, quoted share, unrated seconds, full `MarginFigures`, anchored budgets) in a query count that is **constant in project count** — pinned by `test_company_rollup_query_count_is_constant_in_project_count`. `PortfolioService.margin_trend()` produces the D-03 as-of monthly buckets. All four D-01 eligibility signals are readable directly off that block. The work is therefore: (1) a pure candidate detector, (2) a nightly job that is a structural sibling of `run_morning_checklists`, (3) a reusable grounding validator, (4) a findings table with claim-first exactly-once alerting, (5) alert-type registration, (6) one endpoint + one web card.

Two areas need genuine new design. **The quote-implied-margin signal (D-03 #3) has no shipped helper and cannot use `anchor_revenues()`** — that function deliberately discards approved quotes at invoiced anchors (D-01 invoices-win-outright, `margin_math.py:212-216`), which is exactly the leg this signal needs. It must be built from the raw `(RevenueAnchor, DocumentAmounts)` rows, taking the first row per anchor (the query is newest-first), through `quoted_revenue()`. **The grounding validator's matching rule is the phase's real risk**: the honest way to make it small and testable is to make the payload's allowed-value set *closed under everything the prompt permits the AI to say* — precompute deltas and differences into named payload fields rather than letting the validator search for derivable arithmetic. That turns validation into pure set membership.

Three shipped facts contradict plausible assumptions and must reach the planner: (a) the Phase 26 non-streaming path `call_claude_json` has **no transport retry** — the exponential-backoff envelope lives only in the streaming chat service; (b) `call_claude_json` returns a caller-supplied `fallback` dict on unparseable JSON, which for a *finding* is a silent-fabrication path and must not be used; (c) the `dashboard_alerts_alert_type_check` value list exists as **two independent literals** — the Alembic SQL and the ORM `CheckConstraint` string in `dashboard/models.py:59-70` — despite `alert_types.py`'s docstring claiming single-sourcing. Both must change together in migration 0036.

**Primary recommendation:** Build detection as a DB-free `profitability_math.py` beside `budget_math.py`/`portfolio_math.py`; feed the AI only `ProjectFinancialFigures` + unsliced trend buckets + named precomputed deltas; put the grounding validator in `app/core/ai_grounding.py` as a payload-shape-agnostic module (Phase 37 reuse); mirror Phase 34's claim-first atomic `UPDATE ... WHERE alerted_at IS NULL RETURNING id` for exactly-once alerting, with the severity band inside the fingerprint so a worsening band produces a new fingerprint and re-alerts for free.

---

## Project Constraints (from CLAUDE.md)

Directives the planner must verify every task complies with:

| Directive | Consequence for this phase |
|---|---|
| **No query inside a loop**; `selectinload`/`joinedload`; all FK relationships `lazy="raise"` | The per-project trend replay (6 queries × candidate count) is a *bounded service call per project*, which 34-02 established as permitted; the eligibility gate must run FIRST so trends run only for eligible projects. Never iterate cost entries with a query per row. |
| **No `db.commit()` in services** — `get_db` owns it | The cron path is the exception already handled: `_run_for_all_companies` commits explicitly per company (`scheduler.py:83`). Service methods still must not commit. |
| **All new models inherit `TenantScopedModel`; services `TenantScopedService`; repositories `TenantScopedRepository`; schemas `BaseResponseSchema`** | `AIProfitabilityFinding(TenantScopedModel)`, `ProfitabilityService(TenantScopedService[...])`, `ProfitabilityRepository(TenantScopedRepository[...])`. |
| **Standalone service functions are NOT allowed — use class methods** | Pure math modules are exempt by precedent (`budget_math.py`, `margin_math.py`, `trend_math.py`, `portfolio_math.py` are all module-level functions). Keep new pure functions in a math module, not loose in a service file. |
| **Routers stay thin — delegate to service** | The new `GET .../finding` route does `require_permission` + one service call + one mapper. |
| **No magic numbers/strings — named constants** | Every D-03 threshold, band boundary, token ceiling, findings cap, cron hour, alert type, and prompt-contract limit (280) is a named constant. |
| **Small functions (~20 lines), one thing, 0-2 args ideal / 3 max, dataclasses for many params** | Frozen dataclasses for `CandidateSignal`, `ProfitabilityPayload`, `GroundingResult`, `FindingDraft` — matching `BudgetFacts` / `TrendInputs` / `FiredBudgetAlert`. |
| **DRY — extract when a pattern appears twice** | Never restate margin/budget/trend math (Pitfall 1 drift). Import `margin_percent_for`, `quoted_revenue`, `crossed_thresholds`, `percent_used`. |
| **Minimal comments — WHY not WHAT; no dead code** | `finance_scrub` shipped in Phase 30 as "tested utility only, not wired — avoids dead code". Only wire it where a real non-finance dict-builder exists. |
| **No hardcoded secrets** | `ANTHROPIC_API_KEY` via `settings.anthropic_api_key` (`config.py:22`) → `get_anthropic_client()`. No new model-config surface (D-10). |
| **Every new service function/endpoint MUST have tests before merging; E2E ships in the same change** | See § Validation Architecture; `backend/tests/test_phase_36_e2e.py` + `web/tests/phase-36-ai-findings.spec.ts` + jest component tests, all in-change. |
| **Run `ruff check` + `ruff format` (backend), `npm run lint` (`--max-warnings 0`) + `npx tsc --noEmit` (web) before commit; pre-commit hooks enforce** | Static gates listed in the sampling rate table. |
| **Run `docker compose up migrate` after adding an Alembic migration** | Required after 0036 lands. |
| **Prefer editing existing files over creating new ones** | Extend `alert_types.py`, `finance/router.py`, `scheduler.py`, `project-financials-dashboard.tsx` rather than parallel structures. New files only for the genuinely new module boundaries (math, service, repository, model, prompt, validator). |

---

## Standard Stack

Nothing new is installed. Every dependency is already pinned and in use.

### Core

| Library | Version (verified) | Purpose | Why Standard |
|---|---|---|---|
| `anthropic` | `0.86.0` installed; `requirements.txt:18` pins `anthropic>=0.86.0` | Non-streaming Claude call for the batch job | Shipped Phase 21/26 client; `AsyncAnthropic` lazy singleton in `app/core/ai_utils.py:49-62` |
| `apscheduler` | `3.10.4` (`requirements.txt:21`) | Cron registration | Three jobs already registered in `app/core/scheduler.py:144-168` |
| `sqlalchemy[asyncio]` | `2.0.38` | ORM + `pg_insert(...).on_conflict_do_update` | Idempotent upsert precedent: `checklists/repository.py:41-79` |
| `fastapi[standard]` | `0.115.12` | Findings endpoint | `finance/router.py` pattern |
| `pydantic` | `2.10.6` | Response schemas; **`Decimal` auto-serializes to JSON string** (`finance/schemas.py:86-87` — verified, no custom serializer) | Decimal-as-string is the project-wide money convention |
| Jest 30 + ts-jest + jsdom + RTL | `web/jest.config.ts` | Web component tests | 35-VALIDATION |
| Playwright | `1.58.2` (verified via `npx playwright --version`) | Web E2E, chromium project | 35-VALIDATION |
| pytest + pytest-asyncio | `asyncio_mode = "auto"`, `testpaths=["tests"]` (`pyproject.toml`) | Backend integration/E2E against real `contractorhub_test` | conftest force-selects the test DB and runs `alembic upgrade head` |

### Model configuration (verified from codebase, not memory)

| Constant | Value | Location |
|---|---|---|
| `CLAUDE_MODEL` | `"claude-sonnet-4-6"` | `app/core/ai_utils.py:28` |
| `CLAUDE_MAX_TOKENS` | `2048` | `app/core/ai_utils.py:29` |
| `CLAUDE_TIMEOUT` | `30.0` | `app/core/ai_utils.py:30` |
| `AI_CONCURRENCY_LIMIT` | `5` | `app/core/ai_utils.py:33` |
| API key source | `settings.anthropic_api_key`, falling back to the `ANTHROPIC_API_KEY` env var | `app/core/ai_utils.py:56-62`, `app/core/config.py:22` |
| Streaming chat model (separate, do NOT use) | `_CLAUDE_MODEL = "claude-sonnet-4-6"`, `_MAX_TOKENS = 4096`, `_RETRY_DELAYS = [1.0, 2.0, 4.0]` | `app/features/ai/service.py:83-85` |

D-10 says reuse the Phase 26 configured model → **import `CLAUDE_MODEL` / `CLAUDE_MAX_TOKENS` from `app.core.ai_utils`; do not add a new setting.**

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Single completion returning JSON | Claude **tool use** (Phase 21 chat pattern) | Tool use lets the model pull figures on demand, but the whole D-05 grounding contract depends on the payload being a *closed, known* value set computed before the call. Tool use makes the allow-set dynamic and the validator much harder. **Recommend a single non-streaming completion with the full payload inline** — matches Phase 26 exactly and D-10's "no new model-config surface". |
| `call_claude_json(..., fallback=...)` | A strict sibling that raises on unparseable JSON | The shipped `fallback` (`ai_utils.py:99-107`) returns a caller-supplied dict on bad JSON. For a checklist that degrades to `{"tasks": []}` harmlessly. For a *finding* it is a silent-fabrication path. **Recommend adding `call_claude_json_strict()` to `ai_utils.py`** (raises `ValueError`), rather than overloading one function with two error policies. |
| Batching the whole company into one Claude call | Per-candidate calls via `gather_with_concurrency` | Per-candidate keeps the D-10 per-project token ceiling meaningful, keeps one bad candidate from poisoning the rest, and reuses the shipped bounded-concurrency helper. **Recommend per-candidate.** |
| Re-arming `alerted_at = NULL` on clear-and-recur | Setting `resolved_at` and letting a recurrence insert a fresh row | Resolve-then-reinsert gives free history, makes the partial unique index natural, and makes the "worsens into a different band" case fall out automatically (different band ⇒ different fingerprint ⇒ new row ⇒ new alert). **Recommend resolve-then-reinsert.** |

**Installation:** none. `pip`/`npm` untouched.

---

## Architecture Patterns

### Recommended file layout

```
backend/app/
├── core/
│   ├── ai_grounding.py              # NEW — reusable D-05 validator (Phase 37 reuses)
│   ├── ai_utils.py                  # EDIT — add call_claude_json_strict()
│   └── scheduler.py                 # EDIT — run_ai_profitability_analysis + _register_jobs
└── features/
    ├── dashboard/
    │   ├── alert_types.py           # EDIT — AI_PROFITABILITY_ALERT_TYPE + FINANCIAL_ALERT_TYPES
    │   └── models.py                # EDIT — CheckConstraint literal (line 59-70)
    └── finance/
        ├── profitability_math.py    # NEW — pure D-03 detection + bands + fingerprint
        ├── profitability_models.py  # NEW — AIProfitabilityFinding (or append to models.py)
        ├── profitability_repository.py  # NEW — upsert/claim/latest-per-project
        ├── profitability_service.py # NEW — eligibility → candidates → payload → Claude → validate → persist → alert
        ├── prompts/
        │   └── profitability_system.py  # NEW — prompt contract (checklists/prompts precedent)
        ├── router.py                # EDIT — GET /projects/{id}/financials/finding
        ├── schemas.py               # EDIT — finding response schema
        └── service.py               # EDIT — make _contributing_anchor_cost public (35-05 precedent)

backend/migrations/versions/0036_ai_profitability_findings.py   # NEW

web/src/
├── app/(dashboard)/financials/[projectId]/_components/
│   ├── profitability-finding-card.tsx      # NEW
│   └── project-financials-dashboard.tsx    # EDIT — mount the card
└── features/finance/{types.ts,api.ts,hooks.ts}   # EDIT — finding type + hook

backend/tests/test_phase_36_e2e.py
backend/tests/unit/test_profitability_math.py
backend/tests/unit/test_ai_grounding.py
web/tests/phase-36-ai-findings.spec.ts
web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx
```

---

### Pattern 1: The nightly job is a structural sibling of `run_morning_checklists`

`_run_for_all_companies` (`scheduler.py:44-93`) is the whole harness: it fetches non-deleted companies once with an admin session, then processes each under `asyncio.Semaphore(AI_CONCURRENCY_LIMIT)` with its own session, `set_current_tenant_id(company.id)`, an explicit `await db.commit()`, and a per-company `try/except` that logs and continues. **The skip/failure posture D-01 asks for is already the harness's posture.**

```python
# Source: backend/app/core/scheduler.py:77-93 (verified)
async def _process_company(company):
    async with semaphore, async_session_factory() as db:
        try:
            set_current_tenant_id(company.id)
            svc = service_class(db)
            await getattr(svc, method_name)(company_id=company.id, target_date=target_date)
            await db.commit()
        except Exception:
            await db.rollback()
            logger.exception("%s: failed for company %s — continuing", job_name, company.id)
```

**Hard contract:** the service method signature must be exactly `method(company_id=..., target_date=...)`. `BudgetService.sweep_budgets` (`budget_service.py:315-324`) documents accepting an unused `target_date` purely to satisfy it. Here `target_date` *is* used (the `analyzed_on` date).

**Cron slot (Claude's discretion — recommendation).** Shipped: `BUDGET_SWEEP_HOUR_UTC = 5`, `MORNING_CHECKLIST_HOUR_UTC = 6`, `ALERT_DETECTION_HOURS_UTC = "7-19"` (`scheduler.py:34-41`). The semaphore in `_run_for_all_companies` is created per invocation, so two overlapping AI jobs give 10 concurrent Claude calls, not 5. **Recommend `AI_PROFITABILITY_HOUR_UTC = 6, AI_PROFITABILITY_MINUTE_UTC = 30`** — after the 05:00 budget sweep (so budget context in the payload is current), offset from the 06:00 checklist burst, before the 07:00 alert-detection tick. Register with `misfire_grace_time = 3600` matching the other daily jobs. Extract nothing new: `_register_jobs(target_scheduler)` (`scheduler.py:144`) exists specifically so registration is testable without starting the app (34-06 decision).

---

### Pattern 2: Eligibility (D-01) reads four shipped signals off one aggregate block

`PortfolioService._fetch_portfolio_inputs()` (`portfolio_service.py:498-521`) does every company-wide read; `_project_figures(project, inputs)` (`:295-316`) is pure and yields `ProjectFinancialFigures` (`portfolio_math.py:65-77`):

```python
@dataclass(frozen=True)
class ProjectFinancialFigures:
    project_id: uuid.UUID
    name: str
    status: str
    cost: Decimal
    revenue: ResolvedRevenue | None
    quoted_revenue: Decimal          # the estimated (quote-basis) share — D-09 honesty
    unrated_seconds: int
    margin: MarginFigures            # revenue, revenue_basis, margin, margin_percent,
                                     # incomplete, incomplete_reasons
    budgets: Sequence[AnchoredBudget]
```

| D-01 clause | Shipped signal | Source |
|---|---|---|
| **active** | `figures.status == "active"` | `Project.status` CHECK allows `draft/planning/active/on_hold/complete/archived` (`projects/models.py:77`) |
| **has a revenue source** | `figures.revenue is not None` (equivalently `margin.revenue_basis != "none"`) | `margin_math.py:26-29`, `summarize_margin` returns basis `none` + all-None when revenue is absent |
| **has some cost data** | `figures.cost > ZERO_MONEY` | `context.grand_total` from `_build_breakdown` |
| **no incomplete-data flag** | `figures.margin.incomplete is False` | Covers both Phase 33 reasons: `unrated_labor` (unrated seconds > 0) and `no_cost_data` (revenue > 0 with zero cost, the Pitfall-9 case) — `margin_math.py:155-162` |

**Do not reuse `ACTIVE_PROJECT_STATUSES = ("planning", "active")` from `ai_utils.py:39.** That constant includes `planning`; ROADMAP SC1 and D-01 both say *active*. Define `PROFITABILITY_ELIGIBLE_STATUSES = ("active",)` in the new math module and document the deliberate divergence.

**Skip log (D-01).** No "run log" table exists anywhere in the codebase (verified by grep). Recommend structured logging only — one `logger.info` per skipped project with `project_id` + a named `SkipReason` StrEnum value, plus one summary line per company (`analyzed=N candidates=M findings=K skipped=S`). A persisted run-log table is not required by any success criterion and would be new surface for no verification benefit. If the planner wants persistence, the honest cheapest option is a `skipped_reason` column on the findings table with a `dismissed`-style row — but that pollutes "findings". Recommend logs.

---

### Pattern 3: Candidate detection lives in a pure DB-free module

Four shipped pure modules establish the pattern verbatim — `margin_math.py`, `budget_math.py`, `portfolio_math.py`, `trend_math.py` — each opening with "This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories." **`profitability_math.py` must follow it**, because the three keystone properties (thresholds, bands, fingerprint stability) are then unit-testable with zero fixtures (`tests/unit/test_trend_math.py`, `test_portfolio_math.py` precedent).

**Signal 1 — margin decline across the last 2 monthly trend buckets.**

```python
# buckets come from trend_math.trend_buckets(...) — UNSLICED (see below)
MARGIN_DECLINE_POINTS = Decimal("5")

def declined_across_last_two(buckets: Sequence[TrendBucket]) -> Decimal | None:
    if len(buckets) < 2:
        return None
    latest, prior = buckets[-1].margin.margin_percent, buckets[-2].margin.margin_percent
    if latest is None or prior is None:
        return None          # absent revenue / zero revenue — never coerce to 0
    return prior - latest    # positive == decline
```

Three subtleties the planner must not "fix":
1. **Trend buckets are cumulative as-of replays from project inception, not per-month slices** (`trend_math.py` module docstring; `_cost_prefix_sums`, `_labor_prefix_totals`). A 5-point swing in a *cumulative* margin percent month-over-month is a genuinely large event — the conservative, noise-bounded reading D-02 asks for. Do not convert to per-month deltas.
2. **Use the unsliced bucket list.** `window_slice(buckets, window)` (`trend_math.py:174-181`) exists for the UI. Detection must call `trend_buckets(inputs)` and take `[-2:]` so a UI window setting can never change detection.
3. `margin_percent` is `None` when revenue is absent **or zero** (`margin_math.py:148-152`). Treating `None` as `0` fabricates a 100-point cliff. Guard explicitly.

**Signal 2 — negative margin.** Use `figures.margin.margin < ZERO_MONEY`, **not** `margin_percent < 0`. `margin_percent` is `None` at zero revenue while `margin` is still a real number; and when revenue > 0 the two agree in sign, so `margin` is strictly safer.

**Signal 3 — billed margin ≥5 pts below quote-implied margin (the only genuinely new derivation).**

`anchor_revenues()` **cannot** supply the quote leg: `margin_math.py:212-216` adds a quote only `if anchor not in resolved`, i.e. it discards approved quotes at anchors that have invoices. That is the D-01 invoices-win rule — and it is precisely the leg this signal needs. Build it from the raw rows instead:

```python
# Source pattern: portfolio_service.py:127-128 (PortfolioInputs.quotes) +
#                 margin_math.quoted_revenue (:189-191)
# inputs.quotes[project_id] : list[(RevenueAnchor, DocumentAmounts)], newest-first per anchor
#   (order preserved from approved_quote_amounts_query()'s created_at DESC —
#    repository.py:332-343, portfolio_repository.py:177-184)

def latest_quote_per_anchor(rows):          # first row per anchor == latest approved (D-03)
    latest = {}
    for anchor, amounts in rows:
        latest.setdefault(anchor, amounts)
    return latest
```

Then, **on the same anchor set**:
- Comparable anchors = anchors present in BOTH the resolved-revenue map (`anchor_revenues(...)`) and the latest-quote map.
- Quote-implied revenue = `sum(quoted_revenue(amounts) for those anchors)`.
- Cost at those anchors = `sum(_contributing_anchor_cost(anchor, context))` — `service.py:145-151`, which adds job-anchored derived labor to the anchor's cost-entry sum. **Make it public** rather than restating it; 35-05 set the precedent ("five module-level finance query builders/mappers made public so `portfolio_repository` composes the shipped predicates instead of restating them").
- Billed revenue = `sum(resolved[anchor].total for those anchors)`.
- Both margins via `margin_percent_for(revenue - cost, revenue)` (`margin_math.py:148`).
- Fire when `quote_implied_pct - billed_pct >= QUOTE_IMPLIED_GAP_POINTS`.

**Guard against tautology:** require at least one anchor in the comparable set whose resolved basis is `invoiced`. If every comparable anchor resolved to `quoted`, billed revenue *is* quote revenue and the gap is identically zero — the signal would be vacuous, and worse, a rounding artifact could make it fire.

**Bands + fingerprint.** Both are Claude's discretion. Recommendation:

```python
SEVERITY_BAND_WARNING = "warning"       # maps to DashboardAlert.severity 'warning'
SEVERITY_BAND_CRITICAL = "critical"     # maps to 'critical'
FINGERPRINT_TEMPLATE = "{project_id}:{signal}:{band}"
```

`dashboard_alerts_severity_check` allows `info|warning|critical` (`dashboard/models.py:62-65`), so two bands mapping onto `warning`/`critical` needs no severity migration. Keep band boundaries as named Decimal constants in the math module. Because the band is *inside* the fingerprint, D-06's "worsens into a different band ⇒ new alert" falls out for free — but the previous band's row must be resolved in the same run, or both stay open. Handle that explicitly and test it.

---

### Pattern 4: The AI payload is aggregates only, with a closed value set

PITFALLS.md's performance note and Pitfall 6 both require pre-computed aggregates, never raw rows. Phase 26 already extracts ORM data into plain dicts before any Claude call (`checklists/service.py:101-145` — "no ORM objects — safe for use after session release"). Mirror it exactly.

The payload should carry, per candidate:
- project name + status
- `cost`, `revenue`, `revenue_basis`, `quoted_revenue` share, `margin`, `margin_percent`
- `incomplete` / `incomplete_reasons` (always false/empty for eligible projects by D-01, but the field documents the posture)
- **`labor_basis: "unburdened"`** — verified shipped default at `finance/schemas.py:127`; Pitfall 2 and D-05 both require it travel with the data and be reflected in the finding's language
- `unrated_seconds`
- category mix (from `rollup.categories` — names + totals, aggregates)
- anchored budgets (`label`, `spent`, `total`, `percent_used`) — for corrective-action context only; D-04 forbids duplicating Phase 34's alerts
- last two trend buckets (`month`, `cost`, `margin_percent`)
- **the named precomputed deltas** the prompt is allowed to cite (see Pattern 5)
- the candidate signal(s) and band

`finance/schemas.py:144` already documents `revenue_basis` as "machine-readable for the UI caption **and for Phase 36 AI**" — the honesty contract was designed for this.

**Per-project token ceiling (D-10).** `max_tokens` caps **output only**; the ceiling therefore needs two halves: (a) a named `PROFITABILITY_MAX_OUTPUT_TOKENS` passed as `max_tokens`, and (b) a bound on payload size — which the aggregates-only rule already delivers. `response.usage.input_tokens` / `.output_tokens` are available on the SDK response for the run log (verified against current Anthropic docs). Per-company nightly findings cap: a named constant, counted **after** validation and **before** persistence, with the drop logged.

---

### Pattern 5: The grounding validator (D-05) — set membership, not arithmetic search

Put it at `backend/app/core/ai_grounding.py`. `app/core/` is where cross-feature AI plumbing already lives (`ai_utils.py`, `finance_scrub.py`); Phase 37 lives in `features/quotes`, so a `features/finance/` home would force quotes to import from finance.

Keep it **payload-shape agnostic** so Phase 37 reuses it unchanged:

```python
@dataclass(frozen=True)
class GroundingResult:
    ok: bool
    unmatched: tuple[str, ...]      # the offending literals, verbatim, for the retry prompt

def collect_allowed_values(payload: Mapping[str, object]) -> frozenset[Decimal]: ...
def extract_figures(text: str) -> tuple[str, ...]: ...
def validate_grounding(text: str, allowed: frozenset[Decimal]) -> GroundingResult: ...
```

**Extraction.** Make the prompt contract mandate `$` and `%` sigils and forbid number words, so the extractor stays one level of abstraction (CLAUDE.md):
- money: `\$\s?\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\$\s?\d+(?:\.\d{1,2})?`
- percent: `-?\d+(?:\.\d+)?\s?%`
- Normalize by stripping `$`, `,`, `%` and constructing `Decimal`.

**Matching.** Two representation tolerances are unavoidable and both are already exercised by shipped formatters:
- `format_alert_money` (`budget_math.py:85-87`) renders `Decimal("10000.00")` as `"$10,000"` — thousands separators and a stripped `.00`. Normalize the *cited* literal, then compare against the payload value quantized to `CENTS`.
- `format_alert_percent` (`budget_math.py:90-92`) strips a trailing `.0`. Compare percents quantized to `PERCENT_PLACES` (`Decimal("0.1")`, `margin_math.py:35`) — `margin_percent` is already one-decimal ROUND_HALF_UP.
- Also accept a whole-dollar rounding of a payload value (`quantize(Decimal("1"), ROUND_HALF_UP)`), since the AI will naturally write `$3,200` for `3200.41`. **Decide this explicitly and test both directions** — it is a real loosening.

**The load-bearing design rule:** *the allowed set must be closed under everything the prompt permits the AI to say.* The AI will legitimately want to cite deltas ("margin fell 6.2 points", "$3,200 over the quote's allowance"). Rather than letting the validator search for derivable arithmetic (unbounded, slow, and a hallucination laundering channel), **precompute every citable derived figure into the payload as a named field** — `margin_decline_points`, `quote_gap_points`, `over_quote_dollars`, `budget_remaining` — and forbid the AI from computing anything. Then validation is pure set membership: small, fast, exhaustively testable, and with no false-accept surface.

**Never allow a bare `$0`/`0%` unless a real payload zero exists.** A fabricated `$0` is exactly Pitfall 9's failure mode.

**Retry (one, per D-05).** Second call = same system prompt, conversation continued with a user turn naming the unmatched literals and restating the allowed values. On second failure: drop, `logger.warning` with project id + unmatched literals, persist nothing, alert nothing. Structure this so it is testable offline: the keystone test patches `messages.create` with `side_effect=[bad, bad]` and asserts zero findings and zero alerts.

**Distinguish two retries.** D-05's retry is a *validation* retry. There is **no transport retry** on this path (see Pitfall 1 below). Do not conflate them; the constant names should say which (`GROUNDING_RETRY_LIMIT = 1`).

---

### Pattern 6: The prompt contract (D-09)

Follow `checklists/prompts/checklist_system.py`: a module-level string constant in a `prompts/` package, instructing "Return ONLY valid JSON matching the schema below — no markdown fences". `strip_fences()` (`ai_utils.py:65-70`) handles fences anyway.

Response schema should carry the dismissal contract (D-02: the AI confirms **or dismisses** each candidate):

```json
{
  "confirmed": true,
  "dismissal_reason": null,
  "narrative": "<full paragraph for the financials page>",
  "corrective_action": "<target + direction + cited payload figure>",
  "alert_summary": "<= 280 chars, for DashboardAlert.impact_text and the FCM body>"
}
```

D-09's shape ("Plumbing scope materials are $3,200 over the approved quote's allowance — rebill the change order or renegotiate supplier pricing before drywall starts") = **target** (plumbing scope materials) + **direction** (rebill / renegotiate) + **cited payload figure** ($3,200). Enforce the target/direction halves in the prompt; the validator enforces the figure half. Ban "review your costs"-class filler explicitly in the prompt.

Phase 34's alert copy is byte-for-byte template-locked in `budget_math.py` and asserted byte-for-byte in tests. **AI-written text cannot be** — so the Phase 36 UI-SPEC must lock the *frame* strings (card title, empty state, "Suggested action" label, timestamp format) while the narrative/action stay free text with only a length bound. Say this in the UI-SPEC so the planner doesn't write an impossible byte-identity assertion.

---

### Pattern 7: Alert-type registration + migration 0036

`alert_types.py` (whole file, verified):

```python
SCHEDULE_SLIP_ALERT_TYPE = "schedule_slip"
RESCHEDULING_SUGGESTION_ALERT_TYPE = "rescheduling_suggestion"
DEPENDENCY_RISK_ALERT_TYPE = "dependency_risk"
BUDGET_WARNING_ALERT_TYPE = "budget_warning"
BUDGET_OVERRUN_ALERT_TYPE = "budget_overrun"
FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset({BUDGET_WARNING_ALERT_TYPE, BUDGET_OVERRUN_ALERT_TYPE})
```

Add `AI_PROFITABILITY_ALERT_TYPE = "ai_profitability"` and include it in `FINANCIAL_ALERT_TYPES`. The permission filter then comes free at `dashboard/service.py:748-755`:

```python
if has_finance_view:
    return alerts
return [a for a in alerts if a.alert_type not in FINANCIAL_ALERT_TYPES]
```

with the router resolving `has_finance_view="finance.view" in granted` (`dashboard/router.py:98`).

**Three literals must change together** — this is the single easiest thing to half-do:
1. `alert_types.py` — the new constant + the frozenset.
2. `backend/migrations/versions/0036_...py` — DROP + re-ADD `dashboard_alerts_alert_type_check` with the six values. Verbatim precedent, `0035_budget_alerts_and_quote_chain.py:37-45`.
3. **`app/features/dashboard/models.py:59-70`** — the ORM `CheckConstraint("alert_type IN ('schedule_slip',...)")` is an **independent hardcoded literal**, despite `alert_types.py`'s docstring claiming both are "expressed here". Verified. Miss it and the model diverges from the DB.

`down_revision` for 0036 is `"0035_budget_alerts_quote_chain"` (note: the revision **id** is shorter than the filename — 34-01 shortened it because a 34-char id overflowed `alembic_version varchar(32)`; keep the new id ≤32 chars).

---

### Pattern 8: Exactly-once alerting = Phase 34's claim-first atomic UPDATE

34-03's decision (STATE.md): "exactly-once budget alerts via **claim-first atomic UPDATE**; alert_context resolved before claiming so a vanished anchor never burns a claim". `BudgetService._fire_threshold` (`budget_service.py:364-392`) is the shape:

```python
if not await self.repository.claim_threshold(budget.id, threshold):
    return None                     # already claimed — no alert
alert = await AlertRepository(self.db).create(self._build_alert(...))
return FiredBudgetAlert(...)
```

Applied to findings:

| Concern | Mechanism |
|---|---|
| Nightly upsert without re-alerting | `pg_insert(...).on_conflict_do_update(index_elements=[...], index_where=text("deleted_at IS NULL AND resolved_at IS NULL"), set_={narrative, corrective_action, payload, last_seen_on})` — **never touch `alerted_at`**. Precedent: `checklists/repository.py:53-79`. |
| Alert exactly once | `UPDATE ai_profitability_findings SET alerted_at = now() WHERE id = :id AND alerted_at IS NULL RETURNING id` — zero rows means already alerted. |
| Clear-and-recur re-fires | On a night where a fingerprint no longer qualifies, set `resolved_at`. The partial unique index (`WHERE deleted_at IS NULL AND resolved_at IS NULL`) then lets a recurrence insert a fresh row with `alerted_at IS NULL` ⇒ new alert. |
| Band worsening re-fires | Band is in the fingerprint ⇒ different fingerprint ⇒ new row ⇒ new alert. **Resolve the prior band's row in the same run** or both stay open. |
| Same-day re-run is idempotent | The upsert + the claim, together. No date arithmetic needed. |

**FCM.** Copy `budget_service.py:417-466` structure exactly:
- Resolve recipients **in the current session, before scheduling any background task** — `RbacRepository(self.db).user_ids_with_permission(company_id, "finance.view")` (`rbac/repository.py:68-71`). 34-03: "recipients resolved in the request session, background task gets primitives + fresh session"; this is also what makes the recipient set assertable in tests.
- Fire-and-forget via `asyncio.create_task`, holding task refs in a module-level `set` (asyncio keeps only weak references) with `task.add_done_callback(set.discard)`.
- The background coroutine creates its **own** session and calls `set_current_tenant_id` — the request session is closed by then.
- Every FCM data value must be a `str` (FCM constraint) — `_push_data` uses `""` for absent scope (`budget_service.py:61, 90-100`).
- Dispatch: `NotificationService` has `send_budget_alert_notification(recipient_ids, title, body, data)` (`notifications/service.py:310-337`). Recommend a **sibling** `send_profitability_finding_notification` with the same body, rather than reusing the budget-named method — the name is load-bearing in logs. Both should share `_dispatch_to_tokens` (`:442`), which is where the DRY line actually is.

---

### Pattern 9: Findings endpoint + web mount (D-08)

**Endpoint.** Add to `finance/router.py`, matching the shipped shape (`finance/router.py:93-110`):

```python
@router.get("/projects/{project_id}/financials/finding", response_model=ProfitabilityFindingResponse | None)
async def get_latest_finding(project_id, db=Depends(get_db), current_user=Depends(get_current_user)):
    await require_permission("finance.view")(current_user, db)
    return ...   # thin — one service call + one mapper
```

**Separate query, separate key — do not fold into `/financials`.** 35-10's shipped decision: "A failing trend query degrades to its own empty state instead of blanking the drill-down — two queries, two keys, two failure surfaces." A findings outage must not blank the money dashboard.

**Web.** `/financials/**` is already wrapped by `FinanceGate` via `financials/layout.tsx`. That layout's own comment states the non-negotiable: *"Gating the render is only half the guard: every financial hook additionally passes `enabled: can(FINANCE_VIEW_PERMISSION)`. Render-only gating would still issue the request, so an unauthorized visit would leak money data over the wire and the 'zero /api/v1/financials/* requests' assertion would prove nothing."* The new hook **must** pass `enabled` too, or keystone test 3 becomes vacuous.

Query key: `["cost-entries", "financials", "finding", projectId]` — all finance hooks share the `["cost-entries", ...]` prefix so `invalidateFinance` (`hooks.ts:148`) clears them in one call.

Mount the card in `project-financials-dashboard.tsx` — the file's docstring calls it "the only hook-owning component on `/financials/[projectId]`", so the hook belongs there and the card stays presentational.

Types: money/percent stay **strings** end-to-end (`types.ts` — "Decimal-as-string, displayed verbatim, never re-summed"). Never `Number()` a finding figure.

**AlertPanel** (`monitoring/_components/AlertPanel.tsx`) needs **no change**: it renders `impact_text` (line 108-110) and optional `remediation_text` (line 120-124) generically, and severity styling covers `info|warning|critical` (line 22-38). Map `alert_summary` → `impact_text` and `corrective_action` → `remediation_text` and the panel renders correctly as-is. Verify by test rather than editing.

---

### Pattern 10: Persistence + migration

`AIProfitabilityFinding(TenantScopedModel)` — inherits `id`, `version`, `created_at/updated_at/deleted_at`, `company_id` (`core/base_models.py`). Recommended columns:

| Column | Notes |
|---|---|
| `project_id` | FK `projects(id) ON DELETE CASCADE`; relationship `lazy="raise"` (CLAUDE.md) |
| `signal`, `severity_band` | TEXT + CHECK constraints, values from `profitability_math` constants |
| `fingerprint` | TEXT, the dedup key |
| `narrative`, `corrective_action` | TEXT — the financials-page paragraph and the action |
| `alert_summary` | TEXT + `CHECK (char_length(alert_summary) <= 280)` — D-09 is a contract, enforce in both prompt and DB |
| `payload` | JSONB — the exact aggregates the finding was grounded against. **This is the SC3 audit trail**; without it a published finding cannot be re-verified later. |
| `dashboard_alert_id` | UUID NULL, FK `dashboard_alerts(id) ON DELETE SET NULL` |
| `alerted_at`, `resolved_at`, `analyzed_on` | TIMESTAMPTZ / TIMESTAMPTZ / DATE |

Indexes:
- `CREATE UNIQUE INDEX ux_ai_profitability_findings_open ON ai_profitability_findings (company_id, fingerprint) WHERE deleted_at IS NULL AND resolved_at IS NULL` — 0035's partial-unique-index precedent (`ux_budgets_active_project`).
- `CREATE INDEX ... ON (company_id, project_id, created_at DESC)` for latest-per-project.
- `ix_..._company_id`, `ix_..._project_id` per 0032 convention.

RLS — the four-statement block verbatim from `0032:153-160`, using FORCE (also used for `daily_checklists`/`dashboard_alerts` per Phase 26):

```sql
ALTER TABLE ai_profitability_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_profitability_findings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_ai_profitability_findings ON ai_profitability_findings
  USING (company_id = current_setting('app.current_company_id')::uuid);
GRANT SELECT, INSERT, UPDATE, DELETE ON ai_profitability_findings TO appuser;
```

The `GRANT ... TO appuser` line is easy to forget and produces a permission error only at runtime.

---

### Anti-Patterns to Avoid

- **Restating margin / budget / trend math in the detector.** Pitfall 1 drift; the equivalence-pin tests (`test_company_rollup_matches_rollup_for_project`) exist because of it. Import `margin_percent_for`, `quoted_revenue`, `crossed_thresholds`, `percent_used`.
- **Using `anchor_revenues()` for the quote-implied leg.** It discards quotes at invoiced anchors by design (`margin_math.py:212-216`) — the exact leg signal 3 needs.
- **Using windowed trend buckets for detection.** `window_slice` is a UI concern.
- **Feeding the AI raw `CostEntry` rows.** Aggregates only.
- **Letting the AI compute.** Every citable figure precomputed and named; the AI selects and phrases.
- **Reusing `call_claude_json`'s `fallback` for findings.** Silent fabrication.
- **Treating `margin_percent is None` as `0`.** Fabricates cliffs.
- **`float` anywhere near money.** Pitfall 10; the codebase is Decimal end-to-end.
- **Editing the migration without the ORM `CheckConstraint`** (`dashboard/models.py:59-70`).
- **Render-only gating on the web** without the hook `enabled` guard.
- **Duplicating Phase 34 budget alerts** (D-04). Budget figures are *context* for the corrective action, never a second alert.
- **Committing inside a service method.** Only `_run_for_all_companies` commits on this path.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Per-company cron fan-out with per-company sessions, RLS context, bounded concurrency, isolated failures | A bespoke loop in the new service | `scheduler._run_for_all_companies` (`scheduler.py:44-93`) | The skip-and-continue posture D-01 wants is already its posture |
| Bounded-concurrency Claude calls with per-item failure isolation | `asyncio.gather` + hand-rolled semaphore | `ai_utils.gather_with_concurrency` (`:110-130`) | Returns `None` per failure, logs, never aborts the batch |
| Anthropic client lifecycle / key sourcing / timeout | A second `AsyncAnthropic(...)` | `ai_utils.get_anthropic_client()` (`:49-62`) | Lazy singleton; avoids import-time failure when the key is unset (tests) |
| Markdown-fence stripping | A new regex | `ai_utils.strip_fences` (`:65-70`) | Shipped and tested |
| Idempotent nightly upsert | SELECT-then-INSERT-or-UPDATE | `pg_insert(...).on_conflict_do_update(..., index_where=text("deleted_at IS NULL"))` (`checklists/repository.py:53-79`) | Race-free in one round trip; soft-delete-aware |
| Exactly-once alert firing | A "did we alert?" SELECT then INSERT | Claim-first atomic `UPDATE ... WHERE alerted_at IS NULL RETURNING id` (34-03) | The SELECT-then-write version double-fires under concurrent runs |
| Finance recipient resolution | Role-name literals (`owner`, `project_manager`) | `RbacRepository.user_ids_with_permission(company_id, "finance.view")` (`rbac/repository.py:68`) | 34-03: live matrix, never role-name literals — FINSEC-02 lets companies change grants |
| FCM dispatch, token lookup, Firebase-absent degradation | A new sender | `NotificationService._dispatch_to_tokens` via a sibling of `send_budget_alert_notification` (`:310-337`) | Skips gracefully without credentials, logs, never raises |
| Alert permission filtering | A per-endpoint check | `FINANCIAL_ALERT_TYPES` membership (`dashboard/service.py:753-755`) | Registration alone gates dashboard visibility |
| Money/percent display formatting | New formatters | `budget_math.format_alert_money` / `format_alert_percent` (`:85-92`); web `finance-formatters` | Also defines the exact representations the grounding validator must tolerate |
| Per-anchor cost including derived labor | A new sum | `service._contributing_anchor_cost` (`:145-151`), made public | Job anchors must add derived labor; restating it is the drift |
| Margin percent, revenue resolution, discount/tax | New arithmetic | `margin_math` (`margin_percent_for`, `quoted_revenue`, `anchor_revenues`, `combined_anchor_revenue`) | Single home, ROUND_HALF_UP one-decimal, bit-compatible with shipped totals |
| Monthly as-of buckets | New bucketing | `trend_math.trend_buckets` (`:156-171`) | The effective-dated rate rule must never leak into SQL (Phase 32) |
| Cron job registration for tests | Registering inside `lifespan` | `scheduler._register_jobs(target_scheduler)` (`:144`) | Extracted in 34-06 precisely for testability |

**Key insight:** the shipped Phase 33–35 layer was written with this phase named in its own docstrings (`finance/schemas.py:144`: "machine-readable for the UI caption **and for Phase 36 AI**"; `finance_scrub.py`: "Phase 34/36 wire this in"; `alert_types.py` via STATE.md: "FINANCIAL_ALERT_TYPES ships empty — ready for Phase 36 to populate"). Any new financial computation in this phase is a signal that something shipped is being restated.

---

## Common Pitfalls

### Pitfall 1: Assuming the Phase 26 non-streaming path retries on transient API errors
**What goes wrong:** D-10 says "reuse the Phase 26 cron job's ... retry envelope". A planner reasonably assumes `call_claude_json` retries. **It does not.** Verified: `ai_utils.py:73-107` makes exactly one `messages.create` call, raises `ValueError` on empty content, and returns the caller's `fallback` on bad JSON. The exponential-backoff retry (`_RETRY_DELAYS = [1.0, 2.0, 4.0]`, retrying only `APITimeoutError` / `RateLimitError`) lives at `ai/service.py:323-352` and is an **async generator for streaming chat** — not reusable here.
**How to avoid:** Treat the Phase 26 envelope as: the model constant, the 30s timeout, `gather_with_concurrency`'s per-item exception swallowing, and the fallback policy. If transport resilience is wanted, add it deliberately as a small non-generator helper — and keep `GROUNDING_RETRY_LIMIT` (the D-05 validation retry) named distinctly.
**Warning signs:** A plan task says "reuse the retry envelope" without naming which function.

### Pitfall 2: The `fallback` parameter silently fabricating a finding
**What goes wrong:** `call_claude_json` returns `fallback` on unparseable JSON (`:99-107`). A finding built from a fallback dict would be published with no AI content behind it — a direct SC3 violation.
**How to avoid:** Add `call_claude_json_strict()` that raises. Findings fail closed: drop + log.
**Warning signs:** `fallback={...}` appears anywhere in the profitability service.

### Pitfall 3: Two independent alert-type literals
**What goes wrong:** `alert_types.py`'s docstring says the DB CHECK and `FINANCIAL_ALERT_TYPES` "are both expressed here so a new alert type can never be registered in one and forgotten in the other" — but `dashboard/models.py:59-70` **hardcodes the value list again** as an ORM `CheckConstraint` string. Update the migration and `alert_types.py` only, and the ORM diverges from the DB.
**How to avoid:** One task changes all three; a test inserting a `DashboardAlert` with the new type through the ORM catches it.

### Pitfall 4: Cumulative-vs-per-month trend confusion (D-03 #1)
**What goes wrong:** `trend_buckets` are **cumulative as-of replays**. Reading "margin declined 5 points across the last 2 buckets" as a per-month delta silently changes the sensitivity by an order of magnitude.
**How to avoid:** Document the cumulative reading in the constant's docstring; unit-test with a fixture where cumulative and per-month deltas disagree in sign.
**Warning signs:** A test that computes a month's standalone margin.

### Pitfall 5: The quote-implied signal firing on quote-only projects
**What goes wrong:** For a project whose revenue basis is entirely `quoted`, billed revenue *is* quote revenue — the gap is identically zero, and any rounding artifact becomes a false positive.
**How to avoid:** Require ≥1 `invoiced` anchor in the comparable set. Test the quoted-only project asserting **no** candidate.

### Pitfall 6: Alert noise (PITFALLS.md #6/#8)
**What goes wrong:** PITFALLS #8 is explicit: threshold alerts that over-fire get ignored wholesale, poisoning the whole feature. Three D-03 signals × nightly × every project is a lot of surface.
**How to avoid:** All four bounds are already decided — eligibility gate, candidate-only AI, fingerprint dedup, per-company nightly cap. Ensure the cap is *counted after validation* so dropped findings don't consume it, and that a same-fingerprint recurrence never re-alerts.
**Warning signs:** Findings count grows monotonically across nightly runs in the exactly-once test.

### Pitfall 7: Non-finance leakage through a surface nobody enumerated (SC2)
**What goes wrong:** Registration in `FINANCIAL_ALERT_TYPES` covers `GET /alerts`. It does **not** cover: the FCM recipient list, the new findings endpoint, or the AI chat/checklist surfaces.
**How to avoid:** Four assertions in one keystone test — dashboard alerts filtered, endpoint 403, FCM recipients ⊆ `finance.view` holders, and no dollar figure in checklist/chat output for a contractor. Note `scrub_finance_fields` is **shallow** (`finance_scrub.py:29-38`, documented) and `FINANCE_FIELD_NAMES` does not include this phase's field names (`revenue`, `revenue_basis`, `margin_percent`, `corrective_action`) — extend the set if any non-finance dict-builder is touched.
**Warning signs:** A test asserting only the dashboard-alerts half.

### Pitfall 8: Unburdened labor unlabelled in the finding (PITFALLS #2)
**What goes wrong:** v4.0 labor is wage-only. PITFALLS #2: "AI profitability analysis must be given the burdened figure, not raw wages, or its margin erosion flags will be wrong from the start." Burden is deferred, so the only honest mitigation is labelling.
**How to avoid:** `labor_basis: "unburdened"` (shipped default, `schemas.py:127`) travels in the payload; the prompt requires the finding acknowledge it when labor is material to the claim; the UI-SPEC locks the caption.

### Pitfall 9: Fabricated 100%/0% margins reaching the AI (PITFALLS #9)
**What goes wrong:** `SUM()` over no rows is `0`, producing a fabricated 100% margin that the AI then treats as a baseline.
**How to avoid:** D-01's `margin.incomplete is False` gate already excludes exactly this case (`INCOMPLETE_NO_COST_DATA`, `margin_math.py:143-145, 155-162`). Test with a revenue-bearing zero-cost project asserting it is **skipped** with the right reason.

### Pitfall 10: Test-suite deadlock under parallel agents
**What goes wrong:** STATE.md (Phase 35 blocker): "backend suites run red under parallel agent execution — `conftest.py` TRUNCATEs all tables per test, which deadlocks when two pytest processes share `contractorhub_test`. A deadlock inside `seed_two_tenants` is contention, not a regression."
**How to avoid:** Run Phase 36 backend suites serially. Do not debug a `seed_two_tenants` deadlock as a code fault.

### Pitfall 11: Background FCM task garbage-collected
**What goes wrong:** `asyncio` holds only weak references to tasks; a bare `create_task` can be collected mid-flight.
**How to avoid:** Module-level `set` + `add_done_callback(set.discard)` — `budget_service.py:63-65, 431-442` and `checklists/service.py:192-203`.

---

## Code Examples

### Verified: Claude call in a batch job
```python
# Source: backend/app/core/ai_utils.py:73-107
client = get_anthropic_client()
response = await client.messages.create(
    model=CLAUDE_MODEL,          # "claude-sonnet-4-6"
    max_tokens=CLAUDE_MAX_TOKENS,
    system=system_prompt,
    messages=[{"role": "user", "content": user_content}],
)
if not response.content:
    raise ValueError(...)
cleaned = strip_fences(response.content[0].text)
return json.loads(cleaned)   # STRICT for findings — no fallback
```

### Verified: exactly-once claim before writing the alert
```python
# Source: backend/app/features/finance/budget_service.py:364-392
async def _fire_threshold(self, budget, threshold, spent, context):
    if not await self.repository.claim_threshold(budget.id, threshold):
        return None
    alert = await AlertRepository(self.db).create(self._build_alert(...))
    return FiredBudgetAlert(alert_id=alert.id, ...)
```

### Verified: finance recipients from the live permission matrix
```python
# Source: backend/app/features/finance/budget_service.py:417-424
async def _recipients_for(self, company_id):
    from app.features.rbac.repository import RbacRepository
    return await RbacRepository(self.db).user_ids_with_permission(company_id, "finance.view")
```

### Verified: idempotent nightly upsert
```python
# Source: backend/app/features/checklists/repository.py:53-79
stmt = (
    pg_insert(Model).values(...)
    .on_conflict_do_update(
        index_elements=["company_id", "fingerprint"],
        index_where=text("deleted_at IS NULL AND resolved_at IS NULL"),
        set_={...},                      # NEVER alerted_at
    )
    .returning(Model)
)
```

### Verified: alert-type CHECK expansion (0035 precedent for 0036)
```python
# Source: backend/migrations/versions/0035_budget_alerts_and_quote_chain.py:37-45
op.execute("ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check")
op.execute("""
    ALTER TABLE dashboard_alerts
    ADD CONSTRAINT dashboard_alerts_alert_type_check
    CHECK (alert_type IN (
        'schedule_slip','rescheduling_suggestion','dependency_risk',
        'budget_warning','budget_overrun','ai_profitability'
    ))
""")
```

### Verified: mocking Claude in backend tests
```python
# Source: backend/tests/test_phase_26_e2e.py:144-153, 189-196
def _make_mock_anthropic_response(content: dict | str) -> MagicMock:
    text = json.dumps(content) if isinstance(content, dict) else content
    mock_content = MagicMock(); mock_content.text = text
    mock_response = MagicMock(); mock_response.content = [mock_content]
    return mock_response

with (
    patch("app.core.ai_utils.get_anthropic_client") as mock_client,
    patch("app.features.notifications.service.NotificationService.send_checklist_notification",
          new_callable=AsyncMock),
):
    mock_client.return_value.messages.create = AsyncMock(return_value=mock_response)
    # multi-turn (validate-then-retry): AsyncMock(side_effect=[first, second])
```

### Verified: driving a cron service directly with RLS context in a test
```python
# Source: backend/tests/test_phase_26_e2e.py:198-212
async with async_session_factory() as db:
    # PostgreSQL SET LOCAL rejects parameterized $1 — f-string required
    await db.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
    svc = ProfitabilityService(db)
    await svc.analyze_company(company_id=uuid.UUID(company_id), target_date=today)
    await db.commit()
```

---

## Runtime State Inventory

Not applicable — Phase 36 is additive feature work, not a rename/refactor/migration. No existing string, key, collection, or registration is being renamed.

One adjacent item worth noting: **migration 0036 must be applied to the local Docker DB** with `docker compose up migrate` (CLAUDE.md), and the test DB picks it up automatically on the next pytest run (conftest runs `alembic upgrade head`).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| PostgreSQL | Findings table, RLS, test DB | ✓ | 15.0, accepting connections on :5432 | — |
| Docker | `docker compose up migrate` after 0036 | ✓ | running | Apply `alembic upgrade head` directly |
| `anthropic` SDK | Claude batch call | ✓ | 0.86.0 in `backend/.venv` | — |
| `ANTHROPIC_API_KEY` | Live Claude calls | ✓ | present in `backend/.env` | Tests never need it — `get_anthropic_client()` is patched (Phase 26 precedent) |
| Node.js | Web build/tests | ✓ | v20.18.1 | — |
| Playwright | Web E2E | ✓ | 1.58.2 | — |
| APScheduler | Cron registration | ✓ | 3.10.4 pinned | — |
| Firebase credentials | Real FCM delivery | Not probed | — | `NotificationService._resolve_messaging` returns `None` and the send is a graceful no-op (`notifications/service.py:326-327`); tests patch the send method |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** Firebase credentials only — already handled by shipped graceful degradation.

---

## Validation Architecture

`.planning/config.json` does not exist, so `workflow.nyquist_validation` is absent → treated as **enabled**.

### Test Framework

| Property | Value |
|---|---|
| **Backend framework** | pytest + pytest-asyncio (`asyncio_mode = "auto"`, `testpaths = ["tests"]`) + httpx `AsyncClient` against the real `contractorhub_test` DB; conftest force-selects `DATABASE_URL`, runs `alembic upgrade head`, `clean_tables` autouse |
| **Backend config file** | `backend/pyproject.toml` → `[tool.pytest.ini_options]` |
| **Backend quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_36_e2e.py -q` |
| **Backend unit quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/unit/test_profitability_math.py tests/unit/test_ai_grounding.py -q` |
| **Backend full suite** | `cd backend && source .venv/bin/activate && python -m pytest -q` (~25 min; **run serially** — STATE.md parallel-truncate deadlock) |
| **Web unit framework** | Jest 30 + ts-jest + jsdom + @testing-library/react (`web/jest.config.ts`) |
| **Web unit quick run** | `cd web && npx jest "src/app/(dashboard)/financials"` |
| **Web E2E framework** | Playwright 1.58.2, chromium project, `webServer: npm run dev`; specs mock `/api/proxy` — no live backend |
| **Web E2E quick run** | `cd web && npx playwright test tests/phase-36-ai-findings.spec.ts` |
| **Static gates** | `cd backend && ruff check . && ruff format --check .`; `cd web && npm run lint && npx tsc --noEmit` |
| **Estimated runtime** | ~30s per-task quick runs |

### Phase Requirements → Test Map

| Req | Behavior | Type | Automated command | File exists? |
|---|---|---|---|---|
| **SC3 / D-05** ★ | A finding citing a figure absent from the payload is blocked after one retry and never published (zero findings, zero alerts) | integration | `pytest tests/test_phase_36_e2e.py::test_unmatched_figure_blocked_after_one_retry -x` | ❌ Wave 0 |
| **D-06** ★ | The same erosion fingerprint alerts exactly once across three nightly runs, then re-fires when it worsens a band | integration | `pytest tests/test_phase_36_e2e.py::test_fingerprint_alerts_exactly_once_across_three_runs -x` | ❌ Wave 0 |
| **SC2 / FINAI-02** ★ | Non-finance roles see no AI findings anywhere: dashboard alerts filtered, findings endpoint 403, FCM recipients ⊆ finance.view holders, no dollar figures in checklist/chat output | integration | `pytest tests/test_phase_36_e2e.py::test_non_finance_sees_no_ai_findings_anywhere -x` | ❌ Wave 0 |
| SC3 / D-05 | Grounded finding with only payload-sourced figures publishes on the first call (no retry consumed) | integration | `pytest tests/test_phase_36_e2e.py::test_grounded_finding_publishes_without_retry -x` | ❌ Wave 0 |
| SC3 / D-05 | Retry succeeds: first response unmatched, second grounded → published | integration | `pytest tests/test_phase_36_e2e.py::test_grounding_retry_succeeds_on_second_attempt -x` | ❌ Wave 0 |
| SC3 / D-05 | Figure extraction + matching: thousands separators, stripped `.00`, one-decimal percents, whole-dollar rounding, fabricated `$0` rejected | unit | `pytest tests/unit/test_ai_grounding.py -q` | ❌ Wave 0 |
| D-01 | Non-active project skipped with reason | integration | `pytest tests/test_phase_36_e2e.py::test_skips_non_active_project -x` | ❌ Wave 0 |
| D-01 | Project with no revenue source skipped | integration | `pytest tests/test_phase_36_e2e.py::test_skips_project_without_revenue_source -x` | ❌ Wave 0 |
| D-01 / Pitfall 9 | Revenue-bearing zero-cost project (fabricated ~100% margin) skipped, never analyzed | integration | `pytest tests/test_phase_36_e2e.py::test_skips_incomplete_cost_data_project -x` | ❌ Wave 0 |
| D-01 | Project with unrated labor hours (incomplete flag) skipped | integration | `pytest tests/test_phase_36_e2e.py::test_skips_unrated_labor_project -x` | ❌ Wave 0 |
| D-02 | Non-candidate eligible projects never reach the Claude client (call count == candidate count) | integration | `pytest tests/test_phase_36_e2e.py::test_only_candidates_reach_claude -x` | ❌ Wave 0 |
| D-02 | AI dismissal persists nothing and alerts nothing | integration | `pytest tests/test_phase_36_e2e.py::test_ai_dismissal_publishes_nothing -x` | ❌ Wave 0 |
| D-03 #1 | ≥5pt cumulative margin decline across the last two buckets flags; 4.9pt does not; `None` percents never coerce to 0; window setting never changes detection | unit | `pytest tests/unit/test_profitability_math.py -q -k decline` | ❌ Wave 0 |
| D-03 #2 | Negative margin flags via `margin`, including at zero-revenue where `margin_percent` is None | unit | `pytest tests/unit/test_profitability_math.py -q -k negative` | ❌ Wave 0 |
| D-03 #3 | Quote-implied gap uses latest approved quote per anchor **including invoiced anchors**; compares only the shared anchor set; quoted-only project produces no candidate | unit | `pytest tests/unit/test_profitability_math.py -q -k quote_implied` | ❌ Wave 0 |
| D-03 #3 | End-to-end: a project invoiced below its approved quote produces a candidate | integration | `pytest tests/test_phase_36_e2e.py::test_quote_implied_gap_produces_candidate -x` | ❌ Wave 0 |
| D-06 | Fingerprint is stable across runs for identical inputs and changes on band change | unit | `pytest tests/unit/test_profitability_math.py -q -k fingerprint` | ❌ Wave 0 |
| D-06 | Condition clears then recurs → a second alert fires | integration | `pytest tests/test_phase_36_e2e.py::test_cleared_then_recurring_condition_realerts -x` | ❌ Wave 0 |
| D-06 | Same-day re-run creates no duplicate finding and no duplicate alert (idempotency) | integration | `pytest tests/test_phase_36_e2e.py::test_same_day_rerun_is_idempotent -x` | ❌ Wave 0 |
| D-07 | `ai_profitability` accepted by the DB CHECK **through the ORM** (migration + `models.py` literal in sync) | integration | `pytest tests/test_phase_36_e2e.py::test_ai_profitability_alert_type_accepted_by_orm -x` | ❌ Wave 0 |
| D-07 | FCM recipients equal the live `finance.view` holder set after a matrix change (never role-name literals) | integration | `pytest tests/test_phase_36_e2e.py::test_push_recipients_follow_live_permission_matrix -x` | ❌ Wave 0 |
| D-09 | `alert_summary` ≤ 280 chars enforced; over-length rejected, never truncated silently | integration | `pytest tests/test_phase_36_e2e.py::test_alert_summary_length_contract -x` | ❌ Wave 0 |
| D-10 | Per-company nightly findings cap honored; cap counted after validation | integration | `pytest tests/test_phase_36_e2e.py::test_per_company_findings_cap -x` | ❌ Wave 0 |
| D-10 / FINAI-01 | Cron job registered with the expected id and trigger (`_register_jobs` on a bare scheduler) | integration | `pytest tests/test_phase_36_e2e.py::test_profitability_job_registered -x` | ❌ Wave 0 |
| FINAI-01 | Claude API failure for one project does not abort the company run; other candidates still produce findings | integration | `pytest tests/test_phase_36_e2e.py::test_claude_failure_isolated_per_candidate -x` | ❌ Wave 0 |
| FINAI-01 | Tenant B cannot read tenant A's findings (RLS) | integration | `pytest tests/test_phase_36_e2e.py::test_findings_rls_isolation -x` | ❌ Wave 0 |
| D-08 | Latest finding endpoint returns the newest unresolved finding; `null`/empty state when none | integration | `pytest tests/test_phase_36_e2e.py::test_latest_finding_endpoint -x` | ❌ Wave 0 |
| D-08 | Finding card renders narrative + corrective action; empty state; failing finding query does not blank the drill-down | unit (jest) | `npx jest "src/app/(dashboard)/financials"` | ❌ Wave 0 |
| D-08 / SC2 | `/financials/[projectId]` renders the finding for a finance user; a non-finance user sees the deny panel **and** zero finding requests are issued | e2e | `npx playwright test tests/phase-36-ai-findings.spec.ts` | ❌ Wave 0 |

★ = the three keystone tests named in CONTEXT § Specific Ideas.

### Sampling Rate

- **Per task commit:** `pytest tests/test_phase_36_e2e.py -q` and/or `pytest tests/unit/test_profitability_math.py tests/unit/test_ai_grounding.py -q` and/or `npx jest "src/app/(dashboard)/financials"`, plus the touched layer's linter (`ruff check .` / `npm run lint && npx tsc --noEmit`).
- **Per wave merge:** `pytest tests/test_phase_3{3,4,5,6}_e2e.py tests/unit -q` + `npm test` + both static gates.
- **Phase gate:** full backend suite (serial), `npm test`, `npm run test-e2e`, `ruff check . && ruff format --check .` — all green before `/gsd:verify-work`.
- **Max feedback latency:** ~30 seconds outside the sanctioned phase-gate full suites.

### Wave 0 Gaps

- [ ] `backend/tests/test_phase_36_e2e.py` — all integration/E2E rows above
- [ ] `backend/tests/unit/test_profitability_math.py` — D-03 signals, bands, fingerprint stability
- [ ] `backend/tests/unit/test_ai_grounding.py` — extraction + matching + tolerance rules
- [ ] `web/tests/phase-36-ai-findings.spec.ts` — Playwright, mocked `/api/proxy`, log in through the UI then SPA-navigate (a hard `page.goto` resets Redux auth and disables permission-gated UI — `.claude/skills/e2e-feature-tests/SKILL.md`)
- [ ] `web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx` — card rendering + states
- [ ] No framework install needed — pytest, Jest and Playwright are all present and configured

**Mocking the Claude API in tests (precedent, verified):** patch `app.core.ai_utils.get_anthropic_client` and set `mock_client.return_value.messages.create = AsyncMock(...)`. Use `return_value=` for single-turn and `side_effect=[first, second]` for the validate-and-retry paths. Build responses with the `_make_mock_anthropic_response` helper (`tests/test_phase_26_e2e.py:144-153`) — copy it into the Phase 36 test file rather than importing across test modules (the Phase 26 file is self-contained by convention). Patch `NotificationService.send_*` with `new_callable=AsyncMock` to keep FCM out of the loop, and assert recipient sets through `RbacRepository` instead.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| AI given raw ORM rows / "estimate the numbers" | Pre-computed aggregate payload + validate-and-block on every cited figure | This phase (D-05); PITFALLS #6 anticipated it | SC3 becomes mechanically verifiable rather than a prompt-engineering hope |
| Threshold alerts fire on every evaluation | Claim-first atomic UPDATE, exactly once | Phase 34 (34-03) | The dedup model this phase extends with fingerprints |
| `FINANCIAL_ALERT_TYPES` shipped empty, filter provably inert | Populated with budget types (Phase 34), extended with `ai_profitability` here | Phase 30 → 34 → 36 | Registration alone gates dashboard visibility |
| `finance_scrub` shipped unwired to avoid dead code | Wire only where a real non-finance dict-builder emits finance fields | Phase 30 D-11 → 34/36 | Do not wire it speculatively; assert the posture by test |
| Per-project rollup called in a loop for company views | One batched read path, constant query count, pinned by an equivalence test | Phase 35 (35-05/35-08) | The eligibility pass rides this for free |

**Deprecated / not to be reused here:**
- `ACTIVE_PROJECT_STATUSES = ("planning", "active")` (`ai_utils.py:39`) — includes `planning`; wrong for D-01.
- `call_claude_json(..., fallback=...)` for findings — silent fabrication path.
- `ai/service.py::_call_with_retry` — streaming-only async generator, not usable in a batch job.

---

## Open Questions

1. **Severity-band boundaries and their count** *(Claude's discretion, but load-bearing for D-06 re-fire behavior)*
   - What we know: `dashboard_alerts_severity_check` allows `info|warning|critical`; the band lives inside the fingerprint, so band count directly determines how often a worsening condition re-alerts.
   - What's unclear: whether two bands (warning/critical) or three gives the right re-alert cadence per signal. Too many bands = a re-alert every time a number drifts.
   - Recommendation: **two bands**, boundaries as named Decimals per signal, decided in planning and unit-tested at the boundary. Three bands can be added later without a migration if the CHECK lists band values generously or omits a band CHECK.

2. **Whether the quote-implied signal should compare at project level or per anchor**
   - What we know: D-03 says "for the same anchor set", which the project-level intersection satisfies.
   - What's unclear: a project could have one badly-underbilled scope masked by others. Per-anchor detection would catch it but multiplies candidate volume and fingerprints.
   - Recommendation: **project-level for this milestone** (matches D-03's wording and the noise-bounded posture); the payload still carries per-anchor context so the AI's corrective action can name the specific scope. Revisit with the deferred "broader AI finding menu".

3. **Trend cost for the candidate pass at company scale**
   - What we know: `margin_trend` is 6 bounded queries per project; 34-02 established that a bounded service call per project is permitted (the N+1 rule targets per-row queries).
   - What's unclear: the actual cost at, say, 100 active projects. Phase 35 measured the *company rollup* at 127/199/252 ms medians but never measured N trend replays.
   - Recommendation: run the eligibility gate **first** so trends run only for eligible projects; add a query-count test analogous to `test_company_rollup_query_count_is_constant_in_project_count` asserting the count is `O(eligible)` and **not** `O(all projects)`. If it proves hot, the fix is company-wide dated queries in `PortfolioRepository` — but do not pre-build them.

4. **Whether findings need a retention/pruning policy**
   - What we know: nothing in the codebase prunes `dashboard_alerts` or `daily_checklists`; resolve-then-reinsert accumulates history.
   - Recommendation: no pruning this phase (consistent with every sibling table); soft-delete exists if needed later. Flag it in the phase's deferred items.

5. **`response.usage` token accounting in the run log** *(MEDIUM confidence)*
   - What we know: `response.usage.input_tokens` / `.output_tokens` are available on the Anthropic Python SDK response (confirmed by current SDK docs; SDK 0.86.0 installed). No shipped code in this repo reads `usage` today.
   - Recommendation: read it defensively (`getattr(response, "usage", None)`) for the log line only; never let a missing `usage` fail a run.

---

## Sources

### Primary (HIGH confidence) — shipped code, read directly

- `backend/app/core/ai_utils.py` — model/token/timeout constants (28-33), client singleton (49-62), `strip_fences` (65-70), `call_claude_json` (73-107), `gather_with_concurrency` (110-130)
- `backend/app/core/scheduler.py` — cron constants (34-41), `_run_for_all_companies` (44-93), job wrappers (96-141), `_register_jobs` (144-168)
- `backend/app/core/finance_scrub.py` — `FINANCE_FIELD_NAMES`, `scrub_finance_fields` (shallow, documented)
- `backend/app/core/base_models.py`, `base_repository.py`, `base_service.py`, `config.py:22`
- `backend/app/features/finance/margin_math.py` — bases (26-35), `missing_cost_data` (143-145), `margin_percent_for` (148-152), `summarize_margin` (165-186), `quoted_revenue` (189-191), `anchor_revenues` (194-217), `combined_anchor_revenue` (220-230)
- `backend/app/features/finance/trend_math.py` — bucket semantics docstring (1-32), `TrendInputs`/`TrendBucket` (109-133), `trend_buckets` (156-171), `window_slice` (174-181)
- `backend/app/features/finance/budget_math.py` — thresholds (22-24), `percent_used` (72-77), `crossed_thresholds` (80-82), `format_alert_money`/`format_alert_percent` (85-92)
- `backend/app/features/finance/portfolio_math.py` — `ProjectFinancialFigures` (65-77), `AttentionEntry` (80-92), `attention_entries` (136-139), `portfolio_totals` (142-150)
- `backend/app/features/finance/portfolio_service.py` — `_project_figures` (295-316), `company_financials` (422-430), `project_financials` (432-458), `margin_trend` (460-473), `_trend_inputs` (475-496), `_fetch_portfolio_inputs` (498-521)
- `backend/app/features/finance/portfolio_repository.py` — `list_projects` (117-124), `category_totals_by_project` (126-158), `approved_quote_amounts_by_project` (177-184), `dated_*` (208-241)
- `backend/app/features/finance/service.py` — `ProjectCostRollup` (92-102), `ProjectMarginContext` (104-112), `_contributing_anchor_cost` (145-151), `_any_anchor_missing_cost_data` (154-161), `_build_breakdown` (164-189), `rollup_for_project` (348-372)
- `backend/app/features/finance/repository.py` — `approved_quote_amounts_query` (332-363)
- `backend/app/features/finance/budget_service.py` — push data (59-100), `evaluate_budget` (216-239), `sweep_budgets` (315-355), `_fire_threshold` (364-392), `_recipients_for` (417-424), push scheduling (426-466)
- `backend/app/features/finance/schemas.py` — `LaborCostSummary.basis = "unburdened"` (115-131), `MarginSummary` + "for Phase 36 AI" (139-162), Decimal-as-string note (86-87)
- `backend/app/features/finance/router.py` — `require_permission("finance.view")` route pattern (93-135)
- `backend/app/features/dashboard/alert_types.py` (whole file), `dashboard/models.py` (CheckConstraints 59-70), `dashboard/service.py::get_alerts` (736-755), `dashboard/router.py` (85-99)
- `backend/app/features/checklists/service.py` (whole file — the sibling job), `checklists/repository.py::upsert_checklist` (41-79), `checklists/prompts/checklist_system.py`
- `backend/app/features/notifications/service.py` — `send_budget_alert_notification` (310-337), `_resolve_messaging`/`_dispatch_to_tokens` (424-442)
- `backend/app/features/rbac/repository.py::user_ids_with_permission` (68-71)
- `backend/app/features/ai/service.py` — streaming-only retry (83-85, 323-352)
- `backend/app/features/projects/models.py` — project status CHECK (77)
- `backend/migrations/versions/0032_financial_schema_and_rbac.py` (RLS block 153-196), `0035_budget_alerts_and_quote_chain.py` (37-70)
- `backend/tests/test_phase_26_e2e.py` — Claude mock helper (144-153), patch sites (189-196), RLS-in-test pattern (198-212)
- `backend/tests/conftest.py` — fixtures (`seed_two_tenants`, `tenant_a_client`, `tenant_b_client`, `clean_tables`)
- `backend/pyproject.toml` (`[tool.pytest.ini_options]`), `backend/requirements.txt` (1-21)
- `web/src/app/(dashboard)/financials/layout.tsx` (FinanceGate + the render-vs-request comment), `[projectId]/_components/project-financials-dashboard.tsx` (whole file), `src/features/finance/types.ts`, `src/features/finance/hooks.ts`
- `web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx` (severity config 22-38, impact/remediation rendering 108-124)
- `.planning/phases/36-ai-profitability-analysis/36-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md:441-448`, `.planning/STATE.md`, `.planning/research/PITFALLS.md` (#2, #6, #8, #9, #10 + performance/security tables), `.planning/phases/33-profit-margin-tracking/33-CONTEXT.md` (D-05..D-07, D-12..D-14), `.planning/phases/35-web-financial-dashboard/35-VALIDATION.md`
- `CLAUDE.md`, `.claude/skills/e2e-feature-tests/SKILL.md`, `~/.agents/skills/clean-code/SKILL.md`

### Environment probes (HIGH confidence)
- `anthropic 0.86.0` (`backend/.venv/bin/python -c "import anthropic; print(anthropic.__version__)"`)
- `psql (PostgreSQL) 15.0`; `pg_isready` → accepting connections
- `docker info` → running; `node --version` → v20.18.1; `npx playwright --version` → 1.58.2
- `ANTHROPIC_API_KEY` present in `backend/.env`

### Secondary (MEDIUM confidence)
- Anthropic Messages API `response.usage.input_tokens` / `.output_tokens` — [Claude Platform Docs: Using the Messages API](https://platform.claude.com/docs/en/build-with-claude/working-with-messages), [anthropic-sdk-python](https://github.com/anthropics/anthropic-sdk-python). Consistent across sources; no shipped code in this repo reads `usage`, so treat as MEDIUM until exercised.

### Tertiary (LOW confidence)
- None. Every claim in this document is either read from shipped source or probed directly.

---

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — every version read from `requirements.txt` / the venv / `npx --version`; nothing new installed
- Architecture patterns: **HIGH** — each pattern quoted from shipped source with line references; the two novel pieces (quote-implied margin, grounding validator) are derived from verified shipped semantics and flagged as needing dedicated tests
- Pitfalls: **HIGH** — Pitfalls 1-3 and 8-11 are verified codebase facts (no-retry, fallback, duplicate CHECK literal, unburdened default, parallel-test deadlock, asyncio weak refs); 4-7 and 9 derive from shipped module docstrings and PITFALLS.md
- Validation architecture: **HIGH** — commands verified against `pyproject.toml`, `package.json`, 35-VALIDATION.md and the e2e-feature-tests skill
- Environment: **HIGH** — every row probed

**Research date:** 2026-07-28
**Valid until:** 2026-08-27 (30 days — this is integration research against a stable in-repo codebase; it invalidates only if Phase 33-35 code changes, not on any external release)
