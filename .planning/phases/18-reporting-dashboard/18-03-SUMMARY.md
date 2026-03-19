---
phase: 18-reporting-dashboard
plan: "03"
subsystem: web-frontend/backend-reports
tags: [reporting, heatmap, e2e-tests, recharts, tanstack-query, pytest]
dependency_graph:
  requires: [18-02]
  provides: [RPT-01, RPT-02, RPT-03]
  affects: [web/reports, backend/reports]
tech_stack:
  added: []
  patterns:
    - CSS Grid heatmap with dynamic gridTemplateColumns
    - Parallel TanStack Query for independent chart data
    - SQLAlchemy and_() for LEFT JOIN ON conditions
key_files:
  created:
    - web/src/app/(dashboard)/reports/_components/utilization-heatmap.tsx
  modified:
    - web/src/app/(dashboard)/reports/_components/reports-dashboard.tsx
    - web/tests/phase-18-reports.spec.ts
    - backend/tests/test_phase_18_e2e.py
    - backend/app/features/reports/service.py
decisions:
  - "CSS Grid heatmap with inline gridTemplateColumns style — flexible column count, no fixed-width table approach"
  - "Heatmap has its own separate TanStack Query (not merged with main dashboard query) — allows independent loading state and separate cache key"
  - "Backend tests adapted to use tenant_a_client fixture (not tenant_a_admin_token) — matches available conftest.py fixtures; 403 contractor tests deferred"
metrics:
  duration_minutes: 6
  completed_date: "2026-03-19"
  tasks_completed: 2
  files_modified: 5
---

# Phase 18 Plan 03: Utilization Heatmap and E2E Tests Summary

One-liner: CSS Grid utilization heatmap with green/yellow/red color scale integrated into the 2x2 reports dashboard, backed by 11 passing backend integration tests and full Playwright E2E test coverage for RPT-01, RPT-02, and RPT-03.

## What Was Built

**Task 1: Utilization Heatmap Component + Dashboard Integration**

Created `utilization-heatmap.tsx` as a CSS Grid component:
- `cellColor()` function with thresholds: >=85% red, >=60% yellow, >=30% green, else light green
- Dynamic `gridTemplateColumns: 180px repeat(N, minmax(40px, 1fr))` for flexible week columns
- Each cell has a `title` tooltip: `ContractorName — YYYY-Www: XX%`
- Contractor rows with `Fragment` key, `bg-muted` for weeks with no booking data

Updated `reports-dashboard.tsx`:
- Added second TanStack Query for heatmap with `queryKey: ["reports", "heatmap", startDate, endDate]`
- Replaced placeholder `<div>` with full `ChartCard` for "Contractor Utilization" in bottom-left grid slot
- Inline `Skeleton` loading state for heatmap (independent from main dashboard loading)
- `heatmapCsvRows` builds a CSV with contractor name and per-week utilization percentages

**Task 2: E2E Tests + Backend Integration Tests**

Replaced all `test.skip()` stubs in `web/tests/phase-18-reports.spec.ts` with 7 real Playwright tests across 3 `test.describe` groups:
- RPT-01: four chart sections, revenue renders, jobs renders, quote renders
- RPT-02: 7d preset aria-pressed, YTD preset aria-pressed
- RPT-03: heatmap grid renders with `.rounded-sm` cells or empty state

Replaced all `@pytest.mark.skip` stubs in `backend/tests/test_phase_18_e2e.py` with 11 real integration tests across 4 classes:
- `TestDashboard`: all 4 metric groups, list types, auth required
- `TestDateFilter`: explicit date range, narrow range zero jobs, future range empty
- `TestHeatmap`: structure, date range, auth required, ISO week format
- `TestHeatmapEmptyContractor`: structure and week item fields verified

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed heatmap SQL syntax error from func.and_() misuse**
- **Found during:** Task 2 backend test run
- **Issue:** `service.py` line 363 used `func.and_(*booking_date_conditions)` in the LEFT JOIN ON clause. PostgreSQL received `and(bookings.deleted_at IS NULL)` as a SQL function call, causing `PostgresSyntaxError: syntax error at or near "and"`
- **Fix:** Imported `and_` from `sqlalchemy` and replaced `func.and_(*booking_date_conditions)` with `and_(Booking.contractor_id == User.id, *booking_date_conditions)` in the JOIN ON clause
- **Files modified:** `backend/app/features/reports/service.py`
- **Commit:** c07a3c4

**2. [Rule 2 - Adaptation] Adapted backend tests to use existing conftest fixtures**
- **Found during:** Task 2 planning — `tenant_a_admin_token` and `tenant_a_contractor_token` fixtures referenced in plan do not exist in conftest.py
- **Fix:** Used `tenant_a_client` (admin JWT pre-set) for auth tests, `async_client` (no auth) for 401 tests. 403 contractor role tests deferred with a comment noting the missing fixture.
- **Files modified:** `backend/tests/test_phase_18_e2e.py`

## Self-Check: PASSED

- FOUND: web/src/app/(dashboard)/reports/_components/utilization-heatmap.tsx
- FOUND: web/tests/phase-18-reports.spec.ts
- FOUND: backend/tests/test_phase_18_e2e.py
- FOUND commit 5fe8e50: feat(18-03): utilization heatmap component
- FOUND commit c07a3c4: feat(18-03): E2E tests and service bug fix
