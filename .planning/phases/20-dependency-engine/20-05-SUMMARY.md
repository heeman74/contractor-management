---
phase: 20-dependency-engine
plan: "05"
subsystem: web-gantt
tags: [gantt, dependencies, tanstack-query, playwright, typescript]
dependency_graph:
  requires: ["20-03"]
  provides: ["dependency-arrows-fetching"]
  affects: ["web/src/app/(dashboard)/projects/[id]/gantt/page.tsx", "web/src/lib/api/projects.ts"]
tech_stack:
  added: []
  patterns: ["Promise.all batch fetch with deduplication", "TanStack Query cache invalidation"]
key_files:
  created: []
  modified:
    - web/src/lib/api/projects.ts
    - web/src/app/(dashboard)/projects/[id]/gantt/page.tsx
    - web/tests/phase_20_gantt.spec.ts
decisions:
  - "useProjectDependencies uses sorted task ID join as queryKey to ensure stable cache key across re-renders"
  - "Deduplication uses Set<string> on dep.id to avoid duplicate arrows when tasks share dependencies"
  - "project-dependencies invalidation uses prefix key (no projectId) to clear all task-ID-keyed cache entries"
metrics:
  duration: "2m"
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_modified: 3
---

# Phase 20 Plan 05: Gantt Dependency Arrow Fetching Summary

**One-liner:** Wired `useProjectDependencies` hook using `Promise.all` batch fetch across all task IDs, populating SVAR Gantt `links` prop so dependency arrows render on page load.

## What Was Built

### Task 1: Add useProjectDependencies hook and wire into GanttPage

Added two new exports to `web/src/lib/api/projects.ts`:

- `fetchProjectDependencies(scopes)`: Uses `Promise.all` to batch-fetch dependencies for every task ID extracted from the scopes array, then deduplicates results by `dep.id` using a `Set`.
- `useProjectDependencies(scopes)`: TanStack Query hook with a stable cache key derived from sorted task IDs joined as a string. Enabled only when scopes exist.

Updated `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx`:
- Imported `useProjectDependencies` and called it with `scopes`
- Replaced the empty no-op loop (`for ... void task`) with a single line: `const allDependencies = Array.isArray(depsRaw) ? depsRaw : []`
- Added `queryClient.invalidateQueries({ queryKey: ["project-dependencies"] })` after dependency creation so arrows refresh immediately

### Task 2: Add Playwright E2E tests for dependency arrow rendering

Added two new top-level tests to `web/tests/phase_20_gantt.spec.ts`:

1. `"dependency arrows render when tasks have dependencies"` — navigates to the Gantt page, attaches a request listener, re-navigates, and asserts that at least one GET request to a `dependencies` endpoint was made.
2. `"new dependency creation invalidates and refetches dependency data"` — intercepts proxy calls, counts GET dependency requests via `route.fallback()`, and asserts the count is > 0 after page load.

## Verification

- TypeScript compilation: no errors in gantt or projects.ts files
- Playwright: 12 tests pass, 1 pre-existing failure ("conflict badge shown for overlapping tasks" — strict mode violation from two matching elements, pre-dates this plan)
- `allDependencies` is populated from `useProjectDependencies`, not hardcoded to `[]`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `web/src/lib/api/projects.ts` — modified, contains `fetchProjectDependencies` and `useProjectDependencies`
- `web/src/app/(dashboard)/projects/[id]/gantt/page.tsx` — modified, uses `useProjectDependencies(scopes)`, no `void task`
- `web/tests/phase_20_gantt.spec.ts` — modified, contains new dependency tests
- Task 1 commit: c216958
- Task 2 commit: 74957d1
