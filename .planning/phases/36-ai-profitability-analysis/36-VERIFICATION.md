---
phase: 36-ai-profitability-analysis
verified: 2026-07-29T23:55:45Z
status: passed
score: 3/3 success criteria verified (39/39 plan must-have truths, 24/24 artifacts, 22/22 key links)
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
verifier_reruns:
  backend: "pytest tests/test_phase_36_e2e.py tests/unit -q → 272 passed in 183.73s"
  web_unit: "npx jest src/features/finance 'src/app/\\(dashboard\\)/financials' → 236 passed, 12 suites"
  backend_static: "ruff check . → All checks passed; ruff format --check . → 319 files already formatted"
  web_static: "npx tsc --noEmit → clean (exit 0); npm run lint → clean (--max-warnings 0)"
  web_e2e: "not re-run by verifier (needs dev server); executor-attested 6/6 on tests/phase-36-ai-findings.spec.ts. Every browser-level assertion has an equivalent jest or pytest guard (see Behavioral Spot-Checks)."
---

# Phase 36: AI Profitability Analysis — Verification Report

**Phase Goal:** AI proactively watches every project's financial health so Owner/PM catches margin erosion before it compounds, with every claim grounded in real data
**Verified:** 2026-07-29T23:55:45Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every active project is analyzed by AI on a nightly schedule, and margin erosion is flagged with a specific, suggested corrective action | ✓ VERIFIED | `scheduler.py:199-204` registers `ai_profitability_analysis` on `CronTrigger(hour=6, minute=30)` inside `_register_jobs`, which `lifespan` calls; `run_ai_profitability_analysis` (`scheduler.py:155-169`) delegates via `_run_for_all_companies(method_name="analyze_company", target_date=today)`. D-01 admits only `("active",)` (`profitability_math.py:34`), deliberately narrower than `ai_utils.ACTIVE_PROJECT_STATUSES`. The corrective action is contract-bound in the prompt (§3 target + direction + one payload figure, §4 banned filler) and enforced at persistence: `_to_draft` returns None when any of the three strings is empty. `test_profitability_job_registered`, `test_profitability_job_registered_delegates_to_analyze_company`, all four `test_skips_*` |
| 2 | Owner/PM receives a finance-gated alert for each AI profitability finding — the alert is invisible to any user without finance.* permission | ✓ VERIFIED | All four channels gated. (a) Dashboard: `AI_PROFITABILITY_ALERT_TYPE ∈ FINANCIAL_ALERT_TYPES` (`alert_types.py:19`), dropped by `DashboardService.get_alerts` (`service.py:753-755`) unless `has_finance_view`. (b) Endpoint: `router.py:218` `await require_permission("finance.view")(...)` inline in the handler body. (c) FCM: `_recipients_for` reads `RbacRepository.user_ids_with_permission(company_id, "finance.view")` from the LIVE matrix — no role-name literals anywhere on the push path. (d) AI surfaces: no finding text or figure ever enters the checklist/chat dict-builders. `test_non_finance_sees_no_ai_findings_anywhere` asserts all four in one test; `test_push_recipients_follow_live_permission_matrix` re-asserts (c) after a matrix change; web-side `enabled: can(FINANCE_VIEW_PERMISSION)` stops the request too |
| 3 | Every dollar figure stated in an AI profitability finding traces to a real tool-sourced cost/margin/budget value, never an AI estimate | ✓ VERIFIED | `_build_payload` is a CLOSED value set of aggregates + named precomputed deltas (no raw cost rows, no derivable arithmetic left to the model). `collect_allowed_values` walks it, skipping `str` and `bool` on purpose so a project named "2026" can never make `$2,026` citable. `_ungrounded_literals` validates ALL THREE AI strings (narrative, corrective_action, alert_summary), so a fabricated figure cannot slip out via the alert or the push body. One retry (`GROUNDING_RETRY_LIMIT = 1`), then dropped and logged — never clipped, never partially saved. `test_unmatched_figure_blocked_after_one_retry` drives the whole publish path and asserts zero rows + zero alerts |

**Score:** 3/3 success criteria verified.

---

## Keystone Verifications (requested explicitly)

### 1. SC3 grounding — no silent-fabrication fallback path ✓ VERIFIED

- `grep "call_claude_json" backend/app/features/finance/profitability_service.py` → **only** line 39 (import) and line 517 (call), both `call_claude_json_strict`. The non-strict `call_claude_json` appears **nowhere** in the service.
- `grep -i "fallback" profitability_service.py` → **zero matches**. No positional or keyword fallback argument reaches this path.
- `call_claude_json_strict` (`ai_utils.py:122-156`) has **no `fallback` parameter** in its signature and calls `json.loads(raw_text)` bare — a `JSONDecodeError` propagates. Its docstring names the exact hazard: the non-strict sibling "degrades to a caller-supplied default dict on bad JSON, which is a harmless degradation for a checklist and a silent-fabrication path for a grounded finding (SC3)."
- The raised error is isolated per candidate by `gather_with_concurrency`'s per-item try/except (returns `None`), so a fail-closed candidate cannot abort the company run — and `None` is skipped in `_persist_publishable`.
- Grounding is pure set membership against a closed set; unmatched → one retry turn naming the offending literals verbatim → still unmatched → `logger.warning(UNGROUNDED_DROP_LOG_TEMPLATE)` and `return None`. **Never published.**

### 2. D-06 keep-set resolves against qualifying, not published ✓ VERIFIED

- `publish_findings` returns `PublishResult(published=…, qualifying_fingerprints=[candidate.candidate.fingerprint for candidate in candidates])` — built from **every candidate tonight**, `candidates`, not from `published`.
- `analyze_company` calls `resolve_absent_fingerprints(result.qualifying_fingerprints)`. The dataclass docstring names all three drop reasons the keep-set must survive (raised Claude call, length-contract failure, nightly cap).
- **The guard test exists and is meaningful.** `test_transient_claude_failure_does_not_resolve_or_realert` (`tests/test_phase_36_e2e.py:1993`) runs three nights: night 1 publishes and alerts; night 2's Claude call raises `RuntimeError`; night 3 succeeds. It asserts `create.call_count == 1` on night 2 (a transport error consumes no D-05 retry), then that the row is **the same id**, `resolved_at is None`, `last_confirmed_on` still night 1, and `_ai_profitability_alert_count == 1`. After night 3: same id, still unresolved, `last_confirmed_on` advanced to night 3, and **still exactly one alert**. Built from `published`, night 2 would resolve the row and night 3 would insert a fresh unalerted row and fire a second alert — the test would fail on both the id and the alert-count assertions. Not a tautology.
- `test_unmatched_figure_blocked_after_one_retry` additionally asserts `len(result.qualifying_fingerprints) == 1` for a dropped candidate, pinning the same invariant from the grounding side.

### 3. D-01 eligibility — ineligible projects never reach the AI ✓ VERIFIED

- `skip_reason_for` is a four-rung ladder: `NOT_ACTIVE` → `NO_REVENUE_SOURCE` → `NO_COST_DATA` → `INCOMPLETE_DATA`.
- **Ordering is load-bearing and correct:** `scan_candidates` runs `_partition_by_eligibility` BEFORE `_candidates_for`, so ineligible projects get no trend replay (statement count is O(eligible)) and, critically, are never wrapped into a `ProfitabilityCandidate` — and only candidates are passed to `gather_with_concurrency(candidates, self._draft_for)`. There is no code path from a skipped project to `call_claude_json_strict`.
- Every skip is logged by name (`_log_skips`), plus one per-company summary line. Logging asserted through `structlog.testing.capture_logs` with the templates rendered at the call site (the executor correctly found that `caplog` observes nothing under this app's structlog→stdlib bridge, so a `caplog` assertion would have passed no matter what).
- Tests: `test_skips_non_active_project` (draft), `test_skips_project_without_revenue_source`, `test_skips_incomplete_cost_data_project` (Pitfall 9 fabricated ~100% margin), `test_skips_unrated_labor_project`, and `test_only_candidates_reach_claude` (5 eligible, 2 candidates, `create.call_count == 2`).

### 4. D-03 signal 3 does not take its quote leg from `anchor_revenues` ✓ VERIFIED

- `latest_quote_per_anchor` (`profitability_math.py:175-188`) is the quote leg and includes anchors that have invoices; its docstring states exactly why the shipped resolution cannot supply it ("it drops approved quotes at invoiced anchors by design").
- `quote_implied_gap` takes the **quote-implied** revenue from `_quote_implied_revenue(inputs.latest_quotes, comparable)` — never from `resolved`. `resolved` (which the service builds from `anchor_revenues`) is used **only** for the billed leg (`_billed_revenue`) and for the `_has_billed_anchor` tautology guard, which are its correct roles.
- `comparable = resolved.keys() & latest_quotes.keys()` restricts to the shared anchor set; `_has_billed_anchor` rejects the Pitfall-5 tautology (and an empty comparable set), so a quote-only project can never produce a candidate.
- Tests: `pytest tests/unit/test_profitability_math.py -k quote_implied` plus E2E `test_quote_implied_gap_produces_candidate` (invoiced below an approved quote at the same anchor).

### 5. SC2 four-channel gating ✓ VERIFIED

`test_non_finance_sees_no_ai_findings_anywhere` (`tests/test_phase_36_e2e.py:2643`) is a genuine four-channel test, not a dashboard-only test wearing a keystone label:

1. **Dashboard alerts** — asserted **positively for the PM and negatively for the contractor** on the same project, so the negative half cannot pass because a URL was wrong or a fixture was empty.
2. **Endpoint** — contractor gets `403`, and `_LIFECYCLE_NARRATIVE not in refused.text` (the body carries no leak either).
3. **FCM** — `recipients <= finance_holders` (read live from `RbacRepository`), `contractor_id not in recipients`, `project_manager_id in recipients`.
4. **AI surfaces** — real `ChecklistService.generate_daily_checklists` run for the analyzed project, asserting `"$" not in surface` and none of `("revenue", "margin_percent", "corrective_action")` in **both the captured Claude prompt** (what the shipped dict-builder puts on the wire) **and** the contractor's `/checklists/today` response.

Web-side equivalents also verified: `useProjectProfitabilityFinding` gates the fetch with `enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId`, and the jest test `"issues zero finding requests when the user lacks finance.view"` pins it independent of the browser.

### 6. Phase 30 D-06 boundary — no financial leakage into ungated surfaces ✓ VERIFIED (with two pre-existing notes)

The finding's text is reachable through exactly three surfaces, and all three are gated: `GET /projects/{id}/financials/finding` (finance.view), the `DashboardAlert` (dropped by `FINANCIAL_ALERT_TYPES`), and the FCM push (finance.view holders). Phase 36 correctly chose the **stronger** posture over scrubbing: financial data never enters the checklist/chat AI context at all, so there is nothing to scrub. See "Anti-Patterns / Observations" #3 and #4 for two pre-existing, Phase-30/34-owned boundary notes that Phase 36 inherits (both carry zero dollar figures or require an unguessable UUID a non-finance caller has no path to obtain).

---

## Required Artifacts (Levels 1–4)

| Artifact | Provides | Exists | Substantive | Wired | Data flows | Status |
|---|---|---|---|---|---|---|
| `backend/migrations/versions/0036_ai_profitability_findings.py` | table + RLS + partial unique index + alert_type CHECK expansion | ✓ | ✓ 122 L | ✓ `down_revision=0035_budget_alerts_quote_chain` | ✓ ENABLE+FORCE RLS, policy, appuser grant, 5 CHECKs, 4 indexes | ✓ VERIFIED |
| `backend/app/features/finance/profitability_models.py` | `AIProfitabilityFinding(TenantScopedModel)` | ✓ | ✓ 105 L | ✓ imported by repository, service, schemas | ✓ ORM CHECKs interpolate the same `MAX_*` constants the service checks; `lazy="raise"` on `project` | ✓ VERIFIED |
| `backend/app/features/finance/profitability_repository.py` | upsert / claim / resolve / latest_open | ✓ | ✓ 174 L | ✓ `repository_class` on the service | ✓ `on_conflict_do_update` with `index_where` spelled identically to the partial index predicate; `severity_band`, `alerted_at`, `found_on` deliberately absent from `set_` | ✓ VERIFIED |
| `backend/app/features/finance/profitability_math.py` | DB-free D-01/D-03/bands/fingerprint | ✓ | ✓ 319 L (min 150) | ✓ `candidate_for`, `skip_reason_for`, `latest_quote_per_anchor` all called from the service | ✓ imports `margin_percent_for` / `quoted_revenue` from `margin_math` — no second margin definition; zero DB/FastAPI imports | ✓ VERIFIED |
| `backend/app/core/ai_grounding.py` | reusable D-05 validator | ✓ | ✓ 136 L (min 90) | ✓ `collect_allowed_values` + `validate_grounding` called in `_draft_for` / `_ungrounded_literals` | ✓ payload-shape agnostic: zero `app.features` imports, so Phase 37 reuses it unchanged | ✓ VERIFIED |
| `backend/app/features/finance/prompts/profitability_system.py` | D-09 prompt contract + retry template | ✓ | ✓ 7 numbered sections | ✓ both symbols imported by the service | ✓ length bounds interpolated from `NARRATIVE_MAX_CHARS` etc.; `test_prompt_and_database_state_the_same_length_bounds` pins prompt == DB | ✓ VERIFIED |
| `backend/app/features/finance/profitability_service.py` | scan + publish + alert lifecycle | ✓ | ✓ 845 L (min 150) | ✓ scheduler + router entry points | ✓ `GROUNDING_RETRY_LIMIT`, `AI_FINDING_PREFIX`, `MAX_FINDINGS_PER_COMPANY_PER_NIGHT` all present and load-bearing | ✓ VERIFIED |
| `backend/app/features/finance/portfolio_service.py` | `all_project_figures`, `unsliced_trend_buckets`, `margin_context` | ✓ | ✓ | ✓ all three called from `profitability_service` | ✓ `all_project_figures` is one batched read returning `(figures, inputs)`; `company_financials` now reuses it, so there is one definition of spend | ✓ VERIFIED |
| `backend/app/core/scheduler.py` | job + registration | ✓ | ✓ | ✓ `_register_jobs` ← `lifespan` | ✓ `AI_PROFITABILITY_HOUR_UTC=6`, `MINUTE=30`, offset from the 06:00 checklist job with a named rationale | ✓ VERIFIED |
| `backend/app/features/finance/router.py` | `GET /projects/{id}/financials/finding` | ✓ | ✓ | ✓ mounted, documented in the module header | ✓ returns `to_profitability_finding(finding)` or `None`; own route + own key so a findings outage never blanks the dashboard | ✓ VERIFIED |
| `backend/app/features/finance/schemas.py` | `ProfitabilityFindingResponse` + mapper | ✓ | ✓ | ✓ used by the router | ✓ carries no bare money/percent field — every figure the user sees is inside validated prose | ✓ VERIFIED |
| `backend/app/features/notifications/service.py` | `send_profitability_finding_notification` | ✓ | ✓ 36 L | ✓ called from `_send_profitability_push_safe` | ✓ shares `_resolve_messaging` / `_dispatch_to_tokens`; never raises | ✓ VERIFIED |
| `backend/app/features/dashboard/alert_types.py` | `AI_PROFITABILITY_ALERT_TYPE` + `FINANCIAL_ALERT_TYPES` | ✓ | ✓ | ✓ consumed by `dashboard/service.py`, `_build_alert`, `_push_data` | ✓ registered in **all three** literals (constant, `FINANCIAL_ALERT_TYPES`, ORM CheckConstraint) + the migration | ✓ VERIFIED |
| `web/src/features/finance/types.ts` | `ProfitabilityFinding`, `FINDING_SEVERITIES` | ✓ | ✓ | ✓ imported by api/hooks/card | ✓ `FINDING_SEVERITIES` is the validation whitelist, not just a type | ✓ VERIFIED |
| `web/src/features/finance/api.ts` | `fetchProjectProfitabilityFinding` + mapper | ✓ | ✓ | ✓ called by the hook | ✓ `severity` goes through `toKnownValue`, never a cast; `null` → no finding | ✓ VERIFIED |
| `web/src/features/finance/hooks.ts` | `useProjectProfitabilityFinding` | ✓ | ✓ | ✓ third hook in the dashboard | ✓ `enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId`; key under the `cost-entries` prefix so invalidation is free | ✓ VERIFIED |
| `web/src/features/finance/financials-format.ts` | `formatFindingDate` | ✓ | ✓ | ✓ used by `findingDateLine` | ✓ splits `"YYYY-MM-DD"` — **no `new Date()`**, so no timezone day-shift; unparseable input returns unchanged | ✓ VERIFIED |
| `.../[projectId]/_components/profitability-finding-card.tsx` | presentational card, 11 test ids | ✓ | ✓ 223 L (min 120) | ✓ mounted in `project-financials-dashboard.tsx:108` | ✓ receives `finding`/`isLoading`/`isError` from the live hook; `incompleteCostData={breakdown.margin?.incomplete ?? false}` | ✓ VERIFIED |
| `.../[projectId]/_components/project-financials-dashboard.tsx` | mount + loading gate | ✓ | ✓ | ✓ | ✓ early return still reads only `financials.isLoading \|\| trend.isLoading` (line 86) — a findings outage cannot blank the page | ✓ VERIFIED |
| `web/src/features/finance/components/FinanceFlagChip.tsx` | `FINANCE_ALERT_CHIP_CLASS` | ✓ | ✓ | ✓ 2 consumers (card + attention-list) | ✓ the red tier class string is declared in exactly one module | ✓ VERIFIED |
| `backend/tests/test_phase_36_e2e.py` | integration harness + 34 tests | ✓ | ✓ 2711 L | ✓ | ✓ | ✓ VERIFIED |
| `backend/tests/unit/test_profitability_math.py` | eligibility, 3 signals, bands, fingerprint | ✓ | ✓ 556 L | ✓ | ✓ | ✓ VERIFIED |
| `backend/tests/unit/test_ai_grounding.py` | extraction, matching, tolerance | ✓ | ✓ 358 L | ✓ | ✓ | ✓ VERIFIED |
| `web/.../financials/__tests__/profitability-finding.test.tsx` + `web/tests/phase-36-ai-findings.spec.ts` | card state matrix + Playwright | ✓ | ✓ 16.3 KB / 20.6 KB | ✓ | ✓ | ✓ VERIFIED |

**24/24 artifacts VERIFIED.** No MISSING, no STUB, no ORPHANED, no HOLLOW.

---

## Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `dashboard/models.py` | `dashboard_alerts_alert_type_check` | ORM CheckConstraint literal (`models.py:66-68`) | ✓ WIRED |
| `profitability_repository.py` | `ai_profitability_findings` | `pg_insert(...).on_conflict_do_update` with matching `index_where` | ✓ WIRED |
| `web/hooks.ts` | `usePermissions` | `enabled: can(FINANCE_VIEW_PERMISSION) && !!projectId` | ✓ WIRED |
| `attention-list.tsx` | `FINANCE_ALERT_CHIP_CLASS` | import from `FinanceFlagChip` | ✓ WIRED |
| `profitability_math.py` | `margin_math.margin_percent_for` / `quoted_revenue` | import — no second margin definition | ✓ WIRED |
| `profitability_math.py` | `finance.service.contributing_anchor_cost` | caller supplies `anchor_costs` from the shipped helper | ✓ WIRED |
| `ai_utils.py` | `call_claude_json_strict` | strict sibling, raises, **no `fallback` param** | ✓ WIRED |
| `project-financials-dashboard.tsx` | `useProjectProfitabilityFinding` | third hook, mounted below `FinanceSummaryTiles` | ✓ WIRED |
| `project-financials-dashboard.tsx` | page loading gate | early return reads only `financials.isLoading \|\| trend.isLoading` | ✓ WIRED |
| `profitability_service.py` | `PortfolioService.all_project_figures` | one batched company read, no per-project rollup loop | ✓ WIRED |
| `profitability_service.py` | `profitability_math.candidate_for` | detection never restated in the service | ✓ WIRED |
| `profitability_service.py` | `ai_grounding.validate_grounding` | every AI string validated against `collect_allowed_values(payload)` before persistence | ✓ WIRED |
| `profitability_service.py` | `ai_utils.call_claude_json_strict` | the only Claude entry point on this path | ✓ WIRED |
| `profitability_service.py` | `ProfitabilityRepository.claim_alert` | claim **before** `AlertRepository.create` (`_fire_finding:318-320`) | ✓ WIRED |
| `profitability_service.py` | `RbacRepository.user_ids_with_permission` | recipients resolved in the request session from the live matrix | ✓ WIRED |
| `scheduler.py` | `ProfitabilityService.analyze_company` | `_run_for_all_companies(method_name="analyze_company", target_date=today)` | ✓ WIRED |
| `finance/router.py` | `require_permission` | inline `require_permission("finance.view")` in the handler body | ✓ WIRED |
| `api.ts` | `toKnownValue` | `severity` validated against `FINDING_SEVERITIES`, never cast | ✓ WIRED |
| `profitability_service.py` | `notifications.send_profitability_finding_notification` | own session inside `_send_profitability_push_safe` | ✓ WIRED |
| `dashboard/service.py` | `FINANCIAL_ALERT_TYPES` | non-finance callers get the financial types filtered out | ✓ WIRED |
| `analyze_company` | `resolve_absent_fingerprints` | keep-set = `qualifying_fingerprints` (every candidate), resolve **before** claim | ✓ WIRED |
| `profitability_service.py` | `MAX_*_LENGTH` from `profitability_models` | service length contract reads the same constants the DB CHECKs enforce | ✓ WIRED |

**22/22 key links WIRED.**

---

## Behavioral Spot-Checks (verifier-executed)

| Behavior | Command | Result | Status |
|---|---|---|---|
| Phase 36 integration + all unit suites pass | `pytest tests/test_phase_36_e2e.py tests/unit -q` | 272 passed in 183.73s | ✓ PASS |
| Finance web unit suites pass | `npx jest src/features/finance 'src/app/\(dashboard\)/financials'` | 236 passed, 12 suites, 5.6s | ✓ PASS |
| No non-strict Claude call in the profitability path | `grep -n "call_claude_json" profitability_service.py` | only `call_claude_json_strict` (lines 39, 517) | ✓ PASS |
| No fallback argument anywhere on the finding path | `grep -i fallback profitability_service.py` | zero matches | ✓ PASS |
| `call_claude_json_strict` has no fallback parameter | signature read at `ai_utils.py:122-126` | `(system_prompt, messages, max_tokens)` only | ✓ PASS |
| Grounding validator is feature-agnostic (Phase 37 reuse) | `grep "from app.features" ai_grounding.py` | zero matches | ✓ PASS |
| Alert type registered in all three literals + migration | greps across `alert_types.py`, `models.py`, `0036_*.py` | present in all four | ✓ PASS |
| Backend static gates | `ruff check . && ruff format --check .` | All checks passed; 319 files formatted | ✓ PASS |
| Web static gates | `npx tsc --noEmit && npm run lint` | both clean (exit 0, `--max-warnings 0`) | ✓ PASS |
| Browser-level SC2 zero-request keystone | `npx playwright test tests/phase-36-ai-findings.spec.ts` | not re-run (needs dev server); executor-attested 6/6 | ? SKIP — see note |

**SKIP note:** every browser-level assertion has an independent non-Playwright guard, so the skip leaves no truth unproven: the zero-request half is pinned by the jest test `"issues zero finding requests when the user lacks finance.view"`; the 403 half by `test_finding_endpoint_requires_finance_view`; the card state matrix (11 test ids, loading/error/empty/incomplete/warning/critical) by `profitability-finding.test.tsx`; the outage-isolation contract by the shipped drill-down test plus the `financials.isLoading || trend.isLoading` gate read directly from source.

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| **FINAI-01** | 36-01, 36-03, 36-05, 36-07, 36-08, 36-10 | AI analyzes each active project's financial health on a nightly schedule, flagging margin erosion with suggested corrective actions | ✓ SATISFIED | Cron job at 06:30 UTC over all companies; D-01 eligibility ladder; three deterministic D-03 signals; prompt-enforced target+direction+figure corrective action; per-candidate isolation; RLS-isolated storage. SC1 truth above |
| **FINAI-02** | 36-01, 36-02, 36-04, 36-06, 36-09, 36-10 | Owner/PM receives finance-gated alerts for AI profitability findings | ✓ SATISFIED | Claim-first exactly-once `DashboardAlert`; `FINANCIAL_ALERT_TYPES` dashboard filter; `require_permission("finance.view")` endpoint gate; FCM ⊆ live `finance.view` holders; permission-gated web hook + card. SC2 truth above |

**Orphaned requirements:** none. `REQUIREMENTS.md:95-96` maps only FINAI-01 and FINAI-02 to Phase 36, and every plan's `requirements` frontmatter draws from that pair.

---

## Pre-Existing Defect Fixes — Assessed

All three reported fixes are **real and sound**. A fourth (also real) is recorded below.

### 1. Pitfall-3 drift guard that could not catch drift (36-01, `68aaf4e`) ✓ REAL, SOUND

**The diagnosis was correct.** A SQLAlchemy `CheckConstraint` is DDL-only and is never evaluated on flush; `conftest` builds the test schema with `alembic upgrade head`, not `metadata.create_all`. So the plan's as-specified ORM insert proved the **migration's** value list and nothing about `models.py` — the test would have passed with `models.py` left un-updated, which is precisely the drift Pitfall 3 exists to catch.

**The fix is sound and minimal.** `_orm_alert_type_check_sql()` (`tests/test_phase_36_e2e.py:845-859`) reads the constraint expression off `DashboardAlert.__table__.constraints` by name and `test_ai_profitability_alert_type_accepted_by_orm` asserts membership in it. The ORM round-trip was **kept** (it is the migration half), so the test now covers all three literals independently: migration SQL (the insert succeeds), `models.py` (metadata read), `alert_types.py` (`FINANCIAL_ALERT_TYPES` membership). The executor's break-it-once verification is the right validation for a guard test. Verified by inspection: removing `'ai_profitability'` from the `models.py` literal would fail the `assert ... in _orm_alert_type_check_sql()` line while leaving the insert green.

### 2. Unvalidated `severity` cast that crashed the drill-down (36-06) ✓ REAL, SOUND

**Real and worse than a cosmetic bug.** `mapProfitabilityFinding` cast `severity` straight off the wire; `SEVERITY_CHIP[severity]` then returned `undefined` and `chip.className` threw `Cannot read properties of undefined`. Because the throw is inside render, the Next.js error boundary replaced the **entire** `/financials/[projectId]` page — the money dashboard, not just the card. Two shipped Phase 35 tests were red on it before the plan began.

**The fix is sound and idiomatic.** `api.ts:612` now routes it through the codebase's own `toKnownValue(raw.severity, FINDING_SEVERITIES, "finding severity")` — the same helper already guarding `tier` (`:508`) and `window` (`:554`), so no new convention was invented. Failing at the API boundary is the right level: an invalid payload becomes the query's error state, which the card renders as its own scoped `FindingError` (`py-8 text-center`, no nested panel chrome) rather than taking the page down. `FINDING_SEVERITIES` is exported from `types.ts:246` as a `readonly FindingSeverity[]`, so the whitelist and the union type cannot drift.

### 3. Project fixture whose `"active"` status was silently ignored (36-07, `88685e6`) ✓ REAL, SOUND

**Real, and it would have made the whole D-01 test group vacuous.** `ProjectCreate` declares no `status` field, so `POST /projects {"status": "active"}` dropped it silently and every "active" fixture was actually `draft` — a status D-01 skips. Every eligibility, detection and candidate test would have asserted `candidates == []` and passed for the wrong reason.

**The fix is sound.** `_create_project` no longer sends the ignored field and its docstring now names the trap ("a status in the POST body is silently ignored… every analysis fixture must patch the transition"). `_activate_project` PATCHes to active and **asserts the resulting status** (`assert resp.json()["status"] == _ACTIVE_PROJECT_STATUS`), so a future API change cannot re-introduce a silent no-op. `_seed_analyzable_project(activate=True)` is now the default and `activate=False` is what makes `test_skips_non_active_project` genuinely test the draft side — the two tests exercise opposite sides of the same gate, which is the shape that proves the gate exists.

### 4. `caplog` cannot observe this app's logs (36-07, `88685e6`) ✓ REAL, SOUND — not in the brief, worth recording

The plan's `caplog`-based skip assertions capture zero records under this app's structlog→stdlib bridge; the tests would have passed no matter what the service logged. Fixed by asserting through `structlog.testing.capture_logs` **and** rendering the log templates at the call site (`SKIP_LOG_TEMPLATE % (...)`), because the bridge defers `%`-formatting to the handler, so positional args never reach `capture_logs`. The service-side comment at `profitability_service.py:85-88` documents exactly this. Same class of defect as #1 and #3: a test that asserted nothing.

---

## Anti-Patterns / Observations (clean-code assessment)

Assessed against `~/.agents/skills/clean-code` and `CLAUDE.md` § Clean Code Principles. **No blockers.** No TODO/FIXME/HACK/PLACEHOLDER in any Phase 36 file; no `return null` / `=> {}` stubs; no dead code; no hardcoded empty props; no magic numbers (every threshold, band boundary, cap, hour and length bound is a named constant with a docstring explaining *why*); functions are small and single-purpose; ≤3 arguments enforced via `FindingUpsert`, `DetectionInputs`, `PayloadInputs`, `QuoteGapInputs`, `_PublishContext`. Comments explain WHY, not WHAT. This is unusually disciplined code.

Four notes, none blocking:

| # | File | Severity | Observation |
|---|---|---|---|
| 1 | `app/core/ai_grounding.py:121-123` | ℹ️ Info | `_matches_as_percent` compares a cited percent against **every** allowed value, without distinguishing percent-typed from money-typed payload entries. A payload cost of `Decimal("50")` therefore makes `"50%"` citable. This is a narrow false-**accept**, not a fabrication channel: the number itself is still one the payload contains, so no figure is invented. Tightening it would mean typing the payload's values, which is a larger change than SC3 requires. Worth a note for the Phase 37 reuse. |
| 2 | `app/core/ai_grounding.py:126-136` | ℹ️ Info | The deliberate whole-dollar loosening means a payload value of `Decimal("0.30")` rounds to `0` and makes a cited `"$0"` match. The 36-05 truth "a fabricated `$0` is rejected unless a real payload zero exists" therefore holds only when no payload value rounds to zero. The loosening is one-directional and documented, and the alternative (rejecting `"$3,200"` for `Decimal("3200.41")`) would drop grounded findings — the right trade, but the truth is slightly stronger than the code. |
| 3 | `app/features/dashboard/service.py:123-136` | ⚠️ Warning (pre-existing, Phase 30/34-owned) | `ProjectStatusCard.active_alert_count` counts **all** unread alerts with no `has_finance_view` filter, so an `ai_profitability` alert increments a non-finance user's project-card badge. An **existence** signal only — no alert type, no text, no dollar figure crosses the boundary. Pre-existing since Phase 34 registered `budget_warning`/`budget_overrun` as financial types with the same exposure; Phase 36 widens the blast radius without changing the shape. Recommend logging to `deferred-items.md` for whichever phase next touches the alert-count path. |
| 4 | `app/features/dashboard/router.py:102-135` | ⚠️ Warning (pre-existing, Phase 30/34-owned) | `POST /alerts/{id}/read`, `/accept` and `/dismiss` return a full `AlertResponse` (including `impact_text`, which for a finding carries validated dollar figures) to any authenticated tenant user, with no `finance.view` gate. **Not reachable in practice:** the alert id is an unguessable UUID, `GET /alerts` filters financial types out for non-finance callers, and the only other carrier of `alert_id` is the FCM payload, which goes to finance holders only — so a non-finance caller has no path to obtain one. Same pre-existing Phase 34 shape as #3. Recommend the same deferred-items entry; the fix is one `require_permission` when the alert's type is financial. |
| 5 | `app/core/finance_scrub.py:7-9` | ℹ️ Info | The docstring still reads "Phase 34/36 wire this in once cost/margin data flows into AI context." Phase 36 chose the **stronger** posture — no financial data enters the checklist/chat builders at all, proven empirically by the keystone's prompt-and-body assertions — so `scrub_finance_fields` remains correctly unwired and the forward reference is now stale. Documentation-only; the code is right. |

**Design decision worth naming (not a defect):** `MAX_FINDINGS_PER_COMPANY_PER_NIGHT = 10` means a company with more than 10 candidates in one night publishes only the first 10. SC1's "every active project is analyzed" still holds (every eligible project is analyzed and every skip is logged), and the capped candidates stay in the D-06 keep-set so nothing is resolved and they publish on a subsequent night. `test_per_company_findings_cap` and `test_findings_cap_counted_after_validation` pin both halves, and the cap is counted **after** validation so a dropped finding never spends a slot. Correct as designed and worth remembering as an operational property.

---

## Gaps Summary

**None.** All three ROADMAP success criteria are achieved in code, not merely in SUMMARY claims. Every keystone the brief singled out was checked against source and against a break-it test rather than against a passing assertion:

- The silent-fabrication path is **absent by construction** — `call_claude_json` and any fallback argument appear nowhere on the finding path, and `call_claude_json_strict` has no fallback parameter to pass.
- The D-06 keep-set is built from `qualifying_fingerprints` (every candidate tonight), and `test_transient_claude_failure_does_not_resolve_or_realert` is a real three-night guard whose id and alert-count assertions would both fail under the `published`-based bug.
- D-01 gates before any trend replay, so an ineligible project is never even wrapped into a candidate — there is no code path from a skip to the Claude client.
- D-03 signal 3 takes its quote leg from `latest_quote_per_anchor` and uses `anchor_revenues` only for the billed leg and the tautology guard, which is its correct role.
- SC2's keystone is genuinely four-channel and asserts each half against a permitted counterpart, so no half can pass on a wrong URL or an empty fixture.
- The Phase 30 D-06 boundary holds for every surface Phase 36 introduced. Two ungated **pre-existing** Phase 30/34 alert surfaces (#3, #4 above) are recorded for a future owner; neither leaks a dollar figure reachably.

The three reported pre-existing defect fixes are all real, correctly diagnosed and minimally repaired, and all three were the same class of bug — **a test that asserted nothing**. Catching and fixing three of those, plus a fourth (`caplog`), is materially stronger execution than the plans specified.

Verifier re-ran everything runnable: 272 backend tests, 236 web unit tests, and all four static gates — all green. Playwright was not re-run (needs a dev server) but every one of its assertions has an independent jest or pytest guard.

---

_Verified: 2026-07-29T23:55:45Z_
_Verifier: Claude (gsd-verifier)_
