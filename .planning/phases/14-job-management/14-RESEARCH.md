# Phase 14: Job Management - Research

**Researched:** 2026-03-16
**Domain:** Next.js App Router data tables, job lifecycle UI, TanStack Query, shadcn/ui
**Confidence:** HIGH

## Summary

Phase 14 builds three pages — jobs list, job detail, and job request review — on top of the fully operational Phase 13 web foundation. The backend job API is complete and well-documented; every endpoint needed (list, get, transition, notes, time-entries, requests, review) is already implemented and route-shadowing issues are pre-solved. The web layer has TanStack Query, Redux Toolkit, apiClient with 401-refresh, shadcn/ui primitives, and the StatusBadge component all ready to use.

The primary technical decisions left to the planner are: (1) whether to use shadcn/ui's raw `<table>` primitives with local sort/filter state or add TanStack Table for column management, (2) how to handle server-side pagination cursor vs offset in TanStack Query queryKeys, and (3) the lightbox implementation for photo notes. All three are Claude's discretion areas from CONTEXT.md.

The key implementation constraint is that `JobResponse` from the backend does NOT include related entity names (contractor name, client name) — only UUIDs (`contractor_id`, `client_id`). The detail page must either make additional API calls for those entities or the backend list endpoint must be augmented. This is the most significant pitfall to plan around.

**Primary recommendation:** Use shadcn/ui `<table>` primitives with TanStack Query for server-side data — avoid adding TanStack Table as a new dependency since the DataTable needs are straightforward. Fetch contractor/client names on the detail page via separate TanStack Query calls rather than embedding them in JobResponse.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Jobs list presentation:**
- Horizontal status tab bar: All | Quote | Scheduled | In Progress | Complete | Invoiced | Requests
- Each tab shows count badge (e.g., "In Progress (12)")
- Requests tab separated at the end for client-submitted job requests with pending count
- Compact columns: Job #, Title, Client, Status (StatusBadge), Assigned Contractor, Date
- Always-visible search bar, right-aligned next to tabs
- Click row navigates to detail page at /jobs/[id] (full page navigation, breadcrumb: Dashboard > Jobs > Job #1042)
- Server-side pagination with page controls at bottom (prev/next + page numbers)
- Sortable columns — click header to toggle asc/desc, arrow indicator, default sort: newest first by date
- No inline row actions — all status transitions happen on the detail page only

**Job detail layout:**
- Two-column layout: main content (~65%) + right sidebar (~35%)
- Main content order (top to bottom): Description → Notes → Activity/History
- Notes section: read + add new text notes from web; photo notes from mobile display as thumbnail grid with lightbox on click
- Right sidebar sections: Status badge, Contractor (linked to /contractors/[id]), Client (linked to /clients/[id]), Scheduled date/time, Address, Time tracking (total + expandable individual clock-in/out entries)
- Linked quote/invoice: summary card in sidebar if exists (e.g., "Quote #Q-1042 — $4,500 — Approved") with link to detail (Phase 16 pages — 404 until built)
- Navigation: breadcrumbs only (no explicit back button) — clicking "Jobs" in breadcrumb or sidebar navigates back

**Status transition UX:**
- Primary action button in sidebar under status badge showing next logical status (e.g., "Mark In Progress")
- Dropdown arrow reveals all valid transitions: forward (primary), revert (secondary), cancel (destructive/red)
- Forward transitions execute immediately with success toast: "Job #1042 marked In Progress"
- Destructive actions (revert, cancel) show confirmation dialog before executing
- Cancel Job requires a reason (text field in confirmation dialog, required) — saved as job note for audit trail
- Transition errors display as inline red alert banner below the status button, clears on next action
- After successful transition: stay on detail page, update status badge and action button in place

**Job request review flow:**
- Requests live as a tab on the jobs page (not a separate page or nav item)
- Click request row navigates to request detail page showing: client info, description, preferred dates, property, type
- Approve and Decline buttons at top of request detail
- Declining requires a reason (text field in confirmation dialog, required)
- After approve: navigate to the newly created job's detail page (in Quote status)
- After decline: navigate back to requests tab with success toast

### Claude's Discretion
- Exact DataTable component choice (shadcn/ui table vs TanStack Table)
- Pagination controls styling
- Skeleton loading shapes for list and detail pages
- Lightbox/modal implementation for photo notes
- Exact spacing, typography, and card styling within the two-column layout
- Search debounce timing
- Empty state illustrations/messages for zero-results and zero-requests

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| JOBS-01 | Admin can view all jobs in a filterable list with status tabs and search | Backend `GET /jobs/` with status/search params; TanStack Query with queryKey per status/page/search; shadcn/ui table primitives |
| JOBS-02 | Admin can view full job detail including notes, assigned contractor, client, and status | Backend `GET /jobs/{id}`, `GET /jobs/{id}/notes`, `GET /jobs/{id}/time-entries`; separate queries for contractor/client names |
| JOBS-03 | Admin can transition job status through the lifecycle (Quote→Scheduled→In Progress→Complete→Invoiced) | Backend `PATCH /jobs/{id}/transition` with `{new_status, reason, version}`; optimistic locking via `version` field; 409/422 error handling |
| JOBS-04 | Admin can review client-submitted job requests and approve or decline them | Backend `GET /jobs/requests`, `GET /jobs/requests/{id}`, `POST /jobs/requests/{id}/review`; approve returns `converted_job_id` for redirect |
</phase_requirements>

---

## Standard Stack

### Core (all already installed — zero new deps needed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Next.js App Router | project standard | Page routing, layouts, dynamic segments | Phase 13 decision — locked |
| TanStack Query | installed | Server state, caching, refetch | Phase 13 decision — locked |
| Redux Toolkit | installed | UI state only (tab selection, search, sort) | Phase 13 decision — locked |
| shadcn/ui primitives | installed | Table, Card, Button, Input, DropdownMenu, Dialog, Skeleton, Sonner | Already in web/src/components/ui/ |
| apiClient | web/src/lib/api-client.ts | All API calls with 401 refresh | Phase 13 built |
| StatusBadge | web/src/components/shared/status-badge.tsx | Job status display | Phase 13 built — covers all statuses |
| Tailwind CSS | project standard | Styling | Project standard |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lucide-react | installed | Icons (ArrowUpDown, ChevronDown, etc.) | Column sort arrows, action buttons |
| zod | installed | Form validation for note input, decline reason | Already installed — no new dep |
| react-hook-form | installed | Note creation form, transition dialogs | Already installed |
| sonner (toast) | installed | Success/error notifications | `toast.success()` and `toast.error({ duration: Infinity })` |

### NOT needed (Claude's discretion resolved)
- **TanStack Table**: Adds complexity for a straightforward table. Use shadcn/ui `<table>` with local sort state managed in Redux.
- **@radix-ui/react-dialog**: shadcn/ui `Dialog` component already wraps this — use shadcn directly.
- **yet-another-react-lightbox** or similar: Use a simple shadcn/ui `Dialog` with a full-size `<img>` for the photo lightbox — avoids a new dependency.

**Installation:** No new packages required. All dependencies are in place from Phase 13.

---

## Architecture Patterns

### Recommended Page Structure
```
web/src/app/(dashboard)/
├── jobs/
│   ├── page.tsx              # Jobs list page (Client Component — tabs, table, pagination)
│   └── [id]/
│       └── page.tsx          # Job detail page (Client Component — two-col layout)
web/src/app/(dashboard)/jobs/requests/
│   └── [requestId]/
│       └── page.tsx          # Request detail page (Client Component — approve/decline)
```

Note: All pages are Client Components (`"use client"`) per Phase 13 pattern. The dashboard layout (`(dashboard)/layout.tsx`) wraps everything in `DashboardShell` automatically.

### Pattern 1: Status Tab Navigation with TanStack Query

**What:** Tab clicks update URL search params (`?status=in_progress&page=1`). TanStack Query re-fetches when queryKey changes. Status counts fetched in a single parallel query via multiple `useQuery` calls.

**When to use:** Any tab/filter UI that drives data fetching.

```typescript
// Source: project pattern from (dashboard)/page.tsx
const { data, isLoading } = useQuery({
  queryKey: ["jobs", { status: activeTab, page, search }],
  queryFn: () => {
    const params = new URLSearchParams();
    if (status) params.set("status", status);
    params.set("offset", String((page - 1) * PAGE_SIZE));
    params.set("limit", String(PAGE_SIZE));
    if (search) params.set("q", search);  // use /jobs/search endpoint
    return apiGet<Job[]>(`/api/v1/jobs?${params}`);
  },
});
```

**Tab count pattern:** Fetch counts for each status in parallel using `useQueries` or individual `useQuery` calls per tab. The backend returns an array, so `data?.length` gives the count. For "Requests" tab, use `GET /jobs/requests` to get pending count.

### Pattern 2: Optimistic Locking for Status Transitions

**What:** The backend uses optimistic locking via a `version` field on `JobResponse`. The transition request MUST include the current `version` from the fetched job.

**Critical:** If version is stale (concurrent edit), backend returns `409 Conflict`. UI must handle this explicitly.

```typescript
// Source: backend/app/features/jobs/schemas.py JobTransitionRequest
interface TransitionRequest {
  new_status: JobStatus;
  reason?: string;
  version: number;  // REQUIRED — from the fetched JobResponse.version
}

// Usage in mutation
const transitionMutation = useMutation({
  mutationFn: (data: TransitionRequest) =>
    apiPatch<Job>(`/api/v1/jobs/${jobId}/transition`, data),
  onSuccess: (updatedJob) => {
    queryClient.setQueryData(["job", jobId], updatedJob);  // update cache in-place
    toast.success(`Job marked ${updatedJob.status.replace("_", " ")}`);
  },
  onError: (err: ApiError) => {
    if (err.status === 409) {
      // Version conflict — refetch and show inline error
      queryClient.invalidateQueries({ queryKey: ["job", jobId] });
    }
    // Show inline red alert banner (not toast) per CONTEXT.md
    setTransitionError(err.detail);
  },
});
```

### Pattern 3: Request Review — Approve Redirect

**What:** When admin approves a request, the backend creates a new Job and returns the updated `JobRequestResponse` with `converted_job_id` populated. The web must read `converted_job_id` from the response and redirect to `/jobs/{converted_job_id}`.

```typescript
// Source: backend/app/features/jobs/request_service.py review_request()
// The router calls svc.review_request(), then re-fetches the request to get converted_job_id
const reviewMutation = useMutation({
  mutationFn: (action: ReviewAction) =>
    apiPost<JobRequestResponse>(
      `/api/v1/jobs/requests/${requestId}/review`,
      action
    ),
  onSuccess: (result) => {
    if (result.converted_job_id) {
      // Approved — navigate to the new job
      router.push(`/jobs/${result.converted_job_id}`);
    } else {
      // Declined — navigate back to requests tab
      router.push("/jobs?tab=requests");
      toast.success("Request declined");
    }
  },
});
```

### Pattern 4: Breadcrumb Dynamic Segments

**What:** The `Topbar` `buildBreadcrumbs()` function already handles unknown path segments by title-casing them. A job detail page at `/jobs/some-uuid` will render "Dashboard > Jobs > Some-Uuid" — which is wrong.

**How to fix:** The job detail page component must override the breadcrumb with a custom segment label. The topbar reads path segments; for a UUID segment, we need to render the job's display identifier. Two options:

1. Use `SEGMENT_LABELS` in topbar.tsx — but UUIDs are dynamic, this won't work.
2. Use a "page title context" via Redux ui-slice: dispatch a `setPageTitle` action from the detail page, and have `buildBreadcrumbs` check the ui-slice for overrides.

The simplest approach: add a `pageTitle` field to the Redux `ui-slice`, dispatch `setPageTitle("Job #1042")` from the detail page on data load, and have `buildBreadcrumbs` use it for the last segment when present.

**Existing breadcrumb format:** `topbar.tsx` line 53 — `SEGMENT_LABELS[segment] ?? segment.replace(/-/g, " ").replace(/\b\w/g, ...)` — UUIDs will render as hyphen-separated uppercase gibberish unless overridden.

### Pattern 5: Server-Side Pagination with URL State

**What:** URL search params drive page number, status filter, and search query. This allows bookmarking and browser back/forward navigation.

```typescript
// useSearchParams + useRouter pattern
const searchParams = useSearchParams();
const router = useRouter();
const activeTab = searchParams.get("tab") ?? "all";
const page = Number(searchParams.get("page") ?? "1");
const search = searchParams.get("q") ?? "";

// Tab change
function handleTabChange(tab: string) {
  const params = new URLSearchParams(searchParams.toString());
  params.set("tab", tab);
  params.set("page", "1");  // reset to page 1 on tab change
  router.push(`/jobs?${params}`);
}
```

### Anti-Patterns to Avoid

- **Fetching related entity data in a loop:** The `JobResponse` has `contractor_id` and `client_id` (UUIDs only). Do NOT fetch contractor/client profiles in a loop for each row in the list — this creates N+1 requests. For the list page, display only IDs or accept that contractor/client names are not shown in the list (the columns say "Client" and "Assigned Contractor" — these fields are UUIDs in the response). See Critical Pitfall #1 below.
- **Calling `queryClient.invalidateQueries` after every mutation:** For status transitions, use `queryClient.setQueryData` with the returned updated job to avoid an extra round-trip.
- **Using `router.push` for tab changes without URL param update:** Always use `useSearchParams` + `router.push` so tabs are bookmarkable and back-navigation works.
- **Not including `version` in transition requests:** The backend will 422 if `version` is missing or 0. Always read `version` from the current TanStack Query cache for the job.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toast notifications | Custom toast component | `sonner` (already in ui/sonner.tsx) | Phase 13 decision; `toast.error()` with `{ duration: Infinity }` required per STATE.md |
| Modal/dialog for confirmation | Custom overlay | shadcn/ui `Dialog` | Accessible, keyboard-handled, already installed |
| Status color mapping | Manual className conditionals | `StatusBadge` component | Already maps all job statuses; reuse directly |
| API calls with auth | Raw `fetch` | `apiGet/apiPost/apiPatch` from api-client.ts | 401 auto-refresh wired; don't bypass |
| Dropdown for transitions | Custom dropdown | shadcn/ui `DropdownMenu` | Already installed, accessible |
| Skeleton loading | CSS shimmer | shadcn/ui `Skeleton` | Already installed |
| Search debounce | Custom hook | `useEffect` + `useRef` with `setTimeout` | Simple enough inline; don't add lodash |

**Key insight:** Zero new npm packages are needed. Every UI primitive for this phase is already installed in Phase 13. Adding TanStack Table for a 7-column sortable table would be over-engineering — shadcn/ui raw table with local sort state is sufficient.

---

## Common Pitfalls

### Pitfall 1: JobResponse Has Only UUIDs for Contractor/Client — No Names
**What goes wrong:** The list page spec says columns include "Client" and "Assigned Contractor". `JobResponse` only provides `client_id` and `contractor_id` (UUIDs). Rendering these as raw UUIDs is unacceptable. Fetching names per row is N+1.
**Why it happens:** The backend `list_jobs` endpoint returns `list[JobResponse]` — no joined user data.
**How to avoid:** Two valid approaches:
  1. **List page: display only job # + title + status + date** and omit client/contractor columns from the list (simplest, no extra fetches). Add client/contractor names only to the detail page where a single fetch is acceptable.
  2. **Better UX: batch fetch**: Collect all unique `client_id` and `contractor_id` values from the list response, then do `GET /clients/{id}` for each unique ID. Still N+1 but bounded to unique entities per page (max 50). Use `useQueries` for parallel execution.
  The recommended plan: show abbreviated client/contractor (just IDs or omit) in the list, full names only in the detail page.
**Warning signs:** If you see `await apiGet(\/api\/v1\/clients\/${row.client_id})` inside a `.map()`, you've hit this pitfall.

### Pitfall 2: Optimistic Locking Version Not Sent
**What goes wrong:** `PATCH /jobs/{id}/transition` returns 409 with "version mismatch" or 422 with Pydantic validation error for missing field.
**Why it happens:** `JobTransitionRequest` requires `version: int`. If the frontend sends `{}` without it, FastAPI 422s. If it sends an old version, the service 409s.
**How to avoid:** Always read `version` from the TanStack Query cache: `queryClient.getQueryData<Job>(["job", jobId])?.version`. Never hardcode `version: 0`.
**Warning signs:** 422 Unprocessable Entity on transition with "version" in the error body.

### Pitfall 3: Route Shadowing — `/jobs/requests` vs `/jobs/[id]`
**What goes wrong:** Next.js dynamic segment `[id]` could shadow `/jobs/requests/[requestId]` if the file system routing is set up incorrectly.
**Why it happens:** `app/(dashboard)/jobs/[id]/page.tsx` would match `/jobs/requests` with `id="requests"`.
**How to avoid:** Create the requests detail page at `app/(dashboard)/jobs/requests/[requestId]/page.tsx` — the `requests` subfolder is a static segment, so Next.js routes it before the dynamic `[id]` catch-all.
**Warning signs:** Navigating to `/jobs/requests/some-uuid` loads the job detail page instead of the request detail page.

### Pitfall 4: Approve Review — Must Extract `converted_job_id` from Response
**What goes wrong:** After calling `POST /jobs/requests/{id}/review` with `action: "accepted"`, the router:
  1. Calls `svc.review_request()` which returns a `Job` object
  2. Then re-fetches the updated request via `svc.get_request(request_id)` and returns `JobRequestResponse`

  The `converted_job_id` field in the response IS populated on the request. The frontend must read `result.converted_job_id` to get the new job's ID for redirect.
**Why it happens:** The router wraps the service result and always returns `JobRequestResponse` — not the raw `Job`. The job ID is in `converted_job_id`, not a `job` sub-object.
**How to avoid:** `if (result.converted_job_id) { router.push(\`/jobs/${result.converted_job_id}\`) }`
**Warning signs:** Approving a request but landing on the wrong page or getting a redirect error.

### Pitfall 5: Cancel Job Requires a Reason Saved as Note
**What goes wrong:** The "Cancel Job" action in the transition dropdown requires a text reason (mandatory). This reason must be submitted as the `reason` field in `JobTransitionRequest` AND saved as a job note for audit trail per CONTEXT.md.
**Why it happens:** The backend `transition_status()` records reason in `status_history` JSONB, but does NOT auto-create a `JobNote`. Per CONTEXT.md: "Cancel Job requires a reason (text field in confirmation dialog, required) — saved as job note for audit trail".
**How to avoid:** After a successful cancel transition, fire a second mutation: `POST /jobs/{id}/notes` with the cancel reason as the note body.
**Warning signs:** Cancel succeeds but no note appears in the Notes section.

### Pitfall 6: `GET /jobs/search` vs `GET /jobs/` — Different Endpoints for Search
**What goes wrong:** The search bar and the status tab both need to work together. When a search query is present, use `GET /jobs/search?q=...&status=...`. When no query, use `GET /jobs/?status=...`.
**Why it happens:** The backend has two separate endpoints with slightly different signatures: `/jobs/` (no `q`) and `/jobs/search` (requires `q`).
**How to avoid:** In the TanStack Query `queryFn`, branch on whether `search` is non-empty:
  - Empty search: `GET /api/v1/jobs?status=...&offset=...&limit=...`
  - Non-empty search: `GET /api/v1/jobs/search?q=...&status=...` (note: no pagination params on search endpoint)
**Warning signs:** 422 Unprocessable Entity when search bar is used (missing `q` on the search endpoint, or unexpected `q` on the list endpoint).

### Pitfall 7: StatusBadge Missing "quote" and "invoiced" Color Entries
**What goes wrong:** `StatusBadge` colorMap in `status-badge.tsx` does not have entries for `quote` or `invoiced` (two of the six job statuses). They will render with the default gray fallback.
**Why it happens:** The existing colorMap was seeded for generic statuses — `quote` and `invoiced` are job-specific.
**How to avoid:** Add `quote` and `invoiced` to `colorMap` in `status-badge.tsx`:
  - `quote`: indigo/purple (draft-like) — `"bg-indigo-100 text-indigo-800"`
  - `invoiced`: teal/green (final positive) — `"bg-teal-100 text-teal-800"`
**Warning signs:** Quote and Invoiced status badges appear plain gray.

---

## Code Examples

### Verified: Backend Transition Endpoint Signature
```typescript
// Source: backend/app/features/jobs/schemas.py
interface JobTransitionRequest {
  new_status: "quote" | "scheduled" | "in_progress" | "complete" | "invoiced" | "cancelled";
  reason?: string;   // required for cancel, optional otherwise
  version: number;   // optimistic locking — REQUIRED
}
// PATCH /api/v1/jobs/{id}/transition
// Errors: 422 InvalidTransition, 409 VersionMismatch, 409 SchedulingConflict
```

### Verified: Request Review Endpoint Signature
```typescript
// Source: backend/app/features/jobs/router.py review_job_request_early()
// Source: backend/app/features/jobs/schemas.py JobRequestReviewAction
interface ReviewAction {
  action: "accepted" | "declined" | "info_requested";
  decline_reason?: string;
  decline_message?: string;
}
// POST /api/v1/jobs/requests/{request_id}/review
// Returns: JobRequestResponse with converted_job_id populated on accept
```

### Verified: Notes Endpoint
```typescript
// Source: backend/app/features/jobs/router.py create_note(), list_notes()
// GET  /api/v1/jobs/{id}/notes  → JobNoteResponse[]
// POST /api/v1/jobs/{id}/notes  → JobNoteResponse (201)
interface JobNoteCreate {
  body: string;  // max 2000 chars
}
interface JobNoteResponse {
  id: string;
  job_id: string;
  author_id: string;
  body: string;
  attachments: AttachmentResponse[];  // photo thumbnails come here
  created_at: string;
}
```

### Verified: Full JobResponse Shape
```typescript
// Source: backend/app/features/jobs/schemas.py JobResponse
interface Job {
  id: string;
  company_id: string;
  description: string;
  trade_type: string;
  status: "quote" | "scheduled" | "in_progress" | "complete" | "invoiced" | "cancelled";
  status_history: StatusHistoryEntry[];
  priority: "low" | "medium" | "high" | "urgent";
  client_id: string | null;
  contractor_id: string | null;
  purchase_order_number: string | null;
  external_reference: string | null;
  tags: string[];
  notes: string | null;
  estimated_duration_minutes: number | null;
  scheduled_completion_date: string | null;  // date string
  gps_latitude: string | null;
  gps_longitude: string | null;
  gps_address: string | null;
  version: number;   // for optimistic locking — CRITICAL
  created_at: string;
  updated_at: string;
}
// NOTE: No contractor name, no client name — only UUIDs
```

### Verified: Tab Count Query Pattern
```typescript
// Source: (dashboard)/page.tsx existing pattern
// Fetch per-status counts using individual useQuery calls (parallel by default)
const quotesCount = useQuery({
  queryKey: ["jobs", "count", "quote"],
  queryFn: () => apiGet<Job[]>("/api/v1/jobs?status=quote&limit=200"),
  select: (data) => data.length,
});
const requestsCount = useQuery({
  queryKey: ["job-requests", "count"],
  queryFn: () => apiGet<JobRequestResponse[]>("/api/v1/jobs/requests?limit=200"),
  select: (data) => data.length,
});
```

### Verified: Job List Endpoint Params
```typescript
// Source: backend/app/features/jobs/router.py list_jobs()
// GET /api/v1/jobs?status=...&contractor_id=...&client_id=...
//   &trade_type=...&priority=...&offset=0&limit=50
// Returns: Job[]  (NOT paginated envelope — plain array)
// NOTE: No total count returned — pagination must be inferred from returned length vs limit
```

### Verified: Breadcrumb Override — Redux UI Slice Pattern
```typescript
// Source: web/src/store/slices/ui-slice.ts (to be extended)
// Add to ui-slice: pageTitle field
// Dispatch from detail page:
useEffect(() => {
  if (job) {
    dispatch(setPageTitle(`Job #${job.id.slice(0, 8).toUpperCase()}`));
  }
  return () => dispatch(setPageTitle(null));  // cleanup on unmount
}, [job, dispatch]);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Server Components with db access | Client Components + TanStack Query | Phase 13 decision | All pages are "use client" — no server-side data in RSC |
| Token in localStorage | httpOnly cookie via proxy | Phase 13 | apiClient routes through `/api/proxy` — no direct API calls |
| module-level Redux store | makeStore factory pattern | Phase 13 | Provider is wrapped in store.tsx — use `useAppSelector/useAppDispatch` |
| Custom error handling | ApiError class + toast.error({ duration: Infinity }) | Phase 13 | Error toasts must be persistent — use `duration: Infinity` |

**Deprecated/outdated:**
- `JobResponse.title` — The current `JobResponse` schema has NO `title` field. The dashboard `page.tsx` references `job.title` which will be undefined. Phase 14 should use `job.description` (or a truncated version) as the display label. The `Job` interface in `types/api.ts` must be updated to match the real schema.

---

## Open Questions

1. **JobResponse has no title field but `types/api.ts` references `job.title`**
   - What we know: `JobResponse` uses `description` (not `title`). The stub `Job` interface in `types/api.ts` has `title: string` which is wrong.
   - What's unclear: Was a `title` field planned but not implemented? Or is `description` the display label?
   - Recommendation: Treat `description` as the job's display label. Update `types/api.ts` in Wave 0 with the full `Job` interface matching `JobResponse`.

2. **No total count from `/jobs/` — how to implement proper pagination?**
   - What we know: `GET /jobs/` returns `list[JobResponse]` — a plain array, no `total` or `count` field.
   - What's unclear: Pagination prev/next requires knowing whether a "next" page exists.
   - Recommendation: Use "has more" heuristic — if `data.length === PAGE_SIZE`, show Next button; if less, hide it. Alternatively, use cursor-based UX where "next" is always shown until an empty page is returned. The simplest: if `data.length < limit`, disable Next.

3. **Photo attachment display — `remote_url` may be a local server path**
   - What we know: `AttachmentResponse.remote_url` stores the path. Photos from mobile were saved to `uploads/job_requests/{id}/` on the server.
   - What's unclear: Is there a static file serving route for these uploads? Can the web frontend access them?
   - Recommendation: Check if FastAPI has a static files mount for `/uploads/`. If not, the lightbox will show broken images. Plan for a graceful "photo unavailable" fallback.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Playwright 1.x (`@playwright/test`) |
| Config file | `web/playwright.config.ts` |
| Quick run command | `npm run test-e2e:chromium -- --grep "JOBS"` (from `web/`) |
| Full suite command | `npm run test-e2e` (from `web/`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JOBS-01 | Jobs list renders with status tab bar | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ Wave 0 |
| JOBS-01 | Status tab click filters list by status | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ Wave 0 |
| JOBS-01 | Search bar filters jobs | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ Wave 0 |
| JOBS-01 | Pagination next/prev navigates pages | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ Wave 0 |
| JOBS-02 | Job row click navigates to /jobs/[id] | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ Wave 0 |
| JOBS-02 | Detail page shows description, notes, status | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ Wave 0 |
| JOBS-02 | Time tracking section shows total + entries | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ Wave 0 |
| JOBS-03 | Status transition button fires PATCH and updates badge | E2E | `npm run test-e2e:chromium -- --grep "JOBS-03"` | ❌ Wave 0 |
| JOBS-03 | Cancel transition shows confirmation dialog with required reason | E2E | `npm run test-e2e:chromium -- --grep "JOBS-03"` | ❌ Wave 0 |
| JOBS-04 | Requests tab shows pending request list | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ Wave 0 |
| JOBS-04 | Approve request redirects to new job detail | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ Wave 0 |
| JOBS-04 | Decline request shows reason dialog and toast | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `npm run test-e2e:chromium -- --grep "JOBS-0[1-4]" --headed` (skip slow photo tests)
- **Per wave merge:** `npm run test-e2e` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `web/tests/jobs.spec.ts` — covers JOBS-01 through JOBS-04 (all 12 test stubs)
- [ ] `web/src/types/api.ts` — update `Job` interface to match real `JobResponse` schema (remove `title`, add all fields from `JobResponse`)

---

## Sources

### Primary (HIGH confidence)
- `backend/app/features/jobs/router.py` — All endpoint signatures, error codes, route ordering, optimistic locking behavior
- `backend/app/features/jobs/schemas.py` — Complete request/response shapes, status enums, transition schema
- `backend/app/features/jobs/request_service.py` — Review logic, `converted_job_id` behavior on approve
- `web/src/lib/api-client.ts` — apiClient patterns, 401 handling
- `web/src/components/shared/status-badge.tsx` — StatusBadge colorMap, existing status coverage
- `web/src/components/layout/topbar.tsx` — Breadcrumb implementation, `buildBreadcrumbs()` function
- `web/src/app/(dashboard)/page.tsx` — TanStack Query patterns in use, toast patterns, extractCount helper
- `web/package.json` — Exact dependencies installed (no new deps needed)
- `.planning/phases/14-job-management/14-CONTEXT.md` — All locked decisions

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — Phase 13 decisions (error toast duration, Redux pattern)
- `web/tests/auth.spec.ts` — Playwright test structure to replicate for JOBS tests

### Tertiary (LOW confidence)
- None flagged.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified from package.json and installed components
- Backend API contracts: HIGH — read directly from source files
- Architecture patterns: HIGH — derived from existing Phase 13 code
- Pitfalls: HIGH — derived from actual schema inspection (missing `title` field, UUID-only responses)
- Test infrastructure: HIGH — playwright.config.ts and existing specs inspected

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (stable stack; backend API is additive-only per STATE.md)
