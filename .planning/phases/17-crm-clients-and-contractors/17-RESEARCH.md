# Phase 17: CRM — Clients and Contractors - Research

**Researched:** 2026-03-17
**Domain:** Next.js (App Router) CRM UI + FastAPI CRM router + CSS-grid schedule editor
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Client list presentation**
- Flat searchable list (no status tabs — clients don't have statuses)
- Server-side search and pagination via CrmService.list_clients() (already supports name/email search)
- Rich columns: Name, Email, Phone, Tags (as chips), Preferred Contractor, Jobs Count
- Sortable columns, default sort by name alphabetical
- Click row navigates to /clients/[id] detail page

**Client detail layout**
- Full CRM profile with two-column layout (main ~65% + sidebar ~35%)
- Main content sections (top to bottom):
  - Job history table: reverse chronological, columns = Job #, Title, Status (StatusBadge), Contractor, Date. Click row → /jobs/[id]
  - Saved properties: compact address list with "Default" badge on primary property, click to expand full address details. Read-only
  - Admin notes: inline in sidebar, always visible, read-only
- Sidebar sections: contact card (name, email, phone), tags (as chips), average rating, referral source, preferred contractor (linked to /contractors/[id]), billing address
- Read-only for now — no editing of client profiles from web (CRM-01 and CRM-02 only require viewing)

**Contractor list presentation**
- Flat searchable list with server-side pagination
- Columns: Name, Email, Phone, Trade Type (badge), Availability Status (badge), Active Jobs Count
- Availability badge: Green "Available" / Yellow "Partially booked" / Red "Fully booked" based on today's schedule
- Sortable columns, click row navigates to /contractors/[id]

**Contractor profile layout**
- Two-column layout (main ~65% + sidebar ~35%) — consistent with client detail and job detail patterns
- Main content (top to bottom):
  - Weekly schedule summary: visual grid showing working hours per day (Mon–Sun). "Edit Schedule" button navigates to /contractors/[id]/schedule
  - Assigned jobs table: reverse chronological, columns = Job #, Title, Status (StatusBadge), Client, Date. Click row → /jobs/[id]
- Sidebar: contact info (name, email, phone), trade type badge, average rating, quick stats (active jobs count, hours this week)

**Weekly schedule editor**
- Dedicated page at /contractors/[id]/schedule. Breadcrumb: Contractors > [Name] > Schedule
- Visual 7-column grid (Mon–Sun), rows = hours (6am–8pm). Click and drag to paint working hours. Existing blocks shown as colored fills
- Per-day auto-save: each day saves independently when changed (PUT /schedules/{id}/weekly/{dow}). Success toast per save
- Date overrides section below the weekly grid:
  - Calendar date picker to select the override date
  - Toggle: "Unavailable all day" or set custom hours with time pickers
  - Existing overrides shown as highlighted dates on the calendar picker
  - Save via PUT /schedules/{id}/overrides/{date}

**Cross-page linking**
- Job detail page: client_name → /clients/[id], contractor name → /contractors/[id] (clickable links)
- Quote detail sidebar: client name → /clients/[id]
- Invoice detail sidebar: client name → /clients/[id]
- Contractor profile: assigned jobs table rows → /jobs/[id]
- Client detail: job history table rows → /jobs/[id], preferred contractor → /contractors/[id]
- Schedule calendar (Phase 15): contractor lane headers → /contractors/[id]

### Claude's Discretion
- Exact visual grid component implementation for schedule editor (custom canvas vs CSS grid vs third-party)
- Drag-to-paint interaction details for the schedule grid
- Availability badge calculation logic (how to determine Available/Partially/Fully booked thresholds)
- Exact skeleton loading shapes for all pages
- Tag chip styling and color assignments
- Property list expand/collapse animation
- Exact spacing, typography, and component sizing
- Empty state messages for clients/contractors with no results
- Pagination controls styling (reuse pattern from jobs list)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CRM-01 | Admin can view a searchable list of all clients | CrmService.list_clients() is already built; needs a CRM router at /api/v1/crm/; web page at /clients replicates jobs list pattern |
| CRM-02 | Admin can view client detail with all past and active job history | CrmService.get_client_with_job_history() is already built; ClientProfile model has all fields needed; web page at /clients/[id] replicates job detail two-column pattern |
| CONTR-01 | Admin can view all contractors with availability summary | GET /api/v1/users?role=contractor exists; availability badge requires POST /scheduling/availability for today; web page at /contractors |
| CONTR-02 | Admin can view contractor profile with assigned jobs and weekly schedule | GET /api/v1/jobs?contractor_id= + GET /api/v1/scheduling/schedules/{id}/weekly; web page at /contractors/[id] |
| CONTR-03 | Admin can edit a contractor's weekly working hours | PUT /api/v1/scheduling/schedules/{id}/weekly/{dow} already exists; needs schedule editor UI at /contractors/[id]/schedule |
| CONTR-04 | Admin can set date overrides (mark dates unavailable or custom hours) | PUT /api/v1/scheduling/schedules/{id}/overrides/{date} already exists; date override UI is a section of the schedule editor page |
</phase_requirements>

---

## Summary

Phase 17 is primarily a UI-assembly phase: the backend business logic (CrmService, SchedulingService) is already fully built. The main backend task is creating a thin CRM router to expose the existing service. The web work is a set of five new Next.js pages and cross-linking updates to four existing pages.

The CRM router needs two endpoints: `GET /api/v1/crm/clients` (list with search + pagination) and `GET /api/v1/crm/clients/{user_id}` (detail with job history). These delegate directly to CrmService methods. Contractor listing uses the existing users endpoint filtered by role=contractor; contractor profiles fetch jobs via the jobs endpoint filtered by contractor_id.

The schedule editor is the highest-complexity deliverable. It is a custom CSS-grid component (Mon–Sun columns, 6am–8pm rows). Drag-to-paint interaction is implemented with mousedown/mousemove/mouseup event tracking plus a pointer capture pattern to survive leaving and re-entering cells. This is entirely within Claude's discretion and does not require a third-party drag library.

**Primary recommendation:** Wire the CRM router first (one file), then build the five web pages in plan order (client list → client detail → contractor list → contractor profile → schedule editor), finishing with cross-link updates.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Next.js App Router | Already installed (project-wide) | Routing, pages | Established Phase 13 |
| TanStack Query | Already installed | Server-state fetching/caching | Established Phase 13 |
| shadcn/ui | Already installed | Card, Badge, Button, Input, Table, Skeleton, Sonner, Dialog | Used across all phases |
| Tailwind CSS | Already installed | Styling | Used across all phases |
| FastAPI + SQLAlchemy async | Already installed | Backend router | Project standard |
| react-day-picker | Already installed via shadcn Calendar | Date picker for overrides section | Same library shadcn Calendar uses internally |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lucide-react | Already installed | Icons (Search, ChevronDown, ArrowUpDown, etc.) | All icon needs |
| sonner (Toaster) | Already installed | Success/error toasts | Per-day save confirmations |
| date-fns | Already installed (peer dep) | Date formatting, week calculations | Schedule editor date handling |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom CSS-grid schedule editor | react-big-calendar (Phase 15 library) | react-big-calendar is week-view only and lacks drag-to-paint; custom is simpler for a working-hours editor |
| Custom CSS-grid schedule editor | @dnd-kit | Overkill — drag-to-paint over a regular grid is ~40 lines of pointer events, no need for a DnD library |
| GET /api/v1/users?role=contractor for contractor list | New contractor endpoint | Users endpoint already filters by role; avoids backend duplication |

**Installation:** No new packages required — all needed libraries are already present.

---

## Architecture Patterns

### Recommended Project Structure

```
backend/app/features/jobs/
├── crm_router.py          # NEW — thin router exposing CrmService (GET /crm/clients, GET /crm/clients/{id})

web/src/app/(dashboard)/
├── clients/
│   ├── page.tsx           # NEW — 17-01: client list with search + pagination
│   └── [id]/
│       └── page.tsx       # NEW — 17-02: client detail (two-column layout)
├── contractors/
│   ├── page.tsx           # NEW — 17-03: contractor list with availability badges
│   └── [id]/
│       ├── page.tsx       # NEW — 17-04: contractor profile (two-column layout)
│       └── schedule/
│           └── page.tsx   # NEW — 17-05: schedule editor (grid + overrides)

web/src/types/api.ts        # EXTEND — add ClientProfile, ContractorSummary, WeeklySchedule types
```

### Pattern 1: CRM Router (Backend)

**What:** Thin FastAPI router delegating to CrmService. Does NOT use CRUDRouter because the endpoints are read-only and have non-standard response shapes (client detail bundles profile + jobs).
**When to use:** Any custom read endpoint that doesn't fit standard CRUD.

```python
# Source: project pattern from scheduling/router.py
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.core.security import get_current_user
from app.core.tenant import get_current_tenant_id
from app.features.jobs.crm_service import CrmService
from app.features.jobs.schemas import ClientProfileResponse  # extend for list response

router = APIRouter(prefix="/crm", tags=["crm"])

@router.get("/clients", response_model=list[ClientListResponse])
async def list_clients(
    search: str | None = Query(default=None),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _current_user = Depends(get_current_user),
) -> list[ClientListResponse]:
    company_id = get_current_tenant_id()
    svc = CrmService(db)
    profiles = await svc.list_clients(company_id, search, offset, limit)
    return [ClientListResponse.from_profile(p) for p in profiles]

@router.get("/clients/{user_id}", response_model=ClientDetailResponse)
async def get_client_detail(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user = Depends(get_current_user),
) -> ClientDetailResponse:
    svc = CrmService(db)
    profile, jobs = await svc.get_client_with_job_history(user_id)
    return ClientDetailResponse.from_profile_and_jobs(profile, jobs)
```

**Key insight:** ClientListResponse needs `first_name`, `last_name`, `email`, `phone` from the eagerly-loaded `profile.user`. ClientDetailResponse needs the same plus jobs, properties, admin_notes, tags, billing_address, average_rating, referral_source, preferred_contractor.

### Pattern 2: Client/Contractor List Page (Web)

**What:** Replication of the jobs list pattern: `useQuery` → `apiGet` → Table rows → `router.push`. No status tabs (clients have no statuses).
**When to use:** Any flat searchable paginated list.

```typescript
// Source: adapted from web/src/app/(dashboard)/jobs/page.tsx
// Key difference: debounced search updates URL param and re-triggers useQuery
const { data: clients, isLoading } = useQuery({
  queryKey: ["clients", { search: debouncedSearch, page }],
  queryFn: () => {
    const params = new URLSearchParams();
    if (debouncedSearch) params.set("search", debouncedSearch);
    params.set("offset", String((page - 1) * PAGE_SIZE));
    params.set("limit", String(PAGE_SIZE));
    return apiGet<ClientListItem[]>(`/api/v1/crm/clients?${params}`);
  },
});
```

### Pattern 3: Two-Column Detail Layout (Web)

**What:** Established pattern from Phase 14 and Phase 16. `grid-cols-1 lg:grid-cols-[1fr_360px]`.
**When to use:** Any detail page needing main content + sidebar.

```typescript
// Source: web/src/app/(dashboard)/jobs/[id]/page.tsx line 358
<div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
  <div className="space-y-6">{/* main */}</div>
  <div className="space-y-4">{/* sidebar */}</div>
</div>
```

### Pattern 4: Availability Badge Calculation

**What:** Determine green/yellow/red badge for contractor availability. Uses `POST /api/v1/scheduling/availability` with `contractor_ids=[id]` and `date=today`.
**Logic:**
- No weekly schedule configured → "Fully booked" (red)
- `free_windows.length === 0` → "Fully booked" (red)
- `free_windows` exist and all windows are ≥ 4 hours total → "Available" (green)
- `free_windows` exist but total free time < 4 hours → "Partially booked" (yellow)

**When to use:** Contractor list page availability badge per row; contractor profile sidebar quick stats.

**Important caveat:** Calling `POST /scheduling/availability` for every contractor in a list is N+1 (one POST per contractor). Instead, call once with `contractor_ids=[all contractor IDs on the page]` to batch the availability check.

```typescript
// Batch availability: one call for all visible contractors
const contractorIds = contractors?.map(c => c.id) ?? [];
const { data: availability } = useQuery({
  queryKey: ["availability-today", contractorIds],
  queryFn: () => contractorIds.length === 0 ? [] : apiPost<AvailabilityResponse[]>(
    "/api/v1/scheduling/availability",
    { contractor_ids: contractorIds, date: new Date().toISOString().split("T")[0] }
  ),
  enabled: contractorIds.length > 0,
});
```

### Pattern 5: CSS-Grid Schedule Editor

**What:** 7-column (Mon–Sun) × 15-row grid (6am–8pm, hourly). Drag-to-paint using pointer events. Each cell represents a 1-hour slot. A filled cell = that hour is a working block.
**When to use:** The `/contractors/[id]/schedule` page only.

```typescript
// Drag-to-paint: track mousedown → mousemove → mouseup
// Use setPointerCapture to keep receiving events after leaving a cell
const [isDragging, setIsDragging] = useState(false);
const [paintValue, setPaintValue] = useState<boolean>(true); // fill or clear

function handleCellPointerDown(day: number, hour: number, e: React.PointerEvent) {
  e.currentTarget.setPointerCapture(e.pointerId);
  setIsDragging(true);
  const currentlyFilled = schedule[day]?.includes(hour);
  setPaintValue(!currentlyFilled); // toggle: dragging on empty fills, dragging on filled clears
  toggleCell(day, hour, !currentlyFilled);
}

function handleCellPointerEnter(day: number, hour: number) {
  if (!isDragging) return;
  toggleCell(day, hour, paintValue);
}

function handlePointerUp() {
  setIsDragging(false);
  // Auto-save the day that changed
  saveDaySchedule(changedDay);
}
```

**Converting cell selections to TimeBlock[]:** Each contiguous run of selected hours in a day becomes one `TimeBlock`. E.g., hours [9, 10, 11] → `{ start_time: "09:00", end_time: "12:00" }`.

**Saving:** `PUT /api/v1/scheduling/schedules/{contractor_id}/weekly/{day_of_week}` with `{ blocks: TimeBlock[] }`. The `day_of_week` uses 0=Monday convention from the backend.

### Pattern 6: Date Overrides Section

**What:** Below the weekly grid. Uses shadcn Calendar (react-day-picker) to select override date. Highlighted dates = existing overrides (passed as `modifiers.hasOverride`). On date select, show toggle (unavailable / custom hours) + time pickers + Save button.
**When to use:** Bottom section of the `/contractors/[id]/schedule` page.

**Loading existing overrides:** `GET /api/v1/scheduling/schedules/{id}/overrides?date_from=today&date_to=today+90days`

**Saving:** `PUT /api/v1/scheduling/schedules/{id}/overrides/{date}` with `{ is_unavailable: bool, blocks: TimeBlock[] | null }`

### Anti-Patterns to Avoid

- **Calling availability endpoint per-contractor in contractor list:** Batch all contractor IDs into a single POST request.
- **Fetching jobs inside the CRM router:** Jobs are loaded via a separate query (`GET /api/v1/jobs?contractor_id=`) on the detail page, not embedded in the profile response. This keeps the list endpoint fast.
- **Using `db.commit()` in crm_router.py:** `get_db` dependency handles commit/rollback — never commit in service or router.
- **Pasting client_name into links:** Job detail already has `client_id` and `contractor_id` — use those as the href, not searching by name.
- **Blocking the planner on `jobs_count` in client list:** CrmService.list_clients returns `ClientProfile` objects. A `jobs_count` column requires a subquery or separate count. The simplest approach: add a subquery count directly in `CrmRepository.list_client_profiles` using `func.count(Job.id)` with a subquery.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date picker for override section | Custom date input | shadcn `Calendar` (react-day-picker) | Already in the project; supports `modifiers` for highlighting existing overrides |
| Time block conversion (hours → TimeBlock[]) | Complicated state merge | Simple contiguous-run algorithm (~10 lines) | See Code Examples section |
| Toast notifications | Custom toast UI | Sonner (already installed) | Established project pattern |
| Pagination controls | Custom pagination component | Reuse the Previous/Next pattern from jobs/page.tsx | Already built and styled |
| Status badge for availability | New Badge component | Extend existing `StatusBadge` color map | Add `available`, `partially_booked`, `fully_booked` entries |

**Key insight:** Every UI primitive is already installed. This phase is composition, not library adoption.

---

## Common Pitfalls

### Pitfall 1: CRM Router Not Registered in main.py

**What goes wrong:** New router file created but not imported and included in `app/main.py` → 404 on all CRM endpoints.
**Why it happens:** main.py requires an explicit `include_router` call per feature.
**How to avoid:** After creating `crm_router.py`, immediately add:
```python
from app.features.jobs.crm_router import router as crm_router
app.include_router(crm_router, prefix="/api/v1")
```
**Warning signs:** Playwright tests get 404s on `/api/v1/crm/clients`.

### Pitfall 2: ClientListResponse Missing Nested User Fields

**What goes wrong:** `ClientProfileResponse` (existing schema) does not include `first_name`, `last_name`, `email`, `phone` — those live on `profile.user`. If the router serializes `ClientProfileResponse` directly, the web layer only gets `user_id`, not the display name.
**Why it happens:** CRM profile and User are separate ORM models. The CRM list endpoint needs a richer response schema.
**How to avoid:** Create `ClientListResponse` schema that flattens `user.first_name`, `user.last_name`, `user.email`, `user.phone`, `profile.tags`, `profile.preferred_contractor_id`, plus `jobs_count` (subquery). The CrmRepository already eager-loads `profile.user` with `joinedload`.

### Pitfall 3: Availability Batch vs. N+1

**What goes wrong:** Contractor list fires one `POST /scheduling/availability` per row → 20+ requests on page load.
**Why it happens:** Intuitive pattern mirrors individual row rendering.
**How to avoid:** Fetch all contractors first, collect all IDs, then fire a single batch availability POST. Use `useQuery` with `enabled: contractors !== undefined && contractors.length > 0`.
**Warning signs:** Network tab shows many sequential POST requests to /scheduling/availability.

### Pitfall 4: Day-of-Week Indexing Mismatch

**What goes wrong:** The schedule grid displays Mon=0 visually, but if JavaScript `Date.getDay()` is used (Sun=0), days are shifted.
**Why it happens:** The backend uses `day_of_week` 0=Monday consistently (per router docstring). JavaScript Date uses 0=Sunday.
**How to avoid:** Never use `Date.getDay()` for DOW. Use a fixed array `["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]` indexed 0–6. When constructing dates for display only, use index directly.

### Pitfall 5: Schedule Editor Drag Breaks on Mobile / Touch

**What goes wrong:** `onMouseDown`/`onMouseMove` events don't fire on touch devices. Since this is an admin web tool, touch is lower priority but still causes confusing failures in Playwright tests.
**Why it happens:** Mouse events vs. pointer events.
**How to avoid:** Use pointer events (`onPointerDown`, `onPointerMove`, `onPointerUp`) which work for both mouse and touch. Use `setPointerCapture` so events continue even when dragging outside the cell.

### Pitfall 6: Per-Day Auto-Save Race Condition

**What goes wrong:** User drags across two days quickly; two simultaneous PUT requests fire for different days. Both succeed, but the second response arrives first.
**Why it happens:** Each day saves independently on change. No debounce.
**How to avoid:** Debounce the save trigger per-day (300ms). Use TanStack Query `useMutation` per day. Since each day is an independent `PUT` that completely replaces that day's schedule, race conditions are safe — the last write wins and is correct.

### Pitfall 7: jobs_count Requires Subquery in CrmRepository

**What goes wrong:** `list_client_profiles` returns `ClientProfile` ORM objects; there is no `jobs_count` attribute. Adding it naively causes an N+1 (count query per profile).
**Why it happens:** SQLAlchemy ORM returns model instances, not dicts with computed columns, unless the query explicitly adds scalar subqueries.
**How to avoid:** Add a scalar subquery to `list_client_profiles`:
```python
from sqlalchemy import func, select as sa_select
jobs_count_sq = (
    sa_select(func.count(Job.id))
    .where(Job.client_id == User.id)
    .where(Job.deleted_at.is_(None))
    .correlate(User)
    .scalar_subquery()
    .label("jobs_count")
)
stmt = stmt.add_columns(jobs_count_sq)
# Result rows are now (ClientProfile, int) tuples, not just ClientProfile objects
```
Alternatively, calculate jobs_count client-side from job history data (only feasible on detail page, not list page). For the list page, the subquery approach is required.

---

## Code Examples

Verified patterns from existing codebase:

### CRM Router Registration Pattern

```python
# Source: backend/app/main.py lines 14-116 (established pattern)
# In main.py, add after the existing router imports:
from app.features.jobs.crm_router import router as crm_router
# ...
app.include_router(crm_router, prefix="/api/v1")
```

### Extending StatusBadge for Availability

```typescript
// Source: web/src/components/shared/status-badge.tsx
// Add to colorMap:
available: "bg-green-100 text-green-800",
partially_booked: "bg-yellow-100 text-yellow-800",
fully_booked: "bg-red-100 text-red-800",
```
Then use `<StatusBadge status={availabilityStatus} size="sm" />` where `availabilityStatus` is `"available"`, `"partially_booked"`, or `"fully_booked"`.

### Hours-to-TimeBlock Conversion

```typescript
// Convert a sorted array of selected hour indices to TimeBlock[]
// E.g., [9, 10, 11, 13, 14] → [{start:"09:00", end:"12:00"}, {start:"13:00", end:"15:00"}]
function hoursToBlocks(hours: number[]): TimeBlock[] {
  if (hours.length === 0) return [];
  const sorted = [...new Set(hours)].sort((a, b) => a - b);
  const blocks: TimeBlock[] = [];
  let start = sorted[0];
  let prev = sorted[0];

  for (let i = 1; i <= sorted.length; i++) {
    const current = sorted[i];
    if (current !== prev + 1) {
      blocks.push({
        start_time: `${String(start).padStart(2, "0")}:00`,
        end_time: `${String(prev + 1).padStart(2, "0")}:00`,
      });
      start = current;
    }
    prev = current;
  }
  return blocks;
}
```

### Weekly Schedule Fetch and Display

```typescript
// Source: scheduling/router.py GET /schedules/{contractor_id}/weekly
// Response shape: { "0": [{id, start_time, end_time, ...}], "1": [...], ... }
// Only days with blocks are included — missing keys mean no schedule for that day.
const { data: weeklySchedule } = useQuery({
  queryKey: ["weekly-schedule", contractorId],
  queryFn: () => apiGet<Record<string, WeeklyBlock[]>>(
    `/api/v1/scheduling/schedules/${contractorId}/weekly`
  ),
});

// For display: normalize to Record<number, WeeklyBlock[]>
const scheduleByDay = weeklySchedule
  ? Object.fromEntries(
      Object.entries(weeklySchedule).map(([k, v]) => [parseInt(k), v])
    )
  : {};
```

### Date Overrides Fetch

```typescript
// Source: scheduling/router.py GET /schedules/{id}/overrides
// Requires date_from and date_to query params
const today = new Date().toISOString().split("T")[0];
const ninetyDaysOut = new Date(Date.now() + 90 * 86400000).toISOString().split("T")[0];
const { data: overrides } = useQuery({
  queryKey: ["date-overrides", contractorId],
  queryFn: () => apiGet<DateOverride[]>(
    `/api/v1/scheduling/schedules/${contractorId}/overrides?date_from=${today}&date_to=${ninetyDaysOut}`
  ),
});

// Highlighted dates for Calendar component:
const overrideDates = overrides?.map(o => new Date(o.override_date)) ?? [];
```

### Contractor List — Users Endpoint with Role Filter

```typescript
// Source: backend/app/features/users/router.py — GET /api/v1/users/
// UserResponse includes roles: string[]  — filter client-side by role includes "contractor"
// OR: use ?role=contractor if that query param is supported (check users router first)
// The current users router uses CRUDRouter.list which may not support role filtering.
// Safe approach: fetch all users and filter client-side, OR add role query param to users router.
const { data: allUsers } = useQuery({
  queryKey: ["users"],
  queryFn: () => apiGet<UserResponse[]>("/api/v1/users/"),
});
const contractors = allUsers?.filter(u => u.roles.includes("contractor")) ?? [];
```
**NOTE (LOW confidence):** Whether the existing `/api/v1/users/` endpoint supports a `?role=` query param needs verification by reading the CRUDRouter base class. If not supported, the backend task for plan 17-03 should either add the filter or filter client-side (acceptable if contractor count is small, e.g., < 200).

### Cross-Link Pattern in Job Detail (Already Partially Done)

```typescript
// Source: web/src/app/(dashboard)/jobs/[id]/page.tsx lines 682-709
// The job detail page already renders /contractors/{id} and /clients/{id} links
// using job.contractor_id and job.client_id. Phase 17 task is to replace
// the raw UUID display (id.slice(0,8)) with the actual name from job.client_name.
// job.client_name is already in JobResponse (added in Phase 15).
// contractor_name is NOT currently in JobResponse — need to check if it should be added
// or if a separate fetch is used.
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| New CrmService endpoints | CrmService fully built with list_clients, get_client_with_job_history | Phase 8 (backend) | No service code needed — just router + schemas |
| Scheduling endpoints | PUT weekly/{dow}, PUT overrides/{date}, GET weekly, GET overrides all exist | Phase 5 (backend) | No backend scheduling work needed |
| Status badge colors | Extended with quote/invoice statuses | Phase 16 | Extend colorMap for availability statuses |

**Deprecated/outdated:**
- X-Company-Id header: replaced by JWT-derived company_id. All new endpoints use `get_current_tenant_id()`.

---

## Open Questions

1. **jobs_count in client list — subquery vs. omit?**
   - What we know: CrmRepository.list_client_profiles returns `ClientProfile` objects without a count
   - What's unclear: Whether a scalar subquery in the ORM query is the right approach or if we should omit jobs_count from the list view to keep it simple
   - Recommendation: Include jobs_count in the list using a scalar subquery; it's a standard SQLAlchemy pattern and the column is part of the locked decisions (columns include "Jobs Count")

2. **Contractor list — role filtering at API vs. client-side**
   - What we know: `GET /api/v1/users/` uses TenantScopedRepository.list_all(); CRUDRouter list does not add custom query params without a `filter_schema`
   - What's unclear: Whether the CRUDRouter list supports `?role=` filtering
   - Recommendation: Add a `?role=contractor` query param to the users router list endpoint (a 2-line change using `selectinload` + a where clause), or filter client-side if contractor count is expected to be small

3. **Contractor name in job detail cross-link**
   - What we know: `JobResponse` includes `client_name` (added Phase 15) but does NOT include `contractor_name`
   - What's unclear: Whether to add `contractor_name` to `JobResponse` or fetch contractor name via a separate query
   - Recommendation: Add `contractor_name: str | None` to `JobResponse` following the same `sa_inspect` pattern used for `client_name` in Phase 15; this is an additive-only change

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Playwright (web E2E) + pytest (backend integration) |
| Config file | `web/playwright.config.ts` (baseURL http://localhost:3000, testDir ./tests) |
| Quick run command | `cd web && npx playwright test tests/phase-17-crm.spec.ts` |
| Full suite command | `cd web && npx playwright test` |
| Backend quick run | `cd backend && uv run python -m pytest tests/test_phase_17_e2e.py -x` |
| Backend full suite | `cd backend && uv run python -m pytest` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CRM-01 | Admin sees paginated client list with search | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "client list"` | Wave 0 |
| CRM-01 | Search by name filters results | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "client search"` | Wave 0 |
| CRM-02 | Client detail shows job history | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "client detail"` | Wave 0 |
| CONTR-01 | Contractor list with availability badges | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "contractor list"` | Wave 0 |
| CONTR-02 | Contractor profile shows jobs and schedule | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "contractor profile"` | Wave 0 |
| CONTR-03 | Admin edits weekly working hours | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "schedule editor"` | Wave 0 |
| CONTR-04 | Admin sets date override | Playwright E2E | `npx playwright test tests/phase-17-crm.spec.ts -g "date override"` | Wave 0 |
| CRM-01 | Backend: GET /crm/clients returns paginated list | pytest integration | `cd backend && uv run python -m pytest tests/test_phase_17_e2e.py::test_list_clients -x` | Wave 0 |
| CRM-02 | Backend: GET /crm/clients/{id} returns profile + jobs | pytest integration | `cd backend && uv run python -m pytest tests/test_phase_17_e2e.py::test_client_detail -x` | Wave 0 |

### Sampling Rate

- **Per task commit:** `cd backend && uv run python -m pytest tests/test_phase_17_e2e.py -x` (backend only — fast, ~5 seconds)
- **Per wave merge:** `cd web && npx playwright test tests/phase-17-crm.spec.ts`
- **Phase gate:** Full suite (`npx playwright test` + `uv run python -m pytest`) green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `web/tests/phase-17-crm.spec.ts` — covers all 7 CRM/CONTR requirements (E2E)
- [ ] `backend/tests/test_phase_17_e2e.py` — covers CRM-01, CRM-02 backend endpoints

*(Existing test infrastructure: Playwright at `web/playwright.config.ts` with `testDir: "./tests"`, pytest with `conftest.py` at `backend/tests/`. Both frameworks are configured — no new framework setup needed.)*

---

## Sources

### Primary (HIGH confidence)

- `backend/app/features/jobs/crm_service.py` — CrmService API surface verified directly
- `backend/app/features/jobs/crm_repository.py` — CrmRepository eager-load patterns verified
- `backend/app/features/scheduling/router.py` — All scheduling endpoints and their path params verified
- `backend/app/features/scheduling/schemas.py` — WeeklyScheduleCreate, DateOverrideCreate, TimeBlock shapes verified
- `backend/app/features/jobs/models.py` — ClientProfile, ClientProperty model fields verified
- `backend/app/features/jobs/schemas.py` — ClientProfileResponse, JobResponse verified
- `backend/app/features/users/schemas.py` — UserResponse shape verified
- `backend/app/main.py` — Router registration pattern verified
- `web/src/app/(dashboard)/jobs/page.tsx` — List page pattern verified
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` — Two-column detail + cross-link pattern verified
- `web/src/components/shared/status-badge.tsx` — Existing colorMap verified for extension
- `web/src/lib/api-client.ts` — apiGet/apiPost/apiPut pattern verified
- `web/src/types/api.ts` — Existing type shapes verified
- `.planning/phases/17-crm-clients-and-contractors/17-CONTEXT.md` — All locked decisions

### Secondary (MEDIUM confidence)

- `web/playwright.config.ts` — Test infrastructure config verified
- `backend/tests/` directory listing — test_phase_16_e2e.py naming pattern verified

### Tertiary (LOW confidence)

- Availability badge thresholds (≥4 hours = available, etc.) — derived from UX reasoning, not from existing code; thresholds are within Claude's discretion

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed and in use across the project
- Architecture: HIGH — all patterns are direct replication of Phase 14/15/16 established code
- Backend API surface: HIGH — read directly from source files
- Schedule editor drag-to-paint: MEDIUM — well-known pointer-events pattern; no existing implementation to verify against in this codebase
- Availability badge thresholds: LOW — discretionary; no business rule defined

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable Next.js + FastAPI stack; no fast-moving dependencies introduced)
