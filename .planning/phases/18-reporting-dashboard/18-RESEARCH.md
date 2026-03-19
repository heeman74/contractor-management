# Phase 18: Reporting Dashboard - Research

**Researched:** 2026-03-19
**Domain:** Next.js data visualization (Recharts 3), date range filtering, heatmap grid, backend aggregate endpoints
**Confidence:** HIGH

## Summary

Phase 18 adds a `/reports` page with four charts (AreaChart, BarChart, BarChart, PieChart), a global date range filter, and a contractor utilization heatmap. The backend already has a working `GET /api/v1/reports/dashboard` endpoint returning all four metric groups. A new `GET /api/v1/reports/utilization-heatmap` endpoint is required for the per-contractor-per-week grid view.

On the frontend, Recharts is not yet installed — it must be added at version 3.8.0 (latest stable as of research date). The shadcn/ui `chart.tsx` wrapper component (which wraps Recharts) also does not yet exist and must be added via the shadcn CLI. The existing `react-day-picker` (v9, already installed via the shadcn Calendar component) supports date range selection via the `mode="range"` prop, so no additional date-picker library is needed. All charts must be dynamically imported with `ssr: false`, matching the pattern established by Phase 15 for `react-big-calendar`.

The custom utilization heatmap is a CSS Grid table — contractors as rows, ISO weeks as columns, cells colored by utilization percentage. No third-party heatmap library is needed. The heatmap data comes from a new backend endpoint that pre-computes weekly utilization; this keeps business logic server-side, matching the CONTEXT.md decision.

**Primary recommendation:** Install `recharts` + add shadcn `chart.tsx` via CLI; use `react-day-picker` range mode for the date filter; build the heatmap as a custom CSS Grid component driven by a new `/api/v1/reports/utilization-heatmap` endpoint.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Chart layout and density:**
- Dedicated `/reports` page (not on dashboard home) — matches "Reports" sidebar nav item
- 2x2 grid layout: Revenue by Month (AreaChart) + Jobs by Status (BarChart) on top row, Utilization Heatmap + Quote Conversion (PieChart) on bottom row
- Each chart card shows: title, headline KPI number, and chart below
- Responsive: 2x2 grid on desktop, single column stack on mobile/tablet

**Date range filtering:**
- Global date filter at top of page — one filter controls all 4 charts
- Preset quick buttons: Last 7d, 30d, 90d, YTD + custom date range calendar picker
- Default range on page load: Last 30 days
- Single API call to `/api/v1/reports/dashboard` with start_date/end_date params

**Utilization heatmap:**
- Contractors x Weeks grid — rows = contractors, columns = weeks in the selected date range
- Color scale: green (low) → yellow (moderate) → red (overloaded, >85%)
- New backend endpoint: `GET /api/v1/reports/utilization-heatmap` returning per-contractor-per-week data
- Business logic server-side, not browser-side

**Chart interactivity:**
- Click-to-drill-down: clicking a chart element navigates to relevant list page with filters pre-applied
- Rich hover tooltips with exact values, labels, and percentages — custom styled
- Subtle Recharts default animations (bars grow, lines draw in, pie slices expand)
- CSV download button per chart to export underlying data

### Claude's Discretion
- Exact Recharts component configuration and styling
- Tooltip formatting and positioning
- CSV export implementation approach
- Loading skeleton design while charts fetch data
- Empty state when no data exists for selected range

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RPT-01 | Admin can view a dashboard with revenue, jobs by status, utilization, and quote conversion charts | Backend `/api/v1/reports/dashboard` already returns all 4 metric sets; Recharts provides AreaChart, BarChart, PieChart components |
| RPT-02 | Admin can filter reports by custom date range | `react-day-picker` v9 `mode="range"` covers the calendar; TanStack Query refetch with updated start_date/end_date params handles data refresh |
| RPT-03 | Admin can view contractor utilization heatmap | New `/api/v1/reports/utilization-heatmap` endpoint needed; custom CSS Grid component renders contractors × weeks grid |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| recharts | 3.8.0 | AreaChart, BarChart, PieChart rendering | Industry-standard React chart library; native SVG; supports animation, tooltips, responsive containers; React 19 compatible |
| react-day-picker | 9.14.0 | Date range calendar picker | Already installed; shadcn Calendar component wraps it; `mode="range"` built-in |
| date-fns | 4.1.0 | Date arithmetic (computing presets: last 7d, 30d, YTD) | Already installed in project |
| @tanstack/react-query | 5.90.21 | Data fetching and refetch on date range change | Already installed; established project pattern |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shadcn chart.tsx | via CLI | Recharts config context, color tokens, tooltip base | Use as thin wrapper over raw Recharts; provides CSS variable color integration |
| lucide-react | 0.577.0 | Icons on chart cards (Download for CSV, calendar icon for date filter) | Already installed |
| sonner | 2.0.7 | Error toasts on fetch failure | Already installed; use `toast.error(..., { duration: Infinity })` per project convention |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| recharts | chart.js / victory | Recharts is idiomatic with shadcn/ui; chart.js is imperative (Canvas); victory is heavier |
| custom heatmap CSS Grid | react-heatmap-grid library | Library adds a dependency for a simple grid; custom component gives exact styling control and avoids SSR issues |
| react-day-picker range mode | shadcn DateRangePicker | DateRangePicker shadcn component is just a thin wrapper over react-day-picker — use Calendar directly since it's already in the project |

**Installation (new packages only):**
```bash
# From web/ directory
npm install recharts@3.8.0

# Add shadcn chart component
npx shadcn@latest add chart
```

**Version verification:** `recharts` 3.8.0 verified via `npm view recharts version` — confirmed latest stable as of 2026-03-19. `react-day-picker` 9.14.0 already in package.json.

---

## Architecture Patterns

### Recommended Project Structure

```
web/src/app/(dashboard)/reports/
├── page.tsx                         # "use client"; dynamic import of ReportsDashboard (ssr: false)
└── _components/
    ├── reports-dashboard.tsx        # Main layout: DateRangeFilter + 2x2 chart grid
    ├── date-range-filter.tsx        # Preset buttons + Calendar popover
    ├── revenue-chart.tsx            # AreaChart (paid vs unpaid stacked)
    ├── jobs-by-status-chart.tsx     # BarChart (status → count)
    ├── quote-conversion-chart.tsx   # PieChart (approved / declined / pending)
    ├── utilization-heatmap.tsx      # Custom CSS Grid (contractors x weeks)
    ├── chart-card.tsx               # Reusable wrapper: title + KPI headline + chart + CSV button
    └── reports-skeleton.tsx         # Loading state skeleton for 2x2 grid

web/src/types/api.ts                 # Add: ReportsDashboard, UtilizationHeatmap types

backend/app/features/reports/
├── router.py                        # Add: GET /reports/utilization-heatmap endpoint
├── schemas.py                       # Add: UtilizationHeatmapItem, UtilizationHeatmapResponse
└── service.py                       # Add: get_utilization_heatmap() method
```

### Pattern 1: Dynamic Import with ssr:false (established in Phase 15)

**What:** Wrap the entire charts dashboard in `dynamic()` with `ssr: false` so Recharts (which references `window`/`document`) never renders on the server.

**When to use:** Any component importing Recharts — required for Next.js App Router.

**Example:**
```typescript
// web/src/app/(dashboard)/reports/page.tsx
"use client";

import dynamic from "next/dynamic";
import { ReportsSkeleton } from "./_components/reports-skeleton";

const ReportsDashboard = dynamic(
  () => import("./_components/reports-dashboard"),
  { ssr: false, loading: () => <ReportsSkeleton /> }
);

export default function ReportsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Reports</h1>
        <p className="text-sm text-gray-500">Business performance overview.</p>
      </div>
      <ReportsDashboard />
    </div>
  );
}
```

### Pattern 2: TanStack Query with date range params

**What:** Single query with `queryKey` including start/end dates. Changing either date causes automatic refetch.

**When to use:** The global date filter — all 4 charts share one query key so they all refresh together.

```typescript
// Inside reports-dashboard.tsx
const [dateRange, setDateRange] = useState<{ from: Date; to: Date }>(() => {
  const to = new Date();
  const from = subDays(to, 30); // date-fns
  return { from, to };
});

const startDate = format(dateRange.from, "yyyy-MM-dd"); // date-fns
const endDate = format(dateRange.to, "yyyy-MM-dd");

const { data, isLoading, isError } = useQuery({
  queryKey: ["reports", "dashboard", startDate, endDate],
  queryFn: () =>
    apiGet<DashboardResponse>(
      `/api/v1/reports/dashboard?start_date=${startDate}&end_date=${endDate}`
    ),
  retry: 1,
});

// Heatmap is a separate query (different endpoint)
const { data: heatmapData } = useQuery({
  queryKey: ["reports", "heatmap", startDate, endDate],
  queryFn: () =>
    apiGet<UtilizationHeatmapResponse>(
      `/api/v1/reports/utilization-heatmap?start_date=${startDate}&end_date=${endDate}`
    ),
  retry: 1,
});
```

### Pattern 3: Recharts ResponsiveContainer wrapping

**What:** Always wrap chart components in `<ResponsiveContainer width="100%" height={300}>` to avoid fixed-width SVG in fluid layouts.

**When to use:** Every chart — required for the 2x2 responsive grid.

```typescript
// Source: Recharts 3 docs
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid } from "recharts";

<ResponsiveContainer width="100%" height={300}>
  <AreaChart data={revenueData}>
    <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
    <XAxis dataKey="month" tick={{ fontSize: 12 }} />
    <YAxis tickFormatter={(v) => `$${v.toLocaleString()}`} tick={{ fontSize: 12 }} />
    <Tooltip formatter={(value: number) => [`$${value.toFixed(2)}`, ""]} />
    <Area type="monotone" dataKey="paid" stackId="1" stroke="var(--color-paid)" fill="var(--color-paid)" fillOpacity={0.4} />
    <Area type="monotone" dataKey="unpaid" stackId="1" stroke="var(--color-unpaid)" fill="var(--color-unpaid)" fillOpacity={0.4} />
  </AreaChart>
</ResponsiveContainer>
```

### Pattern 4: Heatmap as CSS Grid

**What:** A `<div>` grid where each cell gets a background color computed from utilization percentage. No charting library needed.

**When to use:** The contractor utilization heatmap specifically.

```typescript
// utilization-heatmap.tsx
function cellColor(utilPct: number): string {
  if (utilPct >= 85) return "bg-red-500";
  if (utilPct >= 60) return "bg-yellow-400";
  if (utilPct >= 30) return "bg-green-400";
  return "bg-green-200";
}

// Grid: first column is contractor name label, remaining columns are week headers
<div
  className="grid overflow-x-auto"
  style={{ gridTemplateColumns: `180px repeat(${weeks.length}, minmax(40px, 1fr))` }}
>
  {/* Header row */}
  <div /> {/* empty corner */}
  {weeks.map((w) => <div key={w} className="text-xs text-center text-muted-foreground">{w}</div>)}
  {/* Data rows */}
  {contractors.map((c) => (
    <React.Fragment key={c.contractor_id}>
      <div className="text-sm truncate pr-2">{c.contractor_name}</div>
      {weeks.map((w) => {
        const cell = c.weeks[w];
        return (
          <div
            key={w}
            title={`${cell?.utilization_percent ?? 0}%`}
            className={cn("h-8 rounded-sm mx-0.5", cell ? cellColor(cell.utilization_percent) : "bg-muted")}
          />
        );
      })}
    </React.Fragment>
  ))}
</div>
```

### Pattern 5: CSV download — client-side Blob

**What:** Serialize chart data to CSV string in the browser, create a Blob URL, trigger `<a download>` click.

**When to use:** CSV download button per chart card.

```typescript
function downloadCsv(filename: string, rows: string[][]): void {
  const content = rows.map((r) => r.map((c) => `"${c}"`).join(",")).join("\n");
  const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
```

Note: The REQUIREMENTS.md marks "CSV/Excel export" as out of scope, but CONTEXT.md (locked decisions) explicitly includes "CSV download button per chart" — CONTEXT.md takes precedence as it is the user's refined decision.

### Pattern 6: click-to-drill-down navigation

**What:** Recharts chart elements accept `onClick` prop. The handler receives the payload and the planner uses Next.js `router.push()` with query params.

```typescript
import { useRouter } from "next/navigation";

const router = useRouter();

// On BarChart Bar element:
<Bar
  dataKey="count"
  onClick={(data) => {
    router.push(`/jobs?status=${data.status}`);
  }}
  cursor="pointer"
/>
```

### Pattern 7: Backend — utilization heatmap endpoint

**What:** New FastAPI endpoint returning a per-contractor-per-week breakdown. Computes ISO week labels from the booking date range.

**Schema (new — add to schemas.py):**
```python
class UtilizationWeekItem(BaseModel):
    iso_week: str          # "2026-W10"
    booked_hours: Decimal = Decimal("0")
    available_hours: Decimal = Decimal("0")
    utilization_percent: Decimal = Decimal("0")

class UtilizationHeatmapContractor(BaseModel):
    contractor_id: str
    contractor_name: str
    weeks: list[UtilizationWeekItem]

class UtilizationHeatmapResponse(BaseModel):
    weeks: list[str]  # ordered list of ISO week labels for column headers
    contractors: list[UtilizationHeatmapContractor]
```

**Service approach:** One aggregate query grouping bookings by `(contractor_id, ISO_WEEK(lower(time_range)))`. Compute ISO week from PostgreSQL: `TO_CHAR(DATE_TRUNC('week', lower(time_range)), 'IYYY-"W"IW')`. Fill in zero-booking weeks for contractors who appear in the date range but have no bookings in certain weeks.

### Anti-Patterns to Avoid

- **Recharts in Server Components:** Never import Recharts in a Server Component or without `ssr: false`. It references `window` and will crash during SSR.
- **Fixed pixel height on chart containers:** Always use `ResponsiveContainer` — fixed heights break the responsive 2x2 layout.
- **Single giant useQuery for all data:** The heatmap endpoint is separate (`/utilization-heatmap`) — keep it as a separate query to allow independent loading states.
- **Computing weekly breakdowns in the browser:** The CONTEXT.md decision locks server-side computation; don't aggregate booking data from the existing `/dashboard` endpoint client-side.
- **`pumpAndSettle()` in widget tests with streams:** Not applicable here (web Playwright), but noted for any future mobile coverage.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Charts | Custom SVG chart drawing | Recharts AreaChart, BarChart, PieChart | Axis scaling, animation, tooltip positioning, responsive resize — all edge-case-heavy |
| Date arithmetic (last 30d, YTD) | Manual `new Date()` manipulation | `date-fns` `subDays`, `startOfYear`, `format` | DST-safe, leap-year-safe, already installed |
| Date range picker | Custom calendar | `react-day-picker` `mode="range"` (already installed) | Range selection, keyboard nav, ARIA — already solved |
| Recharts color theming | Inline hex colors | shadcn `chart.tsx` CSS variable pattern | Keeps color tokens aligned with Tailwind design system |
| CSV serialization | Custom escaping | Simple Blob pattern (Pattern 5 above) | The format is simple enough; don't add a library |

**Key insight:** The chart and date picker complexity is handled by established libraries. The only genuinely custom piece is the heatmap grid, which is intentionally simple CSS Grid — keep it that way.

---

## Common Pitfalls

### Pitfall 1: Recharts SSR crash in Next.js App Router

**What goes wrong:** Importing Recharts at module level in a "use client" file that Next.js still pre-renders causes "window is not defined" runtime error.

**Why it happens:** Next.js App Router pre-renders all client components on the server before hydration. Recharts accesses `window` internally.

**How to avoid:** Put all Recharts code in a separate component file (`reports-dashboard.tsx`), import it via `dynamic(..., { ssr: false })` from `page.tsx`. Never import Recharts directly in `page.tsx`.

**Warning signs:** Build error "window is not defined" or white screen with hydration mismatch.

### Pitfall 2: ResponsiveContainer width: 0 on initial render

**What goes wrong:** `ResponsiveContainer` renders with width=0 before the parent has laid out, showing no chart.

**Why it happens:** Parent container has no explicit width at mount time (e.g., inside a CSS Grid cell that hasn't been sized yet).

**How to avoid:** Ensure the chart card wrapper has `min-h-[300px]` and that the container renders in the DOM before charts attempt to measure. The `ssr: false` dynamic import handles this because the component only mounts client-side after layout.

### Pitfall 3: react-day-picker DateRange type import

**What goes wrong:** TypeScript error on `DateRange` type from `react-day-picker`.

**Why it happens:** v9 changed some type exports vs v8.

**How to avoid:** Import as: `import type { DateRange } from "react-day-picker"`. The Calendar component already uses v9 internally.

### Pitfall 4: Heatmap missing contractors with zero bookings

**What goes wrong:** The heatmap only shows contractors who have at least one booking in the date range — contractors with zero bookings in that period disappear from the grid.

**Why it happens:** The aggregate query only returns rows where bookings exist.

**How to avoid:** The backend service must LEFT JOIN all contractors against the booking subquery. Verify the `isouter=True` join is used — the existing `_get_contractor_utilization` already does this but the new per-week query must replicate it.

### Pitfall 5: ISO week boundary mismatches

**What goes wrong:** A booking on Monday Jan 1 shows in week 52 of the previous year, not week 1 of the new year.

**Why it happens:** ISO weeks can span year boundaries. PostgreSQL `TO_CHAR(..., 'IYYY-"W"IW')` handles this correctly; using `YYYY-WW` instead would be wrong.

**How to avoid:** Use `TO_CHAR(date_col, 'IYYY-"W"IW')` in the SQL for the heatmap endpoint. Verify with a test that checks dates straddling a year boundary.

### Pitfall 6: `toast.error()` without `duration: Infinity`

**What goes wrong:** Error toast auto-dismisses before the user reads it.

**Why it happens:** Project convention (from Phase 13) requires all `toast.error()` calls to include `{ duration: Infinity }`.

**How to avoid:** Every fetch error handler: `toast.error("...", { duration: Infinity })`.

---

## Code Examples

### Recharts AreaChart for Revenue by Month

```typescript
// Source: recharts.org docs + project Tailwind integration
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid } from "recharts";

// data shape from backend: { month: "2026-03", paid: 5400.00, unpaid: 1200.00 }
<ResponsiveContainer width="100%" height={280}>
  <AreaChart data={revenueData} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
    <XAxis dataKey="month" tick={{ fontSize: 11 }} tickLine={false} />
    <YAxis
      tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`}
      tick={{ fontSize: 11 }}
      tickLine={false}
      axisLine={false}
    />
    <Tooltip
      formatter={(value: number, name: string) => [
        `$${value.toLocaleString("en-AU", { minimumFractionDigits: 2 })}`,
        name === "paid" ? "Paid" : "Outstanding",
      ]}
    />
    <Area type="monotone" dataKey="paid" stackId="1"
      stroke="#4f46e5" fill="#4f46e5" fillOpacity={0.25} />
    <Area type="monotone" dataKey="unpaid" stackId="1"
      stroke="#f59e0b" fill="#f59e0b" fillOpacity={0.25} />
  </AreaChart>
</ResponsiveContainer>
```

### Recharts PieChart for Quote Conversion

```typescript
import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip, Legend } from "recharts";

const COLORS = { approved: "#22c55e", declined: "#ef4444", pending: "#f59e0b" };

const pieData = [
  { name: "Approved", value: data.quote_conversion.approved, key: "approved" },
  { name: "Declined", value: data.quote_conversion.declined, key: "declined" },
  { name: "Pending",  value: data.quote_conversion.pending,  key: "pending" },
].filter((d) => d.value > 0);

<ResponsiveContainer width="100%" height={280}>
  <PieChart>
    <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={90} label>
      {pieData.map((entry) => (
        <Cell key={entry.key} fill={COLORS[entry.key as keyof typeof COLORS]} />
      ))}
    </Pie>
    <Tooltip formatter={(value: number) => [value, ""]} />
    <Legend />
  </PieChart>
</ResponsiveContainer>
```

### Date range preset logic with date-fns

```typescript
import { subDays, startOfYear, format } from "date-fns";

type Preset = "7d" | "30d" | "90d" | "ytd";

function presetToRange(preset: Preset): { from: Date; to: Date } {
  const to = new Date();
  switch (preset) {
    case "7d":  return { from: subDays(to, 7), to };
    case "30d": return { from: subDays(to, 30), to };
    case "90d": return { from: subDays(to, 90), to };
    case "ytd": return { from: startOfYear(to), to };
  }
}
```

### react-day-picker range mode

```typescript
// Uses existing Calendar component from web/src/components/ui/calendar.tsx
import { Calendar } from "@/components/ui/calendar";
import type { DateRange } from "react-day-picker";

const [range, setRange] = useState<DateRange | undefined>();

<Calendar
  mode="range"
  selected={range}
  onSelect={setRange}
  numberOfMonths={2}
/>
```

### Backend: utilization heatmap query sketch

```python
# In service.py — get_utilization_heatmap()
from sqlalchemy import func, cast, literal_column, text

iso_week_expr = func.to_char(
    func.date_trunc("week", func.lower(Booking.time_range)),
    "IYYY-\"W\"IW"
).label("iso_week")

duration_hours_expr = func.coalesce(
    func.sum(
        func.extract("epoch", func.upper(Booking.time_range) - func.lower(Booking.time_range))
        / cast(3600, Numeric)
    ),
    cast(0, Numeric)
).label("booked_hours")

result = await self.db.execute(
    select(
        User.id.label("contractor_id"),
        (func.coalesce(User.first_name, "") + " " + func.coalesce(User.last_name, "")).label("contractor_name"),
        iso_week_expr,
        duration_hours_expr,
    )
    .join(UserRoleModel, (UserRoleModel.user_id == User.id) & (UserRoleModel.role == "contractor"))
    .join(Booking, Booking.contractor_id == User.id, isouter=True)
    .where(User.deleted_at.is_(None), UserRoleModel.deleted_at.is_(None))
    .where(*booking_conditions)
    .group_by(User.id, User.first_name, User.last_name, iso_week_expr)
    .order_by(User.first_name, iso_week_expr)
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| shadcn Chart wraps Chart.js | shadcn Chart wraps Recharts | shadcn 2024+ | Recharts is now the canonical shadcn charting library |
| Recharts 2.x API | Recharts 3.x — same core API, improved TypeScript | 2024 | Types are better; `isAnimationActive` default true |
| react-day-picker v8 `DateRange` import | v9 — same import, minor API changes | 2024 | Already at v9 in this project |

**Deprecated/outdated:**
- `recharts` 2.x: same conceptual API but TypeScript types were weaker — use 3.x
- `nivo` charts: heavier bundle, more complex config — Recharts preferred for this project's shadcn alignment

---

## Open Questions

1. **Sidebar `/reports` link active state**
   - What we know: The sidebar already has `{ label: "Reports", href: "/reports", icon: BarChart3 }` defined.
   - What's unclear: Whether the active route highlighting (if any) uses `usePathname()` — need to verify sidebar implementation doesn't need changes.
   - Recommendation: Read `sidebar.tsx` during plan execution and verify.

2. **`available_hours` calculation in weekly heatmap**
   - What we know: The existing utilization service uses a simplified "5/7 of days × 8h" formula per contractor across the whole period.
   - What's unclear: For weekly granularity, should available_hours per week be exactly 5×8=40h or respect contractor working-hours settings?
   - Recommendation: Use fixed 40h/week for now (consistent with existing service approximation). The working-hours feature (CONTR-03) stores weekly hours, but reading them per contractor per week adds significant complexity not in scope.

3. **Recharts `react-is` peer dependency**
   - What we know: Recharts 3.8.0 peer-requires `react-is` alongside React 19. The project does not currently have `react-is` installed.
   - What's unclear: Whether Next.js 16's bundled React ships `react-is` transitively.
   - Recommendation: Add `react-is` to dependencies during install: `npm install recharts@3.8.0 react-is`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework (web) | Playwright 1.58.2 |
| Config file | `web/playwright.config.ts` |
| Quick run command | `cd web && npx playwright test tests/phase-18-reports.spec.ts --project=chromium` |
| Full suite command | `cd web && npm run test-e2e` |
| Framework (backend) | pytest + anyio (see `backend/tests/conftest.py`) |
| Backend quick run | `cd backend && uv run python -m pytest tests/test_phase_18_e2e.py -x` |
| Backend full suite | `cd backend && uv run python -m pytest` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RPT-01 | Reports page loads with 4 chart sections visible | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "four chart sections"` | ❌ Wave 0 |
| RPT-01 | `/api/v1/reports/dashboard` returns 200 with all 4 metric groups | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestDashboard -x` | ❌ Wave 0 |
| RPT-01 | Revenue chart renders AreaChart with month labels | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "revenue chart"` | ❌ Wave 0 |
| RPT-01 | Jobs by status BarChart visible with status labels | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "jobs chart"` | ❌ Wave 0 |
| RPT-01 | Quote conversion PieChart visible | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "quote conversion"` | ❌ Wave 0 |
| RPT-02 | Clicking "Last 7d" preset changes displayed range label | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "date preset 7d"` | ❌ Wave 0 |
| RPT-02 | Clicking "YTD" preset triggers API call with correct start_date | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "ytd preset"` | ❌ Wave 0 |
| RPT-02 | `/api/v1/reports/dashboard?start_date=X&end_date=Y` filters correctly | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestDateFilter -x` | ❌ Wave 0 |
| RPT-03 | Heatmap grid renders with contractor rows and week columns | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "heatmap grid"` | ❌ Wave 0 |
| RPT-03 | `/api/v1/reports/utilization-heatmap` returns 200 with weeks + contractors | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestHeatmap -x` | ❌ Wave 0 |
| RPT-03 | Contractor with zero bookings still appears in heatmap | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestHeatmapEmptyContractor -x` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `cd web && npx playwright test tests/phase-18-reports.spec.ts --project=chromium`
- **Per wave merge:** `cd web && npm run test-e2e && cd ../backend && uv run python -m pytest tests/test_phase_18_e2e.py -x`
- **Phase gate:** Full Playwright suite + backend pytest green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `web/tests/phase-18-reports.spec.ts` — Playwright E2E covering RPT-01, RPT-02, RPT-03
- [ ] `backend/tests/test_phase_18_e2e.py` — backend integration tests for `/dashboard` date filtering and `/utilization-heatmap`

---

## Sources

### Primary (HIGH confidence)
- `backend/app/features/reports/router.py` — confirmed existing `/dashboard` endpoint signature
- `backend/app/features/reports/service.py` — confirmed all 4 metric queries, contractor LEFT JOIN pattern
- `backend/app/features/reports/schemas.py` — confirmed DashboardResponse shape, all sub-schemas
- `web/package.json` — confirmed installed packages: react-day-picker 9.14.0, date-fns 4.1.0, TanStack Query 5.x
- `web/src/components/ui/calendar.tsx` — confirmed shadcn Calendar wraps react-day-picker v9, `mode="range"` available
- `web/src/app/(dashboard)/schedule/page.tsx` — confirmed `dynamic(..., { ssr: false })` pattern
- `npm view recharts version` — verified 3.8.0 is current stable

### Secondary (MEDIUM confidence)
- Recharts 3.8.0 peer dependency check via `npm view recharts@3.8.0 peerDependencies` — React 19 compatible confirmed
- shadcn/ui chart component availability — not yet installed; standard `npx shadcn@latest add chart` installs it alongside recharts

### Tertiary (LOW confidence)
- `react-is` peer dependency: assumed transitive via React ecosystem; should verify during install

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified via npm registry and installed package.json
- Architecture: HIGH — patterns sourced from existing codebase (schedule page, service.py patterns)
- Pitfalls: HIGH — SSR pitfall verified against existing dynamic import pattern; others from code inspection
- Backend endpoint: HIGH — existing service pattern confirmed; new heatmap follows same SQLAlchemy conventions

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable libraries — 30-day window reasonable)
