# Phase 26: AI Daily Checklists and Monitoring Dashboard - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Two capabilities: (1) AI-generated daily task checklists pushed to contractors each morning via FCM, and (2) a web-based GC monitoring dashboard showing project/trade status, AI alerts for schedule slippage, and drill-down to trade task lists.

</domain>

<decisions>
## Implementation Decisions

### Daily Checklist Generation (AI-04)
- **D-01:** Backend cron job (APScheduler or Celery Beat) runs at 6:00 AM local time — queries each contractor's unblocked tasks scheduled for today using the dependency engine, then calls Claude API to prioritize and annotate them (materials needed, photo requirements, estimated duration).
- **D-02:** AI prompt includes contractor's trade scope, today's tasks with dependency status, weather forecast (if available), and any GC notes. Output is a structured JSON checklist.
- **D-03:** Generated checklists are stored in a new `daily_checklists` table for audit trail and offline access on mobile.

### Morning Push Delivery (AI-04 continued)
- **D-04:** FCM push notification with checklist summary — "You have {N} tasks today: {top 3 titles}..." Tapping opens the full checklist in the mobile app.
- **D-05:** Push delivery uses existing `NotificationService.send_task_rejection_notification` fire-and-forget pattern. Failures logged but never block checklist generation.
- **D-06:** Contractor sees full daily checklist on a dedicated screen in the mobile app, accessible from the home/dashboard tab.

### Web Dashboard Layout (DASH-01, DASH-02, DASH-04)
- **D-07:** New top-level route `/dashboard` in the Next.js web app — shows all active projects as cards with per-trade status badges (on track / at risk / blocked).
- **D-08:** Each project card shows a mini progress bar per trade scope, overall completion percentage, and count of active alerts.
- **D-09:** Click a project card → project detail view with trade timeline (Gantt-style horizontal bars showing each trade's schedule, dependency arrows between trades, progress fill).
- **D-10:** Click a trade bar → drill-down to that trade's task list (inline expansion, not a separate page). Shows tasks with status, assignee, dates, and dependency indicators.

### AI Alert Generation (DASH-03, AI-05)
- **D-11:** Backend scheduled job (runs every 2 hours during work hours) compares actual task completion against planned schedule. When a trade falls behind by more than 1 day, generates an AI alert.
- **D-12:** AI alert includes: which trade is behind, by how much, which downstream trades are impacted (from dependency engine), and a suggested remediation (e.g., "Assign additional crew to electrical rough-in to recover 2 days").
- **D-13:** Alerts stored in `dashboard_alerts` table with severity (info/warning/critical), read status, and remediation text.

### AI Schedule Adaptation (AI-05)
- **D-14:** When a task is completed late or a dependency is delayed, the AI generates a rescheduling suggestion for all affected downstream tasks across all trades.
- **D-15:** Rescheduling suggestions are presented to the GC as an alert on the dashboard — GC can accept (auto-applies new dates) or dismiss. Not auto-applied.
- **D-16:** The dependency engine's `_recompute_blocked_status` is the source of truth for which tasks are affected. AI adds human-readable impact analysis on top.

### Claude's Discretion
- Cron/scheduler technology choice (APScheduler vs Celery Beat vs simple cron endpoint)
- AI prompt engineering for checklist generation and alert analysis
- Dashboard chart library for Gantt view (existing web stack patterns)
- Alert severity thresholds (exactly how many days late = warning vs critical)
- Weather API integration (optional enhancement vs skip for MVP)
- Mobile daily checklist screen layout details

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### AI Infrastructure (Phase 21)
- `backend/app/features/ai/service.py` — AI service with Claude API integration (SSE streaming, tool use)
- `backend/app/features/ai/prompts/intake_system.py` — System prompt patterns for AI conversations
- `backend/app/features/ai/router.py` — AI endpoint patterns

### Dependency Engine (Phase 20)
- `backend/app/features/projects/service.py` — DependencyService._recompute_blocked_status for cascade analysis
- `.planning/phases/20-dependency-engine/20-CONTEXT.md` — Dependency engine design decisions

### Notification Infrastructure
- `backend/app/features/notifications/service.py` — FCM fire-and-forget pattern, device token management
- `mobile/lib/core/notifications/fcm_service.dart` — Mobile FCM integration

### Web Dashboard (Phase 18)
- Web app existing dashboard patterns from Phase 18 reporting dashboard

### Requirements
- `.planning/REQUIREMENTS.md` §AI-04, AI-05, DASH-01 through DASH-04

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **AiService**: Claude API integration with SSE streaming and tool use. Extend for checklist generation and alert analysis.
- **NotificationService**: FCM push with fire-and-forget pattern. Reuse for morning checklist push.
- **DependencyService**: Cascade dependency analysis. Use for identifying downstream impact of delays.
- **ProjectService**: Task queries by scope, contractor, status. Use for daily checklist data gathering.
- **Web reporting dashboard**: Existing charts/tables patterns in Next.js web app.

### Established Patterns
- **AI prompts as Python modules**: `prompts/` directory with system prompt constants.
- **FCM fire-and-forget**: Notification failures never block primary operations.
- **Offline-first mobile**: Drift DAOs with sync queue for checklist data.
- **Web API consumption**: Next.js pages fetch from FastAPI backend.

### Integration Points
- **Backend scheduler**: New scheduled jobs for morning checklist + bi-hourly alert generation
- **Mobile home screen**: Add daily checklist entry point
- **Web app**: New `/dashboard` route with project cards, trade timeline, alert panel
- **Alembic migration**: New tables (daily_checklists, dashboard_alerts)
- **Drift schema v14**: New DailyChecklists table for offline checklist access

</code_context>

<specifics>
## Specific Ideas

- Morning push must be personalized per contractor — only THEIR unblocked tasks for today
- Dashboard is web-only (GC uses desktop for monitoring) — not mobile
- AI alerts should explain impact in plain English, not just flag the delay
- Rescheduling suggestions require GC approval — never auto-applied
- Dependency engine is the source of truth for cascade impact

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 26-ai-daily-checklists-and-monitoring-dashboard*
*Context gathered: 2026-03-26 via --auto mode*
