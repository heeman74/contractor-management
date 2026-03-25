---
phase: 24
slug: gc-inspection-workflow
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-25
---

# Phase 24 -- Validation Strategy

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

Each task uses the self-contained `<verify>` command from its plan. Test files are created in Plan 04 (Wave 3) and are NOT prerequisites for Wave 1-2 tasks.

| Task ID | Plan | Wave | Requirement | Automated Verify Command | Status |
|---------|------|------|-------------|--------------------------|--------|
| 24-01-01 | 01 | 1 | INSP-01 | `cd backend && uv run alembic upgrade head && uv run python -c "from app.features.inspection.models import TaskInspection, SiteWalkFlag, PunchListItem; print('OK')"` | pending |
| 24-01-02 | 01 | 1 | INSP-01..04 | `cd backend && uv run python -c "from app.features.inspection.router import inspection_router; print(f'Routes: {len(inspection_router.routes)}')" && uv run ruff check app/features/inspection/` | pending |
| 24-02-01 | 02 | 1 | INSP-01..03 | `cd mobile && dart run build_runner build --delete-conflicting-outputs && grep "schemaVersion => 12" lib/core/database/app_database.dart` | pending |
| 24-02-02 | 02 | 1 | INSP-01..03 | `cd mobile && dart analyze lib/features/projects/data/task_inspection_dao.dart lib/features/projects/data/site_walk_flag_dao.dart lib/features/projects/data/punch_list_item_dao.dart lib/features/projects/presentation/providers/project_providers.dart` | pending |
| 24-03-01 | 03 | 2 | INSP-01 | `cd mobile && dart analyze lib/features/projects/presentation/screens/task_detail_screen.dart lib/features/projects/presentation/widgets/inspection_checklist.dart lib/features/projects/presentation/widgets/rejection_bottom_sheet.dart` | pending |
| 24-03-02a | 03 | 2 | INSP-02 | `cd mobile && dart analyze lib/features/projects/presentation/screens/project_detail_screen.dart lib/features/projects/presentation/widgets/site_walk_flag_section.dart lib/features/projects/presentation/widgets/flag_capture_sheet.dart` | pending |
| 24-03-02b | 03 | 2 | INSP-03 | `cd mobile && dart analyze lib/features/projects/presentation/screens/trade_scope_detail_screen.dart lib/features/projects/presentation/widgets/punch_list_card.dart` | pending |
| 24-04-01 | 04 | 3 | INSP-01..04 | `cd backend && uv run python -m pytest tests/test_phase_24_inspection.py tests/test_phase_24_site_walk.py tests/test_phase_24_punch_list.py tests/test_phase_24_fcm_rejection.py -x -v --timeout=60` | pending |
| 24-04-02 | 04 | 3 | INSP-01..03 | `cd mobile && flutter test test/e2e/phase_24_inspection_e2e_test.dart test/e2e/phase_24_site_walk_e2e_test.dart test/e2e/phase_24_punch_list_e2e_test.dart --no-pub` | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

No Wave 0 test stubs needed. Plans 01-03 use self-contained verification (alembic upgrade, dart analyze, ruff check, build_runner). Plan 04 creates all test files as its deliverable.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo annotation UX for rejection evidence | INSP-01 | Visual annotation quality check | Open task detail -> Reject -> take photo -> annotate -> verify overlay renders correctly on device |
| Camera-first flag creation UX | INSP-02 | Camera hardware interaction | Tap Flag Issue -> verify camera opens -> take photo -> verify form fallback works |
| Punch badge visual styling | INSP-03 | Visual appearance check | Open contractor task view -> verify punch items show distinct badge |
| FCM push notification timing | INSP-04 | Real device push delivery | Reject a task -> verify contractor receives push within 30 seconds on physical device |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] No Wave 0 gaps -- Wave 1-2 use self-contained verify, Wave 3 creates test files
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
