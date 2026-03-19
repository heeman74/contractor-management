---
phase: 17-crm-clients-and-contractors
plan: "03"
subsystem: web-crm
tags: [web, nextjs, crm, contractors, scheduling, availability]
dependency_graph:
  requires: ["17-01"]
  provides: ["CONTR-01", "CONTR-02"]
  affects: ["web/src/app/(dashboard)/contractors"]
tech_stack:
  added: []
  patterns:
    - "Batch POST availability fetch (single request, not N+1) via useQuery"
    - "Client-side role filter from /api/v1/users/ response"
    - "use(params) for async params in Next.js App Router dynamic segments"
    - "Derived trade type from most-frequent job.trade_type in assigned jobs"
key_files:
  created:
    - web/src/app/(dashboard)/contractors/page.tsx
    - "web/src/app/(dashboard)/contractors/[id]/page.tsx"
  modified: []
decisions:
  - "Batch availability fetched for paged contractors only (not all contractors) to limit POST body size"
  - "Active Jobs count on list page shows '—' to avoid N+1; actual count shown on profile page"
  - "KpiCard component requires href prop — used inline stat cards instead for Quick Stats section"
  - "WeeklyBlock day_of_week is 0-indexed from Monday per backend convention"
metrics:
  duration_seconds: 136
  completed_date: "2026-03-19"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 17 Plan 03: Contractor Pages Summary

**One-liner:** Contractor list with batch availability badges and contractor profile with schedule mini-grid, assigned jobs table, and sidebar stats — no N+1 requests.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Contractor list page with batch availability | b5171a4 | web/src/app/(dashboard)/contractors/page.tsx |
| 2 | Contractor profile page with schedule summary and jobs | e4f69e1 | web/src/app/(dashboard)/contractors/[id]/page.tsx |

## What Was Built

### Task 1: Contractor List Page (`/contractors`)

- `"use client"` page with two TanStack Query queries:
  1. `GET /api/v1/users/` — all users, filtered client-side to `roles.includes("contractor")`
  2. `POST /api/v1/scheduling/availability` — single batch request with `{ contractor_ids, date }` for current page
- Debounced search (300ms) filtering by name and email
- Sortable Name column with `ArrowUp`/`ArrowDown` icons
- Table columns: Name, Email, Phone, Trade (default "Contractor" badge), Availability (StatusBadge), Active Jobs ("—")
- Client-side pagination with PAGE_SIZE=50
- Empty states: "No contractors yet" / "No contractors found" / loading skeleton (10 rows)
- Error toast with `duration: Infinity`

### Task 2: Contractor Profile Page (`/contractors/[id]`)

- `"use client"` page with three TanStack Query queries:
  1. `GET /api/v1/users/` — finds contractor by id
  2. `GET /api/v1/jobs/?contractor_id={id}` — assigned jobs
  3. `GET /api/v1/scheduling/schedules/{id}/weekly` — weekly schedule blocks
- Two-column layout: `grid-cols-1 lg:grid-cols-[1fr_360px] gap-8`
- Main column:
  - Weekly Schedule card — 7-column mini-grid (Mon–Sun), shows time ranges or "Off", "Edit Schedule" button → `/contractors/[id]/schedule`
  - Assigned Jobs card — table with Job #, Title, Status (StatusBadge), Client, Date; row click → `/jobs/[id]`
- Sidebar:
  - Contact card with `Avatar`/`AvatarFallback` (initials), name, email, phone
  - Trade badge — derives most frequent `trade_type` from assigned jobs; defaults to "Contractor"
  - Quick Stats — Active Jobs count (scheduled + in_progress), Hours This Week (sum of schedule block durations)
  - Average Rating — "No ratings yet" placeholder
- Loading skeleton (two-column layout), empty states for no schedule / no jobs

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

**Note on KpiCard:** The KpiCard component requires a mandatory `href` prop (links to another page). For the Quick Stats sidebar section, the stats are contextual to the current page and don't have a meaningful navigation target, so inline stat cards were used instead. This is a compositional decision, not a deviation.

## Self-Check: PASSED

- FOUND: web/src/app/(dashboard)/contractors/page.tsx
- FOUND: web/src/app/(dashboard)/contractors/[id]/page.tsx
- FOUND: b5171a4 (task 1 commit)
- FOUND: e4f69e1 (task 2 commit)
- TypeScript: `npx tsc --noEmit` exit code 0 after both tasks
