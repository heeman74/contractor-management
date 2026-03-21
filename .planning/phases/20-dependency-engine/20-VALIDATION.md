---
phase: 20
slug: dependency-engine
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (backend), flutter test (mobile), Playwright (web) |
| **Config file** | `backend/pytest.ini`, `mobile/pubspec.yaml`, `web/playwright.config.ts` |
| **Quick run command** | `cd backend && uv run python -m pytest tests/test_phase_20_e2e.py -x` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ -x && cd ../mobile && flutter test test/e2e/phase_20_*.dart` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | PROJ-04 | integration | `uv run python -m pytest tests/test_dependencies.py` | ❌ W0 | ⬜ pending |
| 20-01-02 | 01 | 1 | PROJ-04 | unit | `uv run python -m pytest tests/test_cycle_detection.py` | ❌ W0 | ⬜ pending |
| 20-02-01 | 02 | 1 | AI-06 | integration | `uv run python -m pytest tests/test_conflict_detection.py` | ❌ W0 | ⬜ pending |
| 20-03-01 | 03 | 2 | PROJ-05 | e2e | `cd web && npx playwright test tests/gantt.spec.ts` | ❌ W0 | ⬜ pending |
| 20-04-01 | 04 | 2 | PROJ-04 | widget | `flutter test test/e2e/phase_20_dependency_engine_e2e_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_dependencies.py` — stubs for PROJ-04 dependency CRUD + cycle detection
- [ ] `backend/tests/test_conflict_detection.py` — stubs for AI-06 zone conflict queries
- [ ] `mobile/test/e2e/phase_20_dependency_engine_e2e_test.dart` — stubs for mobile dependency + Gantt tests
- [ ] `web/tests/gantt.spec.ts` — stubs for Gantt timeline Playwright tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Gantt chart visual fidelity (swim lane colors, arrow rendering) | PROJ-05 | Canvas/SVG rendering can't be pixel-tested in CI | Open project with 3+ trades, verify swim lanes colored correctly, dependency arrows drawn between tasks |
| Mobile Gantt pinch-to-zoom and drag interactions | PROJ-05 | Real touch gestures on device | Open Gantt on Android device, pinch to zoom, drag to scroll, verify smooth interaction |
| Drag-connect dependency creation on web Gantt | PROJ-04 | Mouse drag interaction over canvas | Draw dependency arrow from Task A to Task B on Gantt, verify link created with correct type |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
