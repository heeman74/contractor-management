---
phase: 19-project-data-model
plan: 05
subsystem: web
tags: [web, react, nextjs, projects, tanstack-query, playwright, e2e]
dependency_graph:
  requires: [19-03]
  provides: [PROJ-03-web]
  affects: [web-navigation, web-projects-ui]
tech_stack:
  added: []
  patterns:
    - TanStack Query hooks wrapping apiGet/apiPost/apiPatch
    - Collapsible file-explorer tree with lazy-loaded children
    - Two-panel layout (fixed sidebar + flex detail panel)
    - Base UI Dialog/Sheet with @base-ui/react
    - Playwright E2E tests with API mocking via /api/proxy intercepts
key_files:
  created:
    - web/src/types/projects.ts
    - web/src/lib/api/projects.ts
    - web/src/app/(dashboard)/projects/page.tsx
    - web/src/app/(dashboard)/projects/components/ProjectTree.tsx
    - web/src/app/(dashboard)/projects/components/ProjectDetail.tsx
    - web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx
    - web/src/app/(dashboard)/projects/components/TaskDetail.tsx
    - web/src/app/(dashboard)/projects/components/CreateProjectDialog.tsx
    - web/src/app/(dashboard)/projects/components/AddTradeScopeSheet.tsx
    - web/tests/phase-19-projects.spec.ts
  modified:
    - web/src/components/shared/status-badge.tsx
    - web/src/components/layout/sidebar.tsx
decisions:
  - "AddTradeScopeSheet and CreateProjectDialog created in Task 2 (not Task 3) to satisfy ProjectDetail import dependency"
  - "Playwright tests use getByRole/getByTestId with first() to avoid strict mode violations from multiple matching elements"
  - "useTradeScopes and useTasks queries only enabled when parent node is expanded (lazy loading)"
  - "Popover (Base UI) used for trade name combobox instead of cmdk (not installed)"
metrics:
  duration: 25min
  completed_date: "2026-03-20"
  tasks_completed: 3
  files_created: 10
  files_modified: 2
  tests_added: 18
---

# Phase 19 Plan 05: Web Project Hierarchy UI Summary

Web UI for project hierarchy: sidebar navigation link, collapsible tree with file-explorer pattern, detail panels for projects/scopes/tasks, create project dialog, add trade scope sheet with catalog combobox and save-to-catalog prompt. 18 Playwright E2E tests all passing.

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | TypeScript types, API client, TanStack hooks, sidebar link | a9bd160 | projects.ts, api/projects.ts, status-badge.tsx, sidebar.tsx |
| 2 | Project tree widget, detail panels, dialogs, page layout | f65c1f7 | page.tsx, ProjectTree.tsx, ProjectDetail.tsx, TradeScopeDetail.tsx, TaskDetail.tsx, CreateProjectDialog.tsx, AddTradeScopeSheet.tsx |
| 3 | Playwright E2E tests (18 tests, all passing) | 14bfbf4 | web/tests/phase-19-projects.spec.ts |

## What Was Built

**TypeScript types** (`web/src/types/projects.ts`): Complete interface set for `ProjectResponse`, `TradeScopeResponse`, `TaskResponse`, `TradeCatalogResponse`, `ContractorMatch`, plus create/input interfaces.

**API client** (`web/src/lib/api/projects.ts`): 12 API functions (`fetchProjects`, `fetchProject`, `createProject`, `updateProject`, `fetchTradeCatalog`, `createTradeCatalogEntry`, `fetchTradeScopes`, `createTradeScope`, `updateTradeScope`, `fetchTasks`, `createTask`, `fetchContractors`) and 6 TanStack Query hooks (`useProjects`, `useProject`, `useTradeCatalog`, `useTradeScopes`, `useTasks`, `useContractors`).

**Projects page** (`page.tsx`): Two-panel layout with 280px tree sidebar and flex detail panel. Auto-selects first project. Skeleton loading states.

**ProjectTree** (`ProjectTree.tsx`): Collapsible file-explorer tree with project (folder icon), scope (12px color dot), and task (circle-dot) nodes. Keyboard navigation with Enter/Space to select, ArrowRight/ArrowLeft to expand/collapse. Lazy-loads scopes and tasks on expand. ARIA `role="tree"` and `role="treeitem"` attributes.

**ProjectDetail** (`ProjectDetail.tsx`): Shows project name, status badge, address/dates metadata, trade scope summary cards with color swatches and status badges.

**TradeScopeDetail** (`TradeScopeDetail.tsx`): Shows trade name with 12px color swatch, progress bar (completed/total tasks), priority-bordered task list, status override button.

**TaskDetail** (`TaskDetail.tsx`): Shows title, priority badge, status badge, due date, estimated hours/cost, materials list (from JSONB array), photo_required indicator.

**CreateProjectDialog** (`CreateProjectDialog.tsx`): Form dialog with name (required), description, address, start/end date pickers (shadcn Calendar in Popover). Validates "Project name is required." and "End date must be after start date."

**AddTradeScopeSheet** (`AddTradeScopeSheet.tsx`): Right-side sheet with trade name combobox (Base UI Popover + search input), catalog entries with 12px color swatches, "Create new trade: {text}" option with Plus icon, save-to-catalog Alert prompt ("Save to Catalog" / "Use Once"), contractor select with specialty-match contractors first.

**StatusBadge updates**: Added `planning`, `on_hold`, `archived`, `not_started`, `blocked` colors.

**Sidebar update**: Added Projects link (`FolderKanban` icon, `/projects` href) after Jobs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Dependency] AddTradeScopeSheet and CreateProjectDialog created in Task 2**
- **Found during:** Task 2 implementation
- **Issue:** `ProjectDetail.tsx` directly imports `AddTradeScopeSheet` and the page imports `CreateProjectDialog`, so these had to exist before TypeScript could compile
- **Fix:** Created both components during Task 2 execution; no functional change to plan output
- **Files modified:** AddTradeScopeSheet.tsx, CreateProjectDialog.tsx (both listed in Task 3's files)
- **Commit:** f65c1f7

**2. [Rule 1 - Bug] Playwright strict mode violations in test assertions**
- **Found during:** Task 3 test execution
- **Issue:** `getByText('Kitchen Renovation')` matched 2 elements (tree node + detail heading); `getByText('Create Project')` matched heading + button
- **Fix:** Used `first()`, `getByRole('heading')`, `getByRole('tree').getByText()` for precise targeting
- **Commit:** 14bfbf4

**3. [Rule 1 - Bug] Sheet overlay intercepting contractor combobox clicks**
- **Found during:** Task 3 test execution
- **Issue:** After opening AddTradeScopeSheet, clicking "Plumbing" in an open combobox failed because sheet overlay intercepted pointer events
- **Fix:** Changed test to type in trade-search-input then click the item in `[data-slot="popover-content"]`
- **Commit:** 14bfbf4

**Note:** Pre-existing TypeScript errors in `create-job-dialog.tsx` and `create-contractor-dialog.tsx` are out of scope (not caused by this plan's changes). Deferred per deviation rules.

## Self-Check

```
web/src/types/projects.ts — FOUND
web/src/lib/api/projects.ts — FOUND
web/src/app/(dashboard)/projects/page.tsx — FOUND
web/src/app/(dashboard)/projects/components/ProjectTree.tsx — FOUND
web/src/app/(dashboard)/projects/components/ProjectDetail.tsx — FOUND
web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx — FOUND
web/src/app/(dashboard)/projects/components/TaskDetail.tsx — FOUND
web/src/app/(dashboard)/projects/components/CreateProjectDialog.tsx — FOUND
web/src/app/(dashboard)/projects/components/AddTradeScopeSheet.tsx — FOUND
web/tests/phase-19-projects.spec.ts — FOUND
Commit a9bd160 — FOUND
Commit f65c1f7 — FOUND
Commit 14bfbf4 — FOUND
```
