# Phase 18: Reporting Dashboard - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins can review business performance at a glance with charts covering revenue, job status, contractor utilization, and quote conversion, filtered by any date range. Dedicated /reports page with 4 chart panels. No new data models — consumes existing backend reporting endpoints (with one new endpoint for weekly utilization breakdowns).

</domain>

<decisions>
## Implementation Decisions

### Chart layout & density
- Dedicated `/reports` page (not on dashboard home) — matches "Reports" sidebar nav item
- 2x2 grid layout: Revenue by Month (AreaChart) + Jobs by Status (BarChart) on top row, Utilization Heatmap + Quote Conversion (PieChart) on bottom row
- Each chart card shows: title, headline KPI number (e.g., "$42,350 total revenue"), and chart below
- Responsive: 2x2 grid on desktop, single column stack on mobile/tablet

### Date range filtering
- Global date filter at top of page — one filter controls all 4 charts
- Preset quick buttons: Last 7d, 30d, 90d, YTD + custom date range calendar picker
- Default range on page load: Last 30 days
- Single API call to `/api/v1/reports/dashboard` with start_date/end_date params

### Utilization heatmap
- Contractors x Weeks grid — rows = contractors, columns = weeks in the selected date range
- Color scale: green (low utilization / available) → yellow (moderate) → red (overloaded, >85%)
- New backend endpoint needed: `GET /api/v1/reports/utilization-heatmap` returning per-contractor-per-week data
- Keeps business logic server-side rather than computing weekly breakdowns in the browser

### Chart interactivity
- Click-to-drill-down: clicking a chart element navigates to the relevant list page with filters pre-applied (e.g., click revenue bar for Feb → `/invoices?month=2026-02`)
- Rich hover tooltips with exact values, labels, and percentages — custom styled to match the app
- Subtle Recharts default animations (bars grow, lines draw in, pie slices expand)
- CSV download button per chart to export underlying data

### Claude's Discretion
- Exact Recharts component configuration and styling
- Tooltip formatting and positioning
- CSV export implementation approach
- Loading skeleton design while charts fetch data
- Empty state when no data exists for selected range

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend reporting
- `backend/app/features/reports/router.py` — Existing `/api/v1/reports/dashboard` endpoint with start_date/end_date params, DashboardResponse schema
- `backend/app/features/reports/service.py` — Report aggregation logic (jobs_by_status, revenue_by_month, contractor_utilization, quote_conversion)

### Web foundation
- `web/src/lib/api-client.ts` — apiGet/apiPost/apiPut pattern, proxy routing, 401 retry
- `web/src/components/shared/kpi-card.tsx` — Existing KPI card component pattern (title, value, icon, href, loading)
- `web/src/app/(dashboard)/page.tsx` — Dashboard home with TanStack Query patterns
- `web/src/components/ui/calendar.tsx` — Existing shadcn/ui Calendar component for date picker

### Requirements
- `.planning/REQUIREMENTS.md` — RPT-01, RPT-02, RPT-03 requirements

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `KpiCard` component: title + value + icon + link pattern — can inform chart card header design
- `StatusBadge`: already has color mappings for job statuses — reuse for jobs-by-status chart legend
- shadcn/ui `Calendar` component: available for the custom date range picker
- TanStack Query hooks: established pattern for data fetching with query keys and retry

### Established Patterns
- API proxy through `/api/proxy` route handlers (httpOnly cookie auth)
- Dynamic imports with `ssr: false` used for react-big-calendar — same pattern for Recharts
- shadcn/ui Card component for content containers
- Sonner toasts for error notifications

### Integration Points
- Sidebar nav already has "Reports" item — needs to link to `/reports`
- Backend `/api/v1/reports/dashboard` already returns 4 metric sets — just needs new utilization-heatmap endpoint
- Date picker can reuse shadcn/ui Calendar with range selection mode

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard Recharts approaches matching the existing shadcn/ui design language.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-reporting-dashboard*
*Context gathered: 2026-03-19*
