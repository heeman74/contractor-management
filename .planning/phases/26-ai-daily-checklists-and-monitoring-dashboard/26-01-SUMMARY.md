---
phase: 26-ai-daily-checklists-and-monitoring-dashboard
plan: "01"
subsystem: backend
tags: [ai, checklists, dashboard, apscheduler, fastapi, sqlalchemy, fcm]
dependency_graph:
  requires:
    - backend/app/features/projects/models.py (Project, TradeScope, Task, TaskDependency)
    - backend/app/features/notifications/service.py (FCM push infrastructure)
    - backend/app/features/ai/service.py (AsyncAnthropic pattern)
    - backend/app/core/base_models.py (TenantScopedModel)
    - backend/app/core/base_service.py (TenantScopedService)
    - backend/app/core/base_repository.py (TenantScopedRepository)
  provides:
    - backend/app/features/checklists/service.py (ChecklistService.generate_daily_checklists)
    - backend/app/features/dashboard/service.py (DashboardService.detect_schedule_slips)
    - backend/app/core/scheduler.py (APScheduler lifespan, two cron jobs)
    - backend/migrations/versions/0024_ai_checklists_and_alerts.py (daily_checklists + dashboard_alerts tables)
    - 9 REST endpoints (2 checklists GET, 7 dashboard GET/POST)
  affects:
    - backend/app/main.py (lifespan wired, two routers registered)
    - backend/app/features/notifications/service.py (send_checklist_notification added)
tech_stack:
  added:
    - apscheduler==3.10.4 (AsyncIOScheduler, CronTrigger)
  patterns:
    - Non-streaming Claude API (messages.create) for batch cron jobs
    - asyncio.sleep(0.5) rate limiting between Claude calls per contractor
    - asyncio.create_task FCM fire-and-forget pattern (same as send_task_rejection_notification)
    - PostgreSQL upsert via pg_insert ON CONFLICT DO UPDATE (idempotent checklist regen)
    - FORCE ROW LEVEL SECURITY on both new tables
    - FastAPI lifespan context manager for scheduler lifecycle
key_files:
  created:
    - backend/migrations/versions/0024_ai_checklists_and_alerts.py
    - backend/app/features/checklists/__init__.py
    - backend/app/features/checklists/models.py
    - backend/app/features/checklists/repository.py
    - backend/app/features/checklists/schemas.py
    - backend/app/features/checklists/prompts/__init__.py
    - backend/app/features/checklists/prompts/checklist_system.py
    - backend/app/features/checklists/service.py
    - backend/app/features/checklists/router.py
    - backend/app/features/dashboard/__init__.py
    - backend/app/features/dashboard/models.py
    - backend/app/features/dashboard/repository.py
    - backend/app/features/dashboard/schemas.py
    - backend/app/features/dashboard/prompts/__init__.py
    - backend/app/features/dashboard/prompts/alert_system.py
    - backend/app/features/dashboard/service.py
    - backend/app/features/dashboard/router.py
    - backend/app/core/scheduler.py
  modified:
    - backend/requirements.txt (apscheduler==3.10.4 added)
    - backend/app/features/notifications/service.py (send_checklist_notification method)
    - backend/app/main.py (lifespan, checklists_router, dashboard_router)
decisions:
  - "Non-streaming Claude API for cron batch jobs — streaming SSE is only for interactive chat"
  - "asyncio.sleep(0.5) between contractor/scope Claude calls — simple rate limiting without a queue"
  - "FORCE ROW LEVEL SECURITY on both new tables — prevents superuser bypass"
  - "Checklist upsert via PostgreSQL INSERT ON CONFLICT DO UPDATE — cron re-runs are idempotent"
  - "DashboardAlert.rescheduling_payload stores suggestions as JSONB — accept/dismiss reads from this"
  - "Timeline cross-scope deps derived from TaskDependency table + in-memory task->scope map"
  - "Sort order as downstream-scope heuristic for impact analysis — full graph traversal deferred"
metrics:
  duration_seconds: 550
  tasks_completed: 2
  files_created: 18
  files_modified: 3
  completed_date: "2026-03-26"
---

# Phase 26 Plan 01: Backend Foundation — AI Daily Checklists and Monitoring Dashboard

AI-powered backend for morning daily checklists via Claude API + APScheduler cron, schedule slip detection with AI alert generation, and 9 REST endpoints for mobile and web consumption.

## What Was Built

### Migration 0024 — Two New Tables

`daily_checklists` — stores AI-generated contractor task lists:
- UUID PK, company_id FK (RLS), contractor_id (soft FK), project_id FK, trade_scope_id (soft FK)
- checklist_date, checklist_json (JSONB), summary_text (for FCM), is_pushed flag
- UNIQUE constraint on (company_id, contractor_id, trade_scope_id, checklist_date) for idempotent upserts
- ENABLE + FORCE ROW LEVEL SECURITY

`dashboard_alerts` — stores schedule slip alerts with AI remediation:
- UUID PK, company_id FK (RLS), project_id FK, trade_scope_id (soft FK)
- severity (info/warning/critical), alert_type (schedule_slip/rescheduling_suggestion/dependency_risk)
- days_behind, impact_text, remediation_text, affected_scope_ids (JSONB), rescheduling_payload (JSONB)
- is_read, rescheduling_accepted (bool | null — pending/accepted/dismissed)
- ENABLE + FORCE ROW LEVEL SECURITY

### APScheduler Setup

`app/core/scheduler.py` — module-level `AsyncIOScheduler(timezone="UTC")` with `lifespan` context manager:
- `morning_checklists`: CronTrigger(hour=6, minute=0), misfire_grace_time=3600
- `alert_detection`: CronTrigger(hour="7-19", minute=0), misfire_grace_time=600
- Both jobs iterate all companies, each with their own DB session + tenant context
- Errors per company logged and skipped; execution continues

### ChecklistService

- `generate_daily_checklists(company_id, target_date)`: single N+1-safe query via `selectinload(Project.trade_scopes).selectinload(TradeScope.tasks)`, filters eligible tasks, calls Claude with CHECKLIST_SYSTEM_PROMPT, upserts via `pg_insert ON CONFLICT DO UPDATE`, fires FCM via `asyncio.create_task`
- `get_today_checklist(contractor_id, target_date)`: reads today's checklists for contractor
- `get_checklist_by_id(checklist_id)`: single record lookup

### DashboardService

- `get_project_status_cards(company_id)`: aggregates completion_pct and per-trade status badges (blocked/at_risk/on_track) for all active projects
- `get_trade_tasks(trade_scope_id)`: returns TradeTaskDetail list for drill-down
- `get_trade_timeline(project_id)`: Gantt-ready data with date ranges, progress, cross-scope dependency links
- `detect_schedule_slips(company_id, target_date)`: finds scopes > 1 day behind, calls Claude with ALERT_SYSTEM_PROMPT, stores DashboardAlert with severity + rescheduling_payload
- `accept_rescheduling(alert_id)`: applies task date changes from rescheduling_payload, marks accepted
- `dismiss_alert / mark_alert_read`: alert lifecycle management

### REST Endpoints (9 total)

Checklists:
- `GET /api/v1/checklists/today` — contractor's daily checklist list
- `GET /api/v1/checklists/{id}` — specific checklist by ID

Dashboard:
- `GET /api/v1/dashboard` — project status cards
- `GET /api/v1/dashboard/projects/{id}/timeline` — Gantt data
- `GET /api/v1/dashboard/projects/{id}/trades/{id}/tasks` — trade task drill-down
- `GET /api/v1/dashboard/alerts` — unread alerts (optional ?project_id filter)
- `POST /api/v1/dashboard/alerts/{id}/read` — mark read
- `POST /api/v1/dashboard/alerts/{id}/accept` — accept rescheduling
- `POST /api/v1/dashboard/alerts/{id}/dismiss` — dismiss

### NotificationService Addition

`send_checklist_notification(contractor_id, summary_text, checklist_id)` — follows exact fire-and-forget FCM pattern of `send_task_rejection_notification`. Sends FCM with type="daily_checklist" data payload and summary_text as notification body.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

All key files found on disk. Both task commits verified in git log:
- 408a46a: feat(26-01): migration 0024, models, repositories, schemas, and APScheduler setup
- 374ba35: feat(26-01): checklist/dashboard services, AI prompts, REST routers, and main.py wiring
