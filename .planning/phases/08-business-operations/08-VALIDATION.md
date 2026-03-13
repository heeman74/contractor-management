---
phase: 8
slug: business-operations
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.3.4 + pytest-asyncio 0.25.3 (backend), flutter_test + mocktail 1.0.4 (mobile) |
| **Config file** | `backend/pyproject.toml` (asyncio_mode=auto) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/integration/test_phase_8_e2e.py -x` |
| **Full suite command** | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/integration/test_phase_8_e2e.py -x -q`
- **After every plan wave:** Run `cd backend && uv run python -m pytest && cd ../mobile && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | BIZ-01 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_create_quote_with_line_items -x` | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 1 | BIZ-01 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_template_crud -x` | ❌ W0 | ⬜ pending |
| 08-01-03 | 01 | 1 | BIZ-01 | unit | `pytest tests/unit/test_quote_validation.py -x` | ❌ W0 | ⬜ pending |
| 08-02-01 | 02 | 2 | BIZ-02 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_send_quote_triggers_notification -x` | ❌ W0 | ⬜ pending |
| 08-02-02 | 02 | 2 | BIZ-02 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_read_receipt -x` | ❌ W0 | ⬜ pending |
| 08-02-03 | 02 | 2 | BIZ-02 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_approval_job_transition -x` | ❌ W0 | ⬜ pending |
| 08-02-04 | 02 | 2 | BIZ-02 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_decline_and_revise -x` | ❌ W0 | ⬜ pending |
| 08-02-05 | 02 | 2 | BIZ-02 | unit | `pytest tests/unit/test_quote_validation.py::test_expired_quote_blocks_approval -x` | ❌ W0 | ⬜ pending |
| 08-02-06 | 02 | 2 | BIZ-02 | E2E | `flutter test test/e2e/phase_8_business_ops_e2e_test.dart -t quote_flow` | ❌ W0 | ⬜ pending |
| 08-03-01 | 03 | 2 | BIZ-03 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_generate_invoice_from_job -x` | ❌ W0 | ⬜ pending |
| 08-03-02 | 03 | 2 | BIZ-03 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_number_sequential -x` | ❌ W0 | ⬜ pending |
| 08-03-03 | 03 | 2 | BIZ-03 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_prefilled_from_quote -x` | ❌ W0 | ⬜ pending |
| 08-03-04 | 03 | 2 | BIZ-03 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_transitions_job_to_invoiced -x` | ❌ W0 | ⬜ pending |
| 08-03-05 | 03 | 2 | BIZ-03 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_pdf_download -x` | ❌ W0 | ⬜ pending |
| 08-04-01 | 04 | 3 | BIZ-04 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_jobs_by_status -x` | ❌ W0 | ⬜ pending |
| 08-04-02 | 04 | 3 | BIZ-04 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_revenue_by_month -x` | ❌ W0 | ⬜ pending |
| 08-04-03 | 04 | 3 | BIZ-04 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_contractor_utilization -x` | ❌ W0 | ⬜ pending |
| 08-04-04 | 04 | 3 | BIZ-04 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_role_scoping -x` | ❌ W0 | ⬜ pending |
| 08-04-05 | 04 | 3 | BIZ-04 | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_date_range_filter -x` | ❌ W0 | ⬜ pending |
| 08-05-01 | 05 | 3 | ALL | E2E | `flutter test test/e2e/phase_8_business_ops_e2e_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/integration/test_phase_8_e2e.py` — stubs for BIZ-01 through BIZ-04
- [ ] `backend/tests/unit/test_quote_validation.py` — validation edge cases
- [ ] `mobile/test/e2e/phase_8_business_ops_e2e_test.dart` — full Flutter quote-to-invoice flow
- [ ] Add `quotes, quote_line_items, invoices, invoice_line_items, quote_templates` to TRUNCATE in `backend/tests/conftest.py`
- [ ] Backend install: `cd backend && uv add weasyprint`
- [ ] Flutter install: add `fl_chart: ^1.2.0` to `mobile/pubspec.yaml`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PDF visual layout quality | BIZ-03 | CSS rendering fidelity varies; visual inspection needed | Generate sample invoice PDF, verify alignment, fonts, page breaks |
| Chart touch interaction | BIZ-04 | fl_chart tooltip/hover behavior requires real device | Tap chart bars, verify tooltip shows correct values |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
