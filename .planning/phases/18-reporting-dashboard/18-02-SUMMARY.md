---
phase: 18-reporting-dashboard
plan: 02
subsystem: ui
tags: [recharts, tanstack-query, date-fns, react-day-picker, next.js, typescript]

# Dependency graph
requires:
  - phase: 18-01
    provides: DashboardResponse TypeScript types, backend /api/v1/reports/dashboard endpoint, recharts 3.x installation

provides:
  - /reports page with dynamic import (ssr:false)
  - ReportsDashboard with TanStack Query date-parameterized fetching
  - DateRangeFilter with 4 presets (7d/30d/90d/YTD) + custom calendar popover
  - ChartCard reusable wrapper with KPI, icon, CSV blob download
  - RevenueChart (Recharts AreaChart — stacked paid/unpaid)
  - JobsByStatusChart (Recharts BarChart — per-status color cells)
  - QuoteConversionChart (Recharts PieChart — approved/declined/pending)
  - Loading skeleton (ReportsSkeleton), error toast, empty state per chart

affects: [18-03-utilization-heatmap]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - dynamic import with ssr:false + skeleton loading fallback (reports page)
    - TanStack Query queryKey includes date params for automatic refetch on filter change
    - ChartCard reusable wrapper pattern — title/KPI/icon/CSV decoupled from chart content
    - Recharts Tooltip formatter uses eslint-disable any cast to handle recharts 3.x strict ValueType|undefined
    - Bar onClick cast to any then typed internally — recharts 3.x BarMouseEvent does not expose domain record fields

key-files:
  created:
    - web/src/app/(dashboard)/reports/page.tsx
    - web/src/app/(dashboard)/reports/_components/reports-dashboard.tsx
    - web/src/app/(dashboard)/reports/_components/date-range-filter.tsx
    - web/src/app/(dashboard)/reports/_components/chart-card.tsx
    - web/src/app/(dashboard)/reports/_components/reports-skeleton.tsx
    - web/src/app/(dashboard)/reports/_components/revenue-chart.tsx
    - web/src/app/(dashboard)/reports/_components/jobs-by-status-chart.tsx
    - web/src/app/(dashboard)/reports/_components/quote-conversion-chart.tsx
  modified: []

key-decisions:
  - "Recharts 3.x Tooltip formatter requires any cast — ValueType | undefined is not assignable to number; use eslint-disable-next-line comment to document intentional cast"
  - "Bar onClick in recharts 3.x types as BarMouseEvent which lacks domain data record fields — cast to any then re-cast to known type internally"
  - "PopoverTrigger (base-ui) renders native button directly — styled with inline Tailwind matching buttonVariants outline/sm pattern to avoid asChild requirement"

patterns-established:
  - "Recharts 3.x type workaround: cast formatter value and Bar onClick args to any, re-cast internally with explicit comment"

requirements-completed: [RPT-01, RPT-02]

# Metrics
duration: 7min
completed: 2026-03-19
---

# Phase 18 Plan 02: Reports Dashboard UI Summary

**Three Recharts chart panels (Revenue AreaChart, Jobs BarChart, Quote PieChart) with global date filter (4 presets + calendar picker), CSV export per chart, and click-to-drill-down navigation**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-19T13:46:29Z
- **Completed:** 2026-03-19T13:53:56Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- Reports page at `/reports` loads via dynamic import (ssr:false) with skeleton fallback
- TanStack Query fetches `/api/v1/reports/dashboard?start_date=&end_date=` and refetches automatically on date range change
- DateRangeFilter provides 4 preset buttons (Last 7d/30d/90d/YTD) and custom calendar popover with 2-month view; active preset highlighted indigo
- ChartCard reusable wrapper displays title, KPI number (text-3xl font-bold), indigo icon container, and CSV blob download per chart
- Revenue AreaChart with stacked indigo/amber areas, click navigates to /invoices?month=
- Jobs BarChart with per-status colored cells using STATUS_COLORS map, click navigates to /jobs?status=
- Quote Conversion PieChart with green/red/amber slices and percentage labels, click navigates to /quotes?status=
- Loading skeleton, error toast (duration: Infinity), and empty state all implemented

## Task Commits

Each task was committed atomically:

1. **Task 1: Reports page shell, DateRangeFilter, ChartCard wrapper, and ReportsSkeleton** - `3e92835` (feat)
2. **Task 2: Revenue, Jobs by Status, and Quote Conversion chart components with drill-down** - `8d00acb` (feat)

## Files Created/Modified
- `web/src/app/(dashboard)/reports/page.tsx` - Dynamic import entry point with "use client" directive
- `web/src/app/(dashboard)/reports/_components/reports-dashboard.tsx` - Main layout with TanStack Query, date state, 2x2 grid
- `web/src/app/(dashboard)/reports/_components/date-range-filter.tsx` - Preset buttons + calendar popover with presetToRange function
- `web/src/app/(dashboard)/reports/_components/chart-card.tsx` - Reusable card wrapper with KPI display and CSV download
- `web/src/app/(dashboard)/reports/_components/reports-skeleton.tsx` - 2x2 grid of animated skeleton cards
- `web/src/app/(dashboard)/reports/_components/revenue-chart.tsx` - Recharts AreaChart (paid/unpaid stacked)
- `web/src/app/(dashboard)/reports/_components/jobs-by-status-chart.tsx` - Recharts BarChart (per-status colors)
- `web/src/app/(dashboard)/reports/_components/quote-conversion-chart.tsx` - Recharts PieChart (conversion breakdown)

## Decisions Made
- Recharts 3.x Tooltip formatter requires `any` cast — `ValueType | undefined` is not assignable to `number`; added `eslint-disable-next-line` comments to document intentional casts
- Bar `onClick` in recharts 3.x typed as `BarMouseEvent` which omits domain record fields — cast to `any` then re-cast to known interface type internally
- `PopoverTrigger` (base-ui) renders native button directly and does not have `asChild` — styled with inline Tailwind classes matching `buttonVariants({ variant: "outline", size: "sm" })` pattern

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed recharts 3.x strict TypeScript types on Tooltip formatter and Bar onClick**
- **Found during:** Task 2 (chart components)
- **Issue:** recharts 3.x introduces strict `ValueType | undefined` for Tooltip formatter value param and `BarRectangleItem` for Bar onClick which lacks domain data fields
- **Fix:** Added `eslint-disable-next-line @typescript-eslint/no-explicit-any` casts with internal re-cast to correct types
- **Files modified:** revenue-chart.tsx, jobs-by-status-chart.tsx, quote-conversion-chart.tsx
- **Verification:** `tsc --noEmit` passes (only pre-existing chart.tsx errors remain)
- **Committed in:** 8d00acb (Task 2 commit)

**2. [Rule 1 - Bug] Fixed PopoverTrigger styling — base-ui has no asChild prop**
- **Found during:** Task 1 (DateRangeFilter)
- **Issue:** Plan specified using Button component inside PopoverTrigger but base-ui PopoverTrigger is itself a button element and doesn't support asChild
- **Fix:** Applied buttonVariants equivalent Tailwind classes directly on PopoverTrigger className
- **Files modified:** date-range-filter.tsx
- **Verification:** tsc --noEmit passes
- **Committed in:** 3e92835 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 - Bug)
**Impact on plan:** Both fixes required for TypeScript compilation. No scope creep.

## Issues Encountered
- Pre-existing TypeScript errors in `web/src/components/ui/chart.tsx` (shadcn component) remain — unrelated to this plan's changes and out of scope

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Reports page shell and 3 chart panels ready; Plan 03 slot for utilization heatmap already reserved with placeholder div in 2x2 grid
- All chart drill-down routes (/invoices, /jobs, /quotes) already implemented in previous phases

---

## Self-Check: PASSED
- All 8 files confirmed present on disk
- Both commits 3e92835 and 8d00acb confirmed in git log
- tsc --noEmit only shows pre-existing chart.tsx errors (not introduced by this plan)

---
*Phase: 18-reporting-dashboard*
*Completed: 2026-03-19*
