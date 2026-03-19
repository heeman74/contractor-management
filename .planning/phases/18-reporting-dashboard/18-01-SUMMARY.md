---
phase: 18-reporting-dashboard
plan: "01"
subsystem: backend-reports + web-foundation
tags: [reports, recharts, typescript, heatmap, e2e-stubs]
dependency_graph:
  requires: []
  provides:
    - backend/app/features/reports/schemas.py:UtilizationHeatmapResponse
    - backend/app/features/reports/service.py:get_utilization_heatmap
    - backend/app/features/reports/router.py:GET /reports/utilization-heatmap
    - web/src/types/api.ts:DashboardResponse
    - web/src/types/api.ts:UtilizationHeatmapResponse
    - web/src/components/ui/chart.tsx:ChartContainer
  affects:
    - Phase 18 Plan 02 (chart components depend on TypeScript types and chart.tsx)
    - Phase 18 Plan 03 (E2E test stubs to be filled in)
tech_stack:
  added:
    - recharts@3.8.0
    - react-is@^19.2.4
  patterns:
    - shadcn chart wrapper (ChartContainer, ChartTooltip, ChartLegend)
    - ISO week format via IYYY-"W"IW PostgreSQL to_char expression
    - LEFT JOIN on Booking for zero-booking contractor inclusion
key_files:
  created:
    - web/src/components/ui/chart.tsx
    - web/tests/phase-18-reports.spec.ts
    - backend/tests/test_phase_18_e2e.py
  modified:
    - backend/app/features/reports/schemas.py
    - backend/app/features/reports/service.py
    - backend/app/features/reports/router.py
    - web/src/types/api.ts
    - web/package.json
decisions:
  - "recharts@3.8.0 forced after shadcn CLI resolved to 2.x — plan explicitly requires 3.8.0"
  - "chart.tsx uses import * as RechartsPrimitive wildcard — compatible with recharts 3.x API"
  - "Backend Decimal fields serialize as strings — TypeScript uses string type for all Decimal-backed fields"
  - "E2E test stubs use test.skip() (Playwright) and @pytest.mark.skip (pytest) — satisfies ship-with-feature rule without false failures"
metrics:
  duration: "~15 minutes"
  completed_date: "2026-03-19"
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 5
---

# Phase 18 Plan 01: Backend Heatmap Endpoint, Recharts, and Type Foundation Summary

**One-liner:** Utilization heatmap endpoint (LEFT JOIN ISO week query), recharts 3.8.0 + shadcn chart wrapper, full TypeScript type set for all report responses, and skipped E2E test stubs for Plans 02/03.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Backend utilization-heatmap endpoint | a7b40d0 | schemas.py, service.py, router.py |
| 2 | Recharts, shadcn chart, TypeScript types, E2E stubs | 1e8d5a0 | package.json, chart.tsx, api.ts, test stubs |

## What Was Built

### Task 1: Backend utilization-heatmap endpoint

Added three new Pydantic schemas to `schemas.py`:
- `UtilizationWeekItem` — single week of data per contractor (iso_week, booked/available hours, utilization%)
- `UtilizationHeatmapContractor` — one contractor row with all week items
- `UtilizationHeatmapResponse` — full grid with ordered week headers and contractor rows

Added `get_utilization_heatmap()` to `ReportingService`:
- Uses `IYYY-"W"IW` PostgreSQL format string for ISO week labels
- LEFT JOIN on Booking ensures contractors with zero bookings still appear
- Booking date conditions applied in the JOIN ON clause (not WHERE) to preserve outer join semantics
- Post-processing fills zero-booking weeks for contractors that have some-but-not-all weeks
- Fixed 40h/week available hours, utilization capped at 100%

Added `GET /reports/utilization-heatmap` to `router.py`:
- Admin role check (403 if not admin)
- Placed before `/contractor` route to avoid path shadowing
- Delegates to `ReportingService.get_utilization_heatmap()`

### Task 2: Frontend foundation

- Installed recharts@3.8.0 and react-is@^19.2.4
- Added shadcn chart.tsx via `npx shadcn@latest add chart`
- Added all Phase 18 TypeScript interfaces to `web/src/types/api.ts` (9 new interfaces)
- Created 7 Playwright test stubs in `web/tests/phase-18-reports.spec.ts`
- Created 4 pytest test classes in `backend/tests/test_phase_18_e2e.py` (all skipped)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] shadcn CLI resolved recharts@2.x instead of 3.8.0**
- **Found during:** Task 2
- **Issue:** `npx shadcn@latest add chart` installed recharts@2.15.4 as its peer dependency resolution, overwriting the initially installed 3.8.0
- **Fix:** Re-ran `npm install recharts@3.8.0 --save` after shadcn chart installation to enforce the plan-specified version
- **Files modified:** web/package.json, web/package-lock.json
- **Commit:** 1e8d5a0

## Verification Results

- `npm ls recharts`: recharts@3.8.0 installed
- `ruff check app/features/reports/`: All checks passed
- `grep -c "interface.*Response" web/src/types/api.ts`: 9 (includes DashboardResponse and UtilizationHeatmapResponse)
- `grep "utilization-heatmap" backend/app/features/reports/router.py`: endpoint present

## Self-Check: PASSED

Files created/modified:
- FOUND: backend/app/features/reports/schemas.py (UtilizationHeatmapResponse present)
- FOUND: backend/app/features/reports/service.py (get_utilization_heatmap present)
- FOUND: backend/app/features/reports/router.py (/utilization-heatmap endpoint present)
- FOUND: web/src/types/api.ts (DashboardResponse and UtilizationHeatmapResponse present)
- FOUND: web/src/components/ui/chart.tsx
- FOUND: web/tests/phase-18-reports.spec.ts (7 test stubs)
- FOUND: backend/tests/test_phase_18_e2e.py (4 test class stubs)

Commits:
- FOUND: a7b40d0 (feat(18-01): add utilization-heatmap endpoint)
- FOUND: 1e8d5a0 (feat(18-01): install recharts 3.8.0, shadcn chart, TypeScript types, E2E stubs)
