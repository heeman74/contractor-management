---
phase: 22
slug: task-execution-and-photo-annotation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (backend), Flutter test (mobile), Playwright (web) |
| **Config file** | `backend/pyproject.toml`, `mobile/pubspec.yaml`, `web/playwright.config.ts` |
| **Quick run command** | `cd backend && uv run python -m pytest tests/test_phase_22_e2e.py -x -q` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ -x -q && cd ../mobile && flutter test test/e2e/phase_22_*.dart` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| Populated during planning | | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_22_e2e.py` — stubs for TASK-01 through TASK-07
- [ ] `mobile/test/e2e/phase_22_task_execution_e2e_test.dart` — Flutter E2E stubs
- [ ] `mobile/test/e2e/phase_22_photo_annotation_e2e_test.dart` — Annotation E2E stubs

*Existing test infrastructure (pytest, Flutter test, Playwright) covers all framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo annotation drawing accuracy | TASK-05 | CustomPainter rendering requires visual inspection | Draw arrow + circle + text on test photo, verify visual output |
| Measurement ruler dimension display | TASK-05 | Ruler text alignment requires visual check | Draw measurement line, verify dimension text renders at midpoint |
| Pinch-to-zoom during annotation | TASK-04 | Gesture interaction cannot be fully simulated | Open photo, pinch to zoom, verify annotations scale correctly |
| Push notification batch digest | TASK-02 | FCM delivery requires real device | Complete 3+ tasks, verify GC receives batch digest notification |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
