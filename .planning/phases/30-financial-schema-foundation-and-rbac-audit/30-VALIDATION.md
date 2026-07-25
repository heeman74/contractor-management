---
phase: 30
slug: financial-schema-foundation-and-rbac-audit
status: draft
nyquist_compliant: false
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
| **Full suite command** | `cd backend && python -m pytest tests/test_phase_30_e2e.py tests/integration -q` + `cd web && npx jest --ci` |
| **Estimated runtime** | quick ~15s · full ~5 min |

---

## Sampling Rate

- **After every task commit:** Run the quick command (phase E2E file)
- **After every plan wave:** Run the full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

*(Task IDs filled by planner — map derived from success criteria)*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | FINSEC-01 | integration | pytest: matrix returns finance.* for owner/PM; grant flow works | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | FINSEC-02 | integration | pytest: PUT /roles/{role}/permissions grants finance.view to a role → access follows | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | FINSEC-03 | unit | pytest: `_ADMIN_KEYS ∩ {finance.*} == ∅` regression test | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | FINSEC-04 | integration | pytest: reports/dashboard/AI responses contain no cost/margin/budget/rate fields for non-finance user; alert filter + scrub helper unit tests | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_30_e2e.py` — stubs for FINSEC-01..04 (uses existing `seed_two_tenants` fixtures; follows `.claude/skills/e2e-feature-tests/SKILL.md`)
- [ ] Existing `backend/tests/conftest.py` — no changes expected (migrations auto-apply to test DB)

*Existing infrastructure covers framework needs — no installs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Finance group renders correctly in matrix UI | FINSEC-01 | Visual check of grouping/labels | Log in as owner → Roles & Permissions → confirm "Finance" group with 3 toggles, on for owner/PM only |

*(All functional behavior has automated verification; this is aesthetic only.)*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
