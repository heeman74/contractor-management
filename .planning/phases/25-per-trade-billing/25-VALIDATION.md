---
phase: 25
slug: per-trade-billing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (backend) / flutter_test (mobile) |
| **Config file** | `backend/pyproject.toml` / `mobile/pubspec.yaml` |
| **Quick run command** | `cd backend && uv run python -m pytest tests/ -x -q --timeout=30` / `cd mobile && flutter test --no-pub` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ -v` / `cd mobile && flutter test` |
| **Estimated runtime** | ~60 seconds (backend) / ~90 seconds (mobile) |

---

## Sampling Rate

- **After every task commit:** Run quick test command for changed area
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

Populated during planning — each task uses self-contained `<verify>` commands from its plan.

| Task ID | Plan | Wave | Requirement | Automated Verify Command | Status |
|---------|------|------|-------------|--------------------------|--------|
| TBD | TBD | TBD | BILL-01..05 | TBD | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

TBD — populated after planning determines task structure.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Quote line item editor UX | BILL-01 | Visual interaction quality | Create trade-scope quote → add/edit/remove line items → verify smooth UX |
| Project-level aggregation rendering | BILL-02/04 | Visual layout check | View project with multiple trade quotes/invoices → verify totals render correctly |
| Progress invoice milestone selection UX | BILL-05 | Interaction flow | Select milestone → verify amount auto-calculates → verify "invoiced" badge appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify commands
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
