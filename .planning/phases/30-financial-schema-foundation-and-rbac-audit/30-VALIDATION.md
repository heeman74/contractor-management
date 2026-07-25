---
phase: 30
slug: financial-schema-foundation-and-rbac-audit
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-24
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (backend, real `contractorhub_test` DB via conftest) + jest 29 / Playwright 1.58 (web) |
| **Config file** | `backend/pyproject.toml` ([tool.pytest.ini_options]) / `web/jest.config.ts` |
| **Quick run command** | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_30_e2e.py -q -p no:cacheprovider` |
| **Full suite command** | `cd backend && python -m pytest tests/test_phase_30_e2e.py tests/unit tests/integration -q` + `cd web && npx jest --ci` |
| **Estimated runtime** | quick ~15s · full ~5 min |

---

## Sampling Rate

- **After every task commit:** Run the quick command (phase E2E file) or the task's own automated verify
- **After every plan wave:** Run the full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

*(Task IDs finalized from plans 30-01..30-04 — every task has an `<automated>` verify.)*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-T1 | 30-01 | 1 | FINSEC-01/03 | unit | `pytest tests/unit/test_permissions_finance_keys.py -q` | 30-01 T1 (permissions.py) | ⬜ pending |
| 01-T2 | 30-01 | 1 | FINSEC-03 | unit | `pytest tests/unit/test_permissions_finance_keys.py -q` | 30-01 T2 | ⬜ pending |
| 01-T3 | 30-01 | 1 | FINSEC-01/02/03 | integration | `pytest tests/test_phase_30_e2e.py -q` | 30-01 T3 (test_phase_30_e2e.py) | ⬜ pending |
| 02-T1 | 30-02 | 2 | FINSEC-01 | unit | `pytest tests/unit/test_finance_schemas.py -q` && `python -c "import app.features.finance.models"` | 30-02 T1 (finance/models.py, schemas.py) | ⬜ pending |
| 02-T2 | 30-02 | 2 | FINSEC-01 | migration | `python -m alembic upgrade head && python -m alembic current` (+ `docker compose up migrate` when Docker present) | 30-02 T2 (0032 migration) | ⬜ pending |
| 02-T3 | 30-02 | 2 | FINSEC-01 | unit | `pytest tests/unit/test_finance_schemas.py -q` | 30-02 T3 | ⬜ pending |
| 03-T1 | 30-03 | 2 | FINSEC-04 | unit | `pytest tests/unit/test_finance_scrub.py -q` && `python -c "import app.features.dashboard.service, app.features.dashboard.router"` | 30-03 T1 (finance_scrub.py, dashboard svc/router) | ⬜ pending |
| 03-T2 | 30-03 | 2 | FINSEC-04 | unit | `pytest tests/unit/test_finance_scrub.py -q` | 30-03 T2 | ⬜ pending |
| 04-T1 | 30-04 | 3 | FINSEC-01/02 | integration | `pytest tests/test_phase_30_e2e.py -q -k "backfilled or seeded or rls"` | 30-01 T3 (extends test_phase_30_e2e.py) | ⬜ pending |
| 04-T2 | 30-04 | 3 | FINSEC-04 | integration | `pytest tests/test_phase_30_e2e.py -q` | 30-01 T3 (extends test_phase_30_e2e.py) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No separate Wave 0 scaffold: plan 30-01 Task 3 creates `backend/tests/test_phase_30_e2e.py` (the phase E2E anchor + shared `_token` helper) in Wave 1; plans 30-02/03/04 extend it. Every referenced test file is created by the plan/task that owns it — no `MISSING` verify commands remain.
- Existing `backend/tests/conftest.py` — no changes expected (migrations auto-apply to the `contractorhub_test` DB).

*Existing infrastructure covers framework needs — no installs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Finance group renders correctly in matrix UI | FINSEC-01 | Visual check of grouping/labels | Log in as owner → Roles & Permissions → confirm "Finance" group with 3 toggles, on for owner/PM only |

*(All functional behavior has automated verification; this is aesthetic only.)*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved — 2026-07-24
