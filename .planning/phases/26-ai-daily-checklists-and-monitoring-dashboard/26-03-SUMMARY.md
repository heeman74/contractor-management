---
phase: 26-ai-daily-checklists-and-monitoring-dashboard
plan: "03"
subsystem: web-monitoring-dashboard
tags: [monitoring, dashboard, gantt, alerts, tanstack-query, typescript]
dependency_graph:
  requires: [26-01]
  provides: [DASH-01, DASH-02, DASH-03, DASH-04]
  affects: [web-sidebar-nav]
tech_stack:
  added: []
  patterns:
    - TanStack Query with polling (60s projects, 30s alerts)
    - SVAR Gantt loaded via next/dynamic ssr:false (SSR avoidance)
    - IntersectionObserver for auto-mark-read on alert scroll-into-view
    - Two-column monitoring layout (project grid + alert panel)
key_files:
  created:
    - web/src/lib/types/dashboard.ts
    - web/src/lib/hooks/useDashboard.ts
    - web/src/app/(dashboard)/monitoring/page.tsx
    - web/src/app/(dashboard)/monitoring/_components/ProjectStatusCard.tsx
    - web/src/app/(dashboard)/monitoring/_components/TradeStatusBadge.tsx
    - web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx
    - web/src/app/(dashboard)/monitoring/_components/TradeTimeline.tsx
    - web/src/app/(dashboard)/monitoring/_components/TradeTaskList.tsx
  modified:
    - web/src/components/layout/sidebar.tsx
decisions:
  - ILink type cast uses "e2s" string (not numeric 0) to satisfy SVAR ILink['type'] TLinkType constraint
  - IntersectionObserver (threshold 0.5) used for auto-mark-read — avoids click-handler mismatch
  - ILink.id uses array index string ("link-{idx}") since TradeTimelineDep has no id field
metrics:
  duration: 263s
  tasks_completed: 2
  files_created: 8
  files_modified: 1
  completed_date: "2026-03-26"
---

# Phase 26 Plan 03: Monitoring Dashboard — Web Components Summary

GC cross-trade monitoring dashboard with project status cards, SVAR Gantt trade timeline, AI alert panel with accept/dismiss rescheduling, and inline task drill-down — all in a new /monitoring route on the Next.js web app.

## What Was Built

### Task 1: TypeScript Types, TanStack Query Hooks, and Page Skeleton
- **`web/src/lib/types/dashboard.ts`**: Complete TypeScript interfaces matching all backend response schemas — `ProjectStatusCard`, `TradeStatusBadge`, `TradeTaskDetail`, `DashboardAlert`, `ReschedulingSuggestion`, `TradeTimelineData`, `TradeTimelineScope`, `TradeTimelineDep`.
- **`web/src/lib/hooks/useDashboard.ts`**: 7 TanStack Query hooks: `useDashboardProjects` (60s polling), `useDashboardAlerts` (30s polling, optional project filter), `useTradeTimeline` (enabled guard), `useTradeTasks` (dual-enabled guard), `useMarkAlertRead`, `useAcceptRescheduling`, `useDismissAlert`. Accept and dismiss mutations invalidate both `['dashboard-alerts']` and `['dashboard-projects']` on success for consistent state.
- **`web/src/app/(dashboard)/monitoring/page.tsx`**: "use client" page with two-column responsive layout (2/3 project grid + 1/3 alert panel on xl), selected project state drives trade timeline expansion below grid. Loading skeleton, error retry, and empty state handled.
- **`web/src/components/layout/sidebar.tsx`**: Added `Activity` icon from lucide-react and `Monitoring` nav item linking to `/monitoring`, placed second after Dashboard.

### Task 2: Five Monitoring Components
- **`ProjectStatusCard.tsx`**: Clickable card (shadcn-styled div) with project name, status badge, overall completion progress bar, per-trade `TradeStatusBadge` list, and alert count badge (AlertTriangle + red text). Ring highlight on selection via `isSelected` prop.
- **`TradeStatusBadge.tsx`**: Inline row — trade name (truncated), mini indigo progress bar, completion pct, status pill (green/amber/red for on_track/at_risk/blocked), and "{completed}/{total} tasks" count.
- **`AlertPanel.tsx`**: Scrollable panel (max-h 600px) with severity icons (Info=blue, AlertTriangle=amber, AlertOctagon=red), impact text, optional remediation italic block, days-behind counter. Rescheduling alerts show "Accept Rescheduling" (primary) and "Dismiss" (outline) buttons. `IntersectionObserver` auto-marks-read at 50% visibility. Empty state shows green CheckCircle2 "No alerts — all projects on track".
- **`TradeTimeline.tsx`**: SVAR Gantt loaded via `dynamic(() => import("@svar-ui/react-gantt").then(mod => mod.Gantt), { ssr: false })`. Maps `TradeTimelineScope` to `ITask[]` and `TradeTimelineDep` to `ILink[]` with `"e2s"` type cast. `onTaskClick` toggles `expandedTradeId` state. `readonly={true}` disables drag interactions. Renders `TradeTaskList` inline when a trade is expanded.
- **`TradeTaskList.tsx`**: Collapsible table (X close button) with columns: Title, Status (colored badge), Assignee, Start Date, Due Date, Dependencies. Past-due dates (non-complete tasks past due_date) highlighted in red. Loading skeleton, error, and empty states.

## Verification Results

- TypeScript (`npx tsc --noEmit`): No errors in new monitoring files. Pre-existing errors in `create-contractor-dialog.tsx` and `create-job-dialog.tsx` are unrelated to this plan.
- Build: Blocked by pre-existing TS errors in contractor/jobs dialogs (not introduced by this plan). See Deferred Issues.
- All acceptance criteria checks pass (9/9 grep assertions).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed ILink type cast for SVAR Gantt**
- **Found during:** Task 2 verification
- **Issue:** Initial implementation used `0 as ILink["type"]` (numeric literal). TypeScript rejected this as "Conversion of type 'number' to type 'TLinkType'" with no overlap.
- **Fix:** Changed to `"e2s" as ILink["type"]` (string type matching SVAR's string union), consistent with how `GanttView.tsx` handles link types.
- **Files modified:** `web/src/app/(dashboard)/monitoring/_components/TradeTimeline.tsx`
- **Commit:** 5ed39aa

## Deferred Issues

**1. Pre-existing build failure in contractor/jobs dialogs**
- `create-contractor-dialog.tsx:208` — `Dispatch<SetStateAction<string>>` not assignable to `(value: string | null) => void`
- `create-job-dialog.tsx:172,195,218,243` — Same null assignability issue
- These existed before this plan and are out of scope. Logged for follow-up.

## Commits

| Hash | Message |
|------|---------|
| 521a41b | feat(26-03): add dashboard types, TanStack Query hooks, monitoring page skeleton, and sidebar nav link |
| 5ed39aa | feat(26-03): implement monitoring dashboard components (ProjectStatusCard, AlertPanel, TradeTimeline, TradeTaskList) |

## Self-Check: PASSED
