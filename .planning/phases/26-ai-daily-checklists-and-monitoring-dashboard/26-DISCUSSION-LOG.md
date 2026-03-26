# Phase 26: AI Daily Checklists and Monitoring Dashboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-03-26
**Phase:** 26-ai-daily-checklists-and-monitoring-dashboard
**Areas discussed:** Daily checklist generation, Morning push, Dashboard layout, AI alerts, Schedule adaptation
**Mode:** --auto (all decisions auto-selected with recommended defaults)

---

## Daily Checklist Generation

| Option | Description | Selected |
|--------|-------------|----------|
| Backend cron + Claude API | Scheduled job queries unblocked tasks, AI prioritizes | ✓ |
| Static rule-based ordering | No AI, just dependency order | |

**User's choice:** [auto] Backend cron + Claude API (recommended)

---

## Morning Push Delivery

| Option | Description | Selected |
|--------|-------------|----------|
| FCM push with checklist summary | Tap opens full checklist in mobile app | ✓ |
| In-app only (no push) | Contractor must open app to see | |

**User's choice:** [auto] FCM push (recommended — proactive)

---

## Dashboard Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Project cards + Gantt drill-down | Cards with status badges, click for timeline | ✓ |
| Table-based overview | Spreadsheet-style list | |

**User's choice:** [auto] Project cards + Gantt (recommended — visual)

---

## AI Alert Generation

| Option | Description | Selected |
|--------|-------------|----------|
| Scheduled analysis + stored alerts | Every 2 hours, AI analyzes delays and generates alerts | ✓ |
| Real-time event-driven | Alert on every task status change | |

**User's choice:** [auto] Scheduled analysis (recommended — batched, less noisy)

---

## Schedule Adaptation

| Option | Description | Selected |
|--------|-------------|----------|
| AI suggestions, GC approves | Rescheduling proposed, never auto-applied | ✓ |
| Auto-reschedule | AI applies new dates automatically | |

**User's choice:** [auto] GC approval required (recommended — safety)
