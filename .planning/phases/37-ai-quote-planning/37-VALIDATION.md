---
phase: 37
slug: ai-quote-planning
status: assigned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-30
---

# Phase 37 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 37-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest 8.3.4 + pytest-asyncio (`asyncio_mode="auto"`, `testpaths=["tests"]`) |
| **Backend quick run** | `cd backend && .venv/bin/pytest tests/unit -x -q` |
| **Backend phase run** | `cd backend && .venv/bin/pytest tests/test_phase_37_e2e.py -x -q` |
| **Backend full suite** | `cd backend && .venv/bin/pytest` — **one process only** (conftest TRUNCATEs per test; parallel runs deadlock in `seed_two_tenants`) |
| **Web unit framework** | Jest + Testing Library |
| **Web quote run** | `cd web && npx jest "src/app/\(dashboard\)/quotes"` — parens **must** be escaped (unescaped matches zero files). Jest 30 removed `--testPathPattern`; use the escaped positional pattern, or `--testPathPatterns` if a flag is unavoidable. |
| **Web full unit** | `cd web && npm test` |
| **Web E2E** | `cd web && npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` |
| **Static gates** | `ruff check && ruff format --check` (backend); `npm run lint && npx tsc --noEmit` (web) |
| **Estimated runtime** | ~30s per-task quick runs |

**Claude mocking (verified precedent):** patch `app.core.ai_utils.get_anthropic_client`; copy `_make_mock_anthropic_response` from `tests/test_phase_26_e2e.py:144-153` (self-contained-file convention). `assert_not_awaited` is the cold-start guard.

---

## Sampling Rate

- **Per task commit:** `cd backend && .venv/bin/pytest tests/unit -x -q` (+ `ruff check`), or `cd web && npx jest <touched path>` (+ `npm run lint && npx tsc --noEmit`).
- **Per wave merge:** `cd backend && .venv/bin/pytest tests/test_phase_37_e2e.py tests/unit -q` and `cd web && npm test`.
- **Phase gate:** full backend suite (single process), `npm test`, Playwright `--workers=2 --retries=1` — the two pre-existing Phase 21 URL-drift failures (`ai-intake`, `ai-interview`) are the documented allowance.
- **Max feedback latency:** ~30 seconds outside the sanctioned phase-gate suites.

---

## Phase Requirements → Test Map

> Plan · Task assigned at planning time (2026-07-30). Status stays ⬜ until the
> owning task runs.

| Req | Behavior | Type | Plan · Task | Automated command | Status |
|---|---|---|---|---|---|
| FINAI-03 | Suggest endpoint pre-fills line items grounded in same-trade invoiced history | integration | **37-09 T3** | `pytest tests/test_phase_37_e2e.py -k suggest_prefills -x` | ⬜ |
| FINAI-03 | **KEYSTONE 1** — quote with an unreviewed AI line cannot be sent: `POST /send` → 4xx, status stays `draft` | integration | **37-01 T3** | `pytest tests/test_phase_37_e2e.py -k send_blocked_by_unreviewed -x` | ⬜ |
| FINAI-03 | **KEYSTONE 2** — a suggested `unit_price`/`quantity` absent from the payload's allowed set is blocked | integration | **37-11 T1** | `pytest tests/test_phase_37_e2e.py -k ungrounded_line_blocked -x` | ⬜ |
| FINAI-03 | **KEYSTONE 2b** — an ungrounded `$`/`%` figure in the basis string is blocked | integration | **37-11 T1** | `pytest tests/test_phase_37_e2e.py -k ungrounded_basis_blocked -x` | ⬜ |
| FINAI-03 | **KEYSTONE 3** — a trade with no invoiced history never reaches the Claude client (`assert_not_awaited`) and returns a named refusal | integration | **37-09 T2** | `pytest tests/test_phase_37_e2e.py -k cold_start_never_calls_claude -x` | ⬜ |
| FINAI-03 | **KEYSTONE 4** — regenerate leaves accepted and edited lines byte-identical (incl. `id`) and replaces only untouched AI lines | integration | **37-11 T2** | `pytest tests/test_phase_37_e2e.py -k regenerate_preserves -x` | ⬜ |
| FINAI-03 | Line-item identity survives a PATCH round trip (Trap 1 fix) | integration | **37-01 T2** | `pytest tests/test_phase_37_e2e.py -k line_item_ids_stable -x` | ⬜ |
| FINAI-03 | `field` survives a PATCH round trip (Trap 2 fix) — backend half | integration | **37-01 T2** | `pytest tests/test_phase_37_e2e.py -k line_item_field_survives_patch -x` | ⬜ |
| FINAI-03 | `field` survives the editor form round trip (Trap 2 fix) — web half | unit (web) | **37-03 T2** | `npx jest "src/app/\(dashboard\)/quotes/__tests__/quote-contract"` | ⬜ |
| FINAI-03 | D-10 gate: quote-manage without `finance.view` → 403; `finance.view` without quote-manage → 403 | integration | **37-09 T3** | `pytest tests/test_phase_37_e2e.py -k suggest_requires_both_permissions -x` | ⬜ |
| FINAI-03 | Suggest refused on non-draft quotes | integration | **37-09 T2** | `pytest tests/test_phase_37_e2e.py -k suggest_draft_only -x` | ⬜ |
| FINAI-03 | Comparable query is constant in comparable count (statement counter, 35-02 pattern) | integration | **37-07 T1** | `pytest tests/test_phase_37_e2e.py -k comparable_query_count_constant -x` | ⬜ |
| FINAI-03 | Comparable actual cost equals `contributing_anchor_cost` (equivalence guard — no third cost definition) | integration | **37-07 T1** | `pytest tests/test_phase_37_e2e.py -k comparable_cost_equivalence -x` | ⬜ |
| FINAI-03 | An invoiced anchor with zero cost entries is excluded (PITFALLS #9) | integration | **37-07 T1** | `pytest tests/test_phase_37_e2e.py -k zero_cost_anchor_excluded -x` | ⬜ |
| FINAI-03 | Suggest → review → send-blocked → review-all → send-succeeds, in a browser | E2E | **37-12 T1** | `npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` | ⬜ |
| FINAI-04 | Confidence band on the **count** axis, spread held constant | unit | **37-02 T3** | `pytest tests/unit/test_quote_history_math.py -k band_by_count -x` | ⬜ |
| FINAI-04 | Confidence band on the **spread** axis, count held constant (20 comparables at 3× ≠ high) | unit | **37-02 T3** | `pytest tests/unit/test_quote_history_math.py -k band_by_spread -x` | ⬜ |
| FINAI-04 | Band never read from the AI reply — a self-reported band is ignored | integration | **37-11 T2** | `pytest tests/test_phase_37_e2e.py -k band_is_code_computed -x` | ⬜ |
| FINAI-04 | Band → label/class map has exactly one entry per band | unit (web) | **37-03 T1** | `npx jest "src/app/\(dashboard\)/quotes/__tests__/quote-contract"` | ⬜ |
| FINAI-04 | Chip + basis render per band; no numeric score anywhere in the DOM; no bulk-approve control | unit (web) | **37-05 T2, 37-05 T3** | `npx jest "src/app/\(dashboard\)/quotes/__tests__/quote-suggestions"` | ⬜ |
| FINAI-05 | Variance = pre-tax quoted vs actual cost; sign convention; zero-quote guard | unit | **37-02 T2** | `pytest tests/unit/test_quote_history_math.py -k variance -x` | ⬜ |
| FINAI-05 | Quote variance and project quote variance endpoints are `finance.view`-gated | integration | **37-04 T3** | `pytest tests/test_phase_37_e2e.py -k requires_finance_view -x` | ⬜ |
| FINAI-05 | Variance rows render on `/financials/[projectId]` with the scope-labor caption | unit (web) | **37-10 T2, 37-10 T3** | `npx jest "src/app/\(dashboard\)/financials"` | ⬜ |
| FINAI-05 | Variance on quote detail is finance-gated: no `finance.view` → card absent **and zero requests** (Trap 8) | unit (web) + E2E | **37-08 T3, 37-12 T2** | `npx jest "src/app/\(dashboard\)/quotes/__tests__/quote-variance-gate"`; `npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` | ⬜ |
| FINAI-05 | `FinanceGate`'s omitted-`fallback` behavior is byte-unchanged | unit (web) | **37-08 T1** | `npx jest "src/features/finance" "src/app/\(dashboard\)/financials"` | ⬜ |
| FINAI-05 | Variance feeds the payload: the trade's variance percent appears as a named payload field | integration | **37-11 T3** | `pytest tests/test_phase_37_e2e.py -k variance_in_payload -x` | ⬜ |
| D-13 | `unit_price` derives from quoted history, not the unburdened cost rate; the cost/variance legs are separately named payload fields cited in the basis | integration | **37-11 T3** | `pytest tests/test_phase_37_e2e.py -k pricing_basis -x` | ⬜ |
| D-14 | Project-level quote variance groups by `field` → the per-field jobs approval created | integration | **37-04 T2** | `pytest tests/test_phase_37_e2e.py -k project_quote_variance -x` | ⬜ |
| — | Typed grounding: a percent value cannot satisfy a `$` citation and vice versa | unit | **37-02 T1** | `pytest tests/unit/test_ai_grounding.py -k typed -x` | ⬜ |
| — | Shipped Phase 36 grounding behavior unchanged by the tightening | unit | **37-02 T1** | `pytest tests/unit/test_ai_grounding.py -q` | ⬜ |
| — | Closed set: neither a count nor a quantity is citable as money or as a percent | unit | **37-07 T3** | `pytest tests/unit/test_quote_suggestion_payload.py -q` | ⬜ |
| — | Prompt bounds equal the DB CHECK and schema bounds | unit | **37-09 T1** | `pytest tests/unit/test_quote_planning_prompt.py -q` | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] **Production-code prerequisite, NOT a test — must land first (plan 37-01, wave 1):** the Trap 1 + Trap 2 identity fix (`_replace_line_items` DELETEs/re-INSERTs every line on every PATCH and `QuoteLineItemCreate` carries no `id`; the web form drops `field`). Every keystone except #3 is unwritable until line items have stable identity.
- [ ] `backend/tests/test_phase_37_e2e.py` (created 37-01 T1, extended by 37-01/37-04/37-07/37-09/37-11) — all four keystones + permission, identity, cold-start and query-shape tests
- [ ] `backend/tests/unit/test_quote_history_math.py` (37-02 T2/T3, extended 37-07 T2) — confidence bands (both axes independently) and variance math
- [ ] Extend `backend/tests/unit/test_ai_grounding.py` (37-02 T1) — typed money/percent separation; assert the shipped untyped path is unchanged
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-suggestions.test.tsx` (37-05) — chip per band, basis line, per-line review affordance, no bulk-approve control, no numeric score
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-variance-gate.test.tsx` (37-08) — the Trap 8 render + zero-request pair
- [ ] `web/tests/phase-37-quote-ai.spec.ts` (37-12) — Playwright: suggest → review → send-blocked → review-all → send-succeeds
- [ ] Extend the `jest.mock` module factory in `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` when the variance hook is added (37-10 T3)
- Also: `backend/tests/unit/test_quote_suggestion_payload.py` (37-07 T3), `backend/tests/unit/test_quote_planning_prompt.py` (37-09 T1), `web/src/app/(dashboard)/quotes/__tests__/quote-contract.test.tsx` (37-03), `web/src/app/(dashboard)/quotes/__tests__/quote-send-gate.test.tsx` (37-06).
- Framework install: none — pytest, Jest, Playwright all present.

---

## Manual-Only Verifications

| Behavior | Why manual |
|---|---|
| Visual fidelity of the confidence chip against the 35/36 palette | Aesthetic judgment on a real renderer |
| One live Claude call against a real trade history to confirm prompt adherence end to end | Every automated test patches the client |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (phase-gate suites sanctioned)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** per-task map assigned 2026-07-30 during `/gsd:plan-phase 37` (12 plans, 7 waves).
