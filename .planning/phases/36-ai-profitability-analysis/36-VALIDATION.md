---
phase: 36
slug: ai-profitability-analysis
status: assigned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-29
---

# Phase 36 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 36-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest + pytest-asyncio (`asyncio_mode="auto"`) + httpx AsyncClient vs real `contractorhub_test` DB; conftest forces DATABASE_URL, `alembic upgrade head`, `clean_tables` autouse |
| **Backend quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_36_e2e.py -q` |
| **Backend unit quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/unit/test_profitability_math.py tests/unit/test_ai_grounding.py -q` |
| **Backend full suite** | `cd backend && source .venv/bin/activate && python -m pytest -q` (~25 min; **run serially** — STATE.md parallel-truncate deadlock) |
| **Web unit framework** | Jest 30 + ts-jest + jsdom (`web/jest.config.ts`) |
| **Web unit quick run** | `cd web && npx jest "src/app/(dashboard)/financials"` |
| **Web E2E framework** | Playwright 1.58.2 chromium (`webServer: npm run dev`); specs mock `/api/proxy` |
| **Web E2E quick run** | `cd web && npx playwright test tests/phase-36-ai-findings.spec.ts` |
| **Static gates** | `cd backend && ruff check . && ruff format --check .`; `cd web && npm run lint && npx tsc --noEmit` |
| **Estimated runtime** | ~30s per-task quick runs |

---

## Sampling Rate

- **Per task commit:** `pytest tests/test_phase_36_e2e.py -q` and/or the two unit files and/or `npx jest "src/app/(dashboard)/financials"`, plus the touched layer's linter.
- **Per wave merge:** `pytest tests/test_phase_3{3,4,5,6}_e2e.py tests/unit -q` + `npm test` + both static gates.
- **Phase gate:** full backend suite (serial), `npm test`, `npm run test-e2e`, ruff — all green before `/gsd:verify-work`.
- **Max feedback latency:** ~30 seconds outside sanctioned phase-gate full suites.

---

## Phase Requirements → Test Map

| Req | Behavior | Type | Automated command | Owning plan/task | File exists? |
|---|---|---|---|---|---|
| **SC3 / D-05** ★ | Finding citing a figure absent from the payload is blocked after one retry, never published (zero findings, zero alerts) | integration | `pytest tests/test_phase_36_e2e.py::test_unmatched_figure_blocked_after_one_retry -x` | 36-08 T1 | ⬜ created by that task |
| **D-06** ★ | Same erosion fingerprint alerts exactly once across three nightly runs, re-fires on band worsening | integration | `pytest tests/test_phase_36_e2e.py::test_fingerprint_alerts_exactly_once_across_three_runs -x` | 36-09 T1 | ⬜ created by that task |
| **SC2 / FINAI-02** ★ | Non-finance sees no AI findings anywhere: alerts filtered, findings endpoint 403, FCM ⊆ finance.view holders, no figures in checklist/chat output | integration | `pytest tests/test_phase_36_e2e.py::test_non_finance_sees_no_ai_findings_anywhere -x` | 36-10 T3 | ⬜ created by that task |
| SC3 / D-05 | Grounded finding publishes first-call (no retry consumed) | integration | `pytest tests/test_phase_36_e2e.py::test_grounded_finding_publishes_without_retry -x` | 36-08 T1 | ⬜ created by that task |
| SC3 / D-05 | Retry succeeds: unmatched → grounded → published | integration | `pytest tests/test_phase_36_e2e.py::test_grounding_retry_succeeds_on_second_attempt -x` | 36-08 T1 | ⬜ created by that task |
| SC3 / D-05 | Figure extraction/matching: thousands separators, stripped `.00`, one-decimal percents, whole-dollar rounding, fabricated `$0` rejected | unit | `pytest tests/unit/test_ai_grounding.py -q` | 36-05 T1+T2 | ⬜ created by that task |
| D-01 | Non-active project skipped with reason | integration | `pytest tests/test_phase_36_e2e.py::test_skips_non_active_project -x` | 36-07 T3 | ⬜ created by that task |
| D-01 | No-revenue project skipped | integration | `pytest tests/test_phase_36_e2e.py::test_skips_project_without_revenue_source -x` | 36-07 T3 | ⬜ created by that task |
| D-01 / Pitfall 9 | Revenue-bearing zero-cost project (fabricated ~100% margin) skipped | integration | `pytest tests/test_phase_36_e2e.py::test_skips_incomplete_cost_data_project -x` | 36-07 T3 | ⬜ created by that task |
| D-01 | Unrated-labor project skipped | integration | `pytest tests/test_phase_36_e2e.py::test_skips_unrated_labor_project -x` | 36-07 T3 | ⬜ created by that task |
| D-02 | Non-candidates never reach Claude (call count == candidate count) | integration | `pytest tests/test_phase_36_e2e.py::test_only_candidates_reach_claude -x` | 36-08 T1 | ⬜ created by that task |
| D-02 | AI dismissal persists nothing, alerts nothing | integration | `pytest tests/test_phase_36_e2e.py::test_ai_dismissal_publishes_nothing -x` | 36-08 T1 | ⬜ created by that task |
| D-03 #1 | ≥5pt cumulative decline across last two buckets flags; 4.9pt doesn't; None percents never coerce to 0; window never changes detection | unit | `pytest tests/unit/test_profitability_math.py -q -k decline` | 36-03 T1 | ⬜ created by that task |
| D-03 #2 | Negative margin flags via `margin`, incl. zero-revenue where percent is None | unit | `pytest tests/unit/test_profitability_math.py -q -k negative` | 36-03 T1 | ⬜ created by that task |
| D-03 #3 | Quote-implied gap: latest approved quote per anchor INCLUDING invoiced anchors; shared anchor set only; quoted-only project → no candidate | unit | `pytest tests/unit/test_profitability_math.py -q -k quote_implied` | 36-03 T2 | ⬜ created by that task |
| D-03 #3 | E2E: invoiced-below-approved-quote produces a candidate | integration | `pytest tests/test_phase_36_e2e.py::test_quote_implied_gap_produces_candidate -x` | 36-07 T3 | ⬜ created by that task |
| D-06 | Fingerprint stable across runs; changes on band change | unit | `pytest tests/unit/test_profitability_math.py -q -k fingerprint` | 36-03 T3 | ⬜ created by that task |
| D-06 | Cleared-then-recurring condition re-alerts | integration | `pytest tests/test_phase_36_e2e.py::test_cleared_then_recurring_condition_realerts -x` | 36-09 T1 | ⬜ created by that task |
| **D-06** | A transient Claude failure does NOT resolve a still-qualifying finding and does NOT re-alert on the next successful night (keep-set = qualifying, not published) | integration | `pytest tests/test_phase_36_e2e.py::test_transient_claude_failure_does_not_resolve_or_realert -x` | 36-09 T1 | ⬜ created by that task |
| D-06 | Same-day re-run idempotent (no dup finding, no dup alert) | integration | `pytest tests/test_phase_36_e2e.py::test_same_day_rerun_is_idempotent -x` | 36-09 T1 | ⬜ created by that task |
| D-07 | `ai_profitability` accepted by the DB CHECK through the ORM (migration + models.py literal in sync) | integration | `pytest tests/test_phase_36_e2e.py::test_ai_profitability_alert_type_accepted_by_orm -x` | 36-01 T3 | ⬜ created by that task |
| D-07 | FCM recipients equal live finance.view holders after a matrix change | integration | `pytest tests/test_phase_36_e2e.py::test_push_recipients_follow_live_permission_matrix -x` | 36-09 T2 | ⬜ created by that task |
| D-09 | DB half: over-length `alert_summary`/`narrative` rejected by the CHECK constraint | integration | `pytest tests/test_phase_36_e2e.py::test_alert_summary_db_length_check -x` | 36-01 T3 | ⬜ created by that task |
| D-09 | Service half: over-length draft rejected, nothing persisted, never truncated | integration | `pytest tests/test_phase_36_e2e.py::test_over_length_draft_is_rejected_not_truncated -x` | 36-08 T2 | ⬜ created by that task |
| D-10 | Per-company nightly findings cap honored, counted after validation | integration | `pytest tests/test_phase_36_e2e.py::test_per_company_findings_cap -x` | 36-08 T2 | ⬜ created by that task |
| D-10 / FINAI-01 | Cron job registered with expected id/trigger | integration | `pytest tests/test_phase_36_e2e.py::test_profitability_job_registered -x` | 36-10 T1 | ⬜ created by that task |
| FINAI-01 | Claude failure for one project doesn't abort the company run | integration | `pytest tests/test_phase_36_e2e.py::test_claude_failure_isolated_per_candidate -x` | 36-08 T1 | ⬜ created by that task |
| FINAI-01 | Tenant B cannot read tenant A's findings (RLS) | integration | `pytest tests/test_phase_36_e2e.py::test_findings_rls_isolation -x` | 36-01 T3 | ⬜ created by that task |
| D-08 | Latest-finding endpoint returns newest unresolved; null/empty state | integration | `pytest tests/test_phase_36_e2e.py::test_latest_finding_endpoint -x` | 36-10 T2 | ⬜ created by that task |
| D-08 | Finding card renders narrative + action; empty state; failing query doesn't blank the drill-down | unit (jest) | `npx jest "src/app/(dashboard)/financials"` | 36-04 T3 | ⬜ created by that task |
| D-08 / SC2 | Finance user sees the finding on /financials/[projectId]; non-finance sees deny panel AND zero finding requests | e2e | `npx playwright test tests/phase-36-ai-findings.spec.ts` | 36-06 T1+T2 | ⬜ created by that task |

★ = the three keystone tests named in CONTEXT § Specific Ideas.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Each missing test file is CREATED by the plan/task that owns its first row — there is
no separate scaffolding wave, because every owning task is TDD-shaped and its
`<verify>` runs the file it writes.

- [ ] `backend/tests/test_phase_36_e2e.py` — created by **36-01 T3** (harness + helpers + schema tests); extended by 36-07 T3, 36-08 T1/T2, 36-09 T1/T2, 36-10 T1/T2/T3
- [ ] `backend/tests/unit/test_profitability_math.py` — created by **36-03 T1**; extended by 36-03 T2/T3
- [ ] `backend/tests/unit/test_ai_grounding.py` — created by **36-05 T1**; extended by 36-05 T2
- [ ] `web/src/features/finance/__tests__/financials-hooks.test.tsx` — extended by **36-02 T3** (file already ships)
- [ ] `web/src/app/(dashboard)/financials/__tests__/profitability-finding.test.tsx` — created by **36-04 T3**
- [ ] `web/tests/phase-36-ai-findings.spec.ts` — created by **36-06 T1**; extended by 36-06 T2
- Framework install: none — pytest, Jest, Playwright all present.

**Serial-DB constraint:** only ONE backend plan runs per wave (waves 1-7 place at most
one backend plan each) — `conftest.py` TRUNCATEs all tables per test and two pytest
processes against `contractorhub_test` deadlock inside `seed_two_tenants`
(STATE.md Phase 35 blocker). Web plans run in parallel with backend plans freely.

**Claude API mocking (verified precedent):** patch `app.core.ai_utils.get_anthropic_client`, `mock_client.return_value.messages.create = AsyncMock(...)` — `return_value=` single-turn, `side_effect=[first, second]` for validate-and-retry. Copy `_make_mock_anthropic_response` from `tests/test_phase_26_e2e.py:144-153` (self-contained-file convention). Patch `NotificationService.send_*` with AsyncMock; assert recipient sets via `RbacRepository`.

---

## Manual-Only Verifications

None — the Claude API is mocked at the client layer; visual polish of the finding card falls to the UI-SPEC checker/UAT pass.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (phase-gate full suites sanctioned)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** per-task map assigned 2026-07-29 during phase planning
