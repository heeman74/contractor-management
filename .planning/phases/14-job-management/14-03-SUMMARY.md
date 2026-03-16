---
phase: 14-job-management
plan: "03"
subsystem: web
tags: [web, jobs, requests, admin, review]
dependency_graph:
  requires: [14-01]
  provides: [JOBS-04]
  affects: [web/src/app/(dashboard)/jobs/requests/]
tech_stack:
  added: []
  patterns:
    - TanStack Query useQuery + useMutation for request detail and review
    - Base UI Dialog with controlled open state for decline confirmation
    - Redux setPageTitle for breadcrumb override
key_files:
  created:
    - web/src/app/(dashboard)/jobs/requests/[requestId]/page.tsx
  modified: []
decisions:
  - Static `requests` segment before `[requestId]` prevents Next.js route shadowing with `/jobs/[id]`
  - Approve flow has no confirmation dialog per CONTEXT.md — positive actions fire immediately
  - Decline button disabled until reason is non-empty (client-side gate)
  - Error toasts use duration Infinity per Phase 13 decision
metrics:
  duration: "~1 min"
  completed: "2026-03-16"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
---

# Phase 14 Plan 03: Job Request Detail Page Summary

**One-liner:** Admin request detail page with approve-redirect and decline-with-reason dialog, wired to POST /api/v1/jobs/requests/{id}/review.

## What Was Built

A `"use client"` Next.js page at `/jobs/requests/[requestId]` that lets admins review inbound client job requests. The route uses a static `requests` folder segment to prevent Next.js dynamic route shadowing with the existing `/jobs/[id]` route.

The page fetches a single request via `useQuery` and renders a two-column layout: the main column shows the request description and a schedule/job-info card (job type, preferred date/time, property address); the sidebar shows the client's contact details and request metadata (status badge, submitted date).

An action bar sits above the grid with two buttons:

- **Approve Request** — fires `useMutation` with `{ action: "accepted" }`, then on success reads `result.converted_job_id` and redirects to `/jobs/{converted_job_id}`.
- **Decline** — opens a Base UI Dialog with a required reason textarea. The "Decline Request" confirm button is disabled until the textarea is non-empty. On confirm, fires `{ action: "declined", decline_reason }`, closes the dialog, and redirects to `/jobs?tab=requests` with a success toast.

Breadcrumb is overridden via Redux `setPageTitle` to display "Request from [Client Name]", cleared on unmount. All error paths emit persistent toasts (`duration: Infinity`). A full loading skeleton covers the action bar and both columns during the initial fetch.

## Tasks

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Job request detail page with approve and decline actions | a0e3449 | web/src/app/(dashboard)/jobs/requests/[requestId]/page.tsx |

## Acceptance Criteria Verification

- [x] File exists and starts with `"use client"`
- [x] Static `requests` segment before `[requestId]` in path
- [x] `useQuery` and `useMutation` imports
- [x] `apiGet` and `apiPost` imports
- [x] `JobRequestResponse` and `JobRequestReviewAction` type imports
- [x] `setPageTitle` dispatch for breadcrumb override
- [x] `queryKey: ["job-request",` for detail query
- [x] `/api/v1/jobs/requests/${requestId}` fetch URL
- [x] `/api/v1/jobs/requests/${requestId}/review` mutation URL
- [x] `action: "accepted"` for approve
- [x] `action: "declined"` for decline
- [x] `result.converted_job_id` check for approve redirect
- [x] `router.push(\`/jobs/${result.converted_job_id}\`)` approve redirect
- [x] `router.push("/jobs?tab=requests")` decline redirect
- [x] "Decline this request?" dialog title
- [x] "Decline reason (required)" label text
- [x] `declineReason` state variable
- [x] `disabled={!declineReason.trim()` on confirm button
- [x] "Keep Request" dismiss button
- [x] "Approve Request" button text
- [x] `toast.success("Request declined and client notified")`
- [x] `toast.error` with `duration: Infinity`
- [x] `npx tsc --noEmit` exits 0

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- File `/web/src/app/(dashboard)/jobs/requests/[requestId]/page.tsx`: FOUND
- Commit `a0e3449`: FOUND
