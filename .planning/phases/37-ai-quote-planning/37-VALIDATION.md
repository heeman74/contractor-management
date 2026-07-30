---
phase: 37
slug: ai-quote-planning
status: planned
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
| **Web quote run** | `cd web && npx jest "src/app/\(dashboard\)/quotes"` — parens **must** be escaped (unescaped matches zero files) |
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

| Req | Behavior | Type | Automated command | File exists? |
|---|---|---|---|---|
| FINAI-03 | Suggest endpoint pre-fills line items grounded in same-trade invoiced history | integration | `pytest tests/test_phase_37_e2e.py -k suggest_prefills -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 1** — quote with an unreviewed AI line cannot be sent: `POST /send` → 4xx, status stays `draft` | integration | `pytest tests/test_phase_37_e2e.py -k send_blocked_by_unreviewed -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 2** — a suggested `unit_price`/`quantity` absent from the payload's allowed set is blocked | integration | `pytest tests/test_phase_37_e2e.py -k ungrounded_line_blocked -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 2b** — an ungrounded `$`/`%` figure in the basis string is blocked | integration | `pytest tests/test_phase_37_e2e.py -k ungrounded_basis_blocked -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 3** — a trade with no invoiced history never reaches the Claude client (`assert_not_awaited`) and returns a named refusal | integration | `pytest tests/test_phase_37_e2e.py -k cold_start_never_calls_claude -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 4** — regenerate leaves accepted and edited lines byte-identical (incl. `id`) and replaces only untouched AI lines | integration | `pytest tests/test_phase_37_e2e.py -k regenerate_preserves -x` | ❌ Wave 0 |
| FINAI-03 | Line-item identity survives a PATCH round trip (Trap 1 fix) | integration | `pytest tests/test_phase_37_e2e.py -k line_item_ids_stable -x` | ❌ Wave 0 |
| FINAI-03 | `field` survives a PATCH round trip (Trap 2 fix) | unit (web) | `npx jest "src/app/\(dashboard\)/quotes"` | ❌ Wave 0 |
| FINAI-03 | D-10 gate: quote-manage without `finance.view` → 403; `finance.view` without quote-manage → 403 | integration | `pytest tests/test_phase_37_e2e.py -k suggest_requires_both_permissions -x` | ❌ Wave 0 |
| FINAI-03 | Suggest refused on non-draft quotes | integration | `pytest tests/test_phase_37_e2e.py -k suggest_draft_only -x` | ❌ Wave 0 |
| FINAI-03 | Comparable query is constant in comparable count (statement counter, 35-02 pattern) | integration | `pytest tests/test_phase_37_e2e.py -k comparable_query_count_constant -x` | ❌ Wave 0 |
| FINAI-03 | Comparable actual cost equals `contributing_anchor_cost` (equivalence guard — no third cost definition) | integration | `pytest tests/test_phase_37_e2e.py -k comparable_cost_equivalence -x` | ❌ Wave 0 |
| FINAI-03 | An invoiced anchor with zero cost entries is excluded (PITFALLS #9) | integration | `pytest tests/test_phase_37_e2e.py -k zero_cost_anchor_excluded -x` | ❌ Wave 0 |
| FINAI-04 | Confidence band on the **count** axis, spread held constant | unit | `pytest tests/unit/test_quote_history_math.py -k band_by_count -x` | ❌ Wave 0 |
| FINAI-04 | Confidence band on the **spread** axis, count held constant (20 comparables at 3× ≠ high) | unit | `pytest tests/unit/test_quote_history_math.py -k band_by_spread -x` | ❌ Wave 0 |
| FINAI-04 | Band never read from the AI reply — a self-reported band is ignored | integration | `pytest tests/test_phase_37_e2e.py -k band_is_code_computed -x` | ❌ Wave 0 |
| FINAI-04 | Chip + basis render per band; no numeric score anywhere in the DOM | unit (web) | `npx jest "src/app/\(dashboard\)/quotes"` | ❌ Wave 0 |
| FINAI-05 | Variance = pre-tax quoted vs actual cost; sign convention; zero-quote guard | unit | `pytest tests/unit/test_quote_history_math.py -k variance -x` | ❌ Wave 0 |
| FINAI-05 | Variance rows render on `/financials/[projectId]` with the scope-labor caption | unit (web) | `npx jest "src/app/\(dashboard\)/financials"` | ✅ extend `project-financials.test.tsx` |
| FINAI-05 | Variance on quote detail is finance-gated: no `finance.view` → card absent **and zero requests** (Trap 8) | unit (web) + E2E | `npx jest "src/app/\(dashboard\)/quotes"`; `npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` | ❌ Wave 0 |
| FINAI-05 | Variance feeds the payload: the trade's variance percent appears as a named payload field | integration | `pytest tests/test_phase_37_e2e.py -k variance_in_payload -x` | ❌ Wave 0 |
| D-13 | `unit_price` derives from quoted history, not the unburdened cost rate; the cost/variance legs are separately named payload fields cited in the basis | integration | `pytest tests/test_phase_37_e2e.py -k pricing_basis -x` | ❌ Wave 0 |
| D-14 | Project-level quote variance groups by `field` → the per-field jobs approval created | integration | `pytest tests/test_phase_37_e2e.py -k project_quote_variance -x` | ❌ Wave 0 |
| — | Typed grounding: a percent value cannot satisfy a `$` citation and vice versa | unit | `pytest tests/unit/test_ai_grounding.py -k typed -x` | ✅ extend |
| — | Shipped Phase 36 grounding behavior unchanged by the tightening | unit | `pytest tests/unit/test_ai_grounding.py -q` | ✅ exists |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] **Production-code prerequisite, NOT a test — must land first:** the Trap 1 + Trap 2 identity fix (`_replace_line_items` DELETEs/re-INSERTs every line on every PATCH and `QuoteLineItemCreate` carries no `id`; the web form drops `field`). Every keystone except #3 is unwritable until line items have stable identity.
- [ ] `backend/tests/test_phase_37_e2e.py` — all four keystones + permission, identity, cold-start and query-shape tests
- [ ] `backend/tests/unit/test_quote_history_math.py` — confidence bands (both axes independently) and variance math
- [ ] Extend `backend/tests/unit/test_ai_grounding.py` — typed money/percent separation; assert the shipped untyped path is unchanged
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-suggestions.test.tsx` — chip per band, basis line, per-line review affordance, no bulk-approve control, no numeric score
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-variance-gate.test.tsx` — the Trap 8 render + zero-request pair
- [ ] `web/tests/phase-37-quote-ai.spec.ts` — Playwright: suggest → review → send-blocked → review-all → send-succeeds
- [ ] Extend the `jest.mock` module factory in `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` when the variance hook is added
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

**Approval:** pending
