# Phase 26: AI Daily Checklists and Monitoring Dashboard - Research

**Researched:** 2026-03-26
**Domain:** AI scheduling (Claude API), backend cron jobs (APScheduler), FCM push notifications, Next.js Gantt/dashboard UI
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Daily Checklist Generation (AI-04)**
- D-01: Backend cron job runs at 6:00 AM local time — queries each contractor's unblocked tasks scheduled for today using the dependency engine, then calls Claude API to prioritize and annotate them (materials needed, photo requirements, estimated duration).
- D-02: AI prompt includes contractor's trade scope, today's tasks with dependency status, weather forecast (if available), and any GC notes. Output is a structured JSON checklist.
- D-03: Generated checklists are stored in a new `daily_checklists` table for audit trail and offline access on mobile.

**Morning Push Delivery (AI-04 continued)**
- D-04: FCM push notification with checklist summary — "You have {N} tasks today: {top 3 titles}..." Tapping opens the full checklist in the mobile app.
- D-05: Push delivery uses existing fire-and-forget pattern. Failures logged but never block checklist generation.
- D-06: Contractor sees full daily checklist on a dedicated screen in the mobile app, accessible from the home/dashboard tab.

**Web Dashboard Layout (DASH-01, DASH-02, DASH-04)**
- D-07: New top-level route `/dashboard` in the Next.js web app — shows all active projects as cards with per-trade status badges (on track / at risk / blocked).
- D-08: Each project card shows a mini progress bar per trade scope, overall completion percentage, and count of active alerts.
- D-09: Click a project card → project detail view with trade timeline (Gantt-style horizontal bars showing each trade's schedule, dependency arrows between trades, progress fill).
- D-10: Click a trade bar → drill-down to that trade's task list (inline expansion, not a separate page). Shows tasks with status, assignee, dates, and dependency indicators.

**AI Alert Generation (DASH-03, AI-05)**
- D-11: Backend scheduled job (runs every 2 hours during work hours) compares actual task completion against planned schedule. When a trade falls behind by more than 1 day, generates an AI alert.
- D-12: AI alert includes: which trade is behind, by how much, which downstream trades are impacted (from dependency engine), and a suggested remediation (e.g., "Assign additional crew to electrical rough-in to recover 2 days").
- D-13: Alerts stored in `dashboard_alerts` table with severity (info/warning/critical), read status, and remediation text.

**AI Schedule Adaptation (AI-05)**
- D-14: When a task is completed late or a dependency is delayed, the AI generates a rescheduling suggestion for all affected downstream tasks across all trades.
- D-15: Rescheduling suggestions are presented to the GC as an alert on the dashboard — GC can accept (auto-applies new dates) or dismiss. Not auto-applied.
- D-16: The dependency engine's `_recompute_blocked_status` is the source of truth for which tasks are affected. AI adds human-readable impact analysis on top.

### Claude's Discretion
- Cron/scheduler technology choice (APScheduler vs Celery Beat vs simple cron endpoint)
- AI prompt engineering for checklist generation and alert analysis
- Dashboard chart library for Gantt view (existing web stack patterns)
- Alert severity thresholds (exactly how many days late = warning vs critical)
- Weather API integration (optional enhancement vs skip for MVP)
- Mobile daily checklist screen layout details

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AI-04 | AI generates daily checklists per trade with tasks, materials needed, and photo requirements | Checklist generation via Claude API (structured JSON output), FCM delivery via existing NotificationService, daily_checklists table + Drift v14, DailyChecklistScreen on mobile |
| AI-05 | AI adapts schedules based on actual progress — flags delays and suggests rescheduling | Bi-hourly cron job compares due_date vs completion dates, DependencyService._recompute_blocked_status for cascade analysis, AI alert JSON with remediation, dashboard_alerts table, GC accept/dismiss UI |
| DASH-01 | GC can view all active projects with trade status summary on web dashboard | New /dashboard Next.js route under (dashboard) route group, project cards with per-trade status badges computed from Task status aggregation |
| DASH-02 | GC can see cross-trade timeline with dependency arrows and progress indicators | Reuse existing SVAR Gantt (@svar-ui/react-gantt 2.5.2) with trade-level grouping and progress fill, dependency arrows from task_dependencies table |
| DASH-03 | AI generates alerts when trades fall behind schedule or dependencies are at risk | Scheduled job with DependencyService cascade analysis, Claude API for remediation text, dashboard_alerts table with severity/read tracking |
| DASH-04 | GC can drill down from project overview to individual trade tasks | Inline expansion in dashboard card (not new page), task list with status/assignee/dates shown on click |
</phase_requirements>

---

## Summary

Phase 26 adds two top-level capabilities: AI-driven daily checklists delivered to contractors each morning via FCM, and a web-based monitoring dashboard for GCs showing project/trade status with AI-generated alerts when schedules slip.

The backend requires two new scheduled jobs (6 AM morning checklist generation, bi-hourly alert detection), two new database tables (`daily_checklists`, `dashboard_alerts`), and two new FastAPI routers. All AI logic extends the existing `AIService` with non-streaming calls — checklist and alert generation do not need SSE since they run in background jobs. The FCM delivery reuses `NotificationService.send_task_rejection_notification` fire-and-forget pattern exactly. The dependency engine's `DependencyService._recompute_blocked_status` is the authoritative cascade source for alert generation.

The mobile side adds a `DailyChecklistScreen`, a `DailyChecklistDao` (Drift schema v14), and a sync handler for offline checklist access. The web dashboard is a new `/dashboard` Next.js route inside the `(dashboard)` route group using the existing SVAR Gantt library (`@svar-ui/react-gantt` 2.5.2) already in `package.json`, plus Recharts for project card progress bars (also already installed).

**Primary recommendation:** Use `APScheduler` with `AsyncIOScheduler` (already compatible with FastAPI's async event loop) added as a startup/shutdown lifespan event. No Celery/Redis worker needed — jobs are fast enough (< 30 seconds per company) to run in-process.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| apscheduler | 3.10.x | In-process cron scheduler integrated with FastAPI lifespan | Already async-compatible, no separate worker needed, simpler than Celery for this load |
| anthropic | >=0.86.0 (already installed) | Claude API for checklist + alert text generation | Already installed and used in Phase 21 AIService |
| firebase-admin | 6.6.0 (already installed) | FCM push delivery | Already installed and used in NotificationService |
| sqlalchemy[asyncio] | 2.0.38 (already installed) | New table models for daily_checklists, dashboard_alerts | Matches existing ORM pattern |
| alembic | 1.14.1 (already installed) | Migration 0024 for new tables | Standard project migration tool |
| drift | 2.32.0 (already installed) | Drift schema v14: DailyChecklists table | Standard mobile data layer |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @svar-ui/react-gantt | 2.5.2 (already installed) | Trade timeline in dashboard | DASH-02 Gantt-style view — already proven in Phase 20 |
| recharts | 3.8.0 (already installed) | Mini progress bars per trade in project cards | DASH-01 progress indicators |
| @tanstack/react-query | 5.90.21 (already installed) | Dashboard data fetching + polling for alerts | Standard web data fetching pattern |
| lucide-react | 0.577.0 (already installed) | Alert/status icons in dashboard cards | Already used throughout web app |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| APScheduler in-process | Celery Beat + Redis worker | Celery adds operational complexity (separate worker process, Redis config). APScheduler in FastAPI lifespan is sufficient for 2 job types at current scale |
| APScheduler in-process | Cron endpoint + external cron | External cron (system cron / Cloud Scheduler) is viable but requires network hop + auth header — APScheduler is simpler for dev/test parity |
| SVAR Gantt (reuse) | Custom horizontal bar chart | Custom chart would duplicate Phase 20 work. SVAR is already integrated with known quirks (SSR: false, ILink type cast) |

**Installation (new package only):**
```bash
cd backend && uv pip install "apscheduler==3.10.4"
echo "apscheduler==3.10.4" >> requirements.txt
```

**Version verification:**
APScheduler 3.10.4 is the stable 3.x release as of March 2026. The 4.x branch is in alpha and changes the API significantly — stay on 3.x.

---

## Architecture Patterns

### Recommended Project Structure (new files only)

```
backend/app/features/
├── checklists/             # New feature: AI daily checklists
│   ├── __init__.py
│   ├── models.py           # DailyChecklist SQLAlchemy model
│   ├── repository.py       # ChecklistRepository (TenantScopedRepository)
│   ├── schemas.py          # Pydantic response schemas
│   ├── service.py          # ChecklistService: generate + store + push
│   ├── prompts/
│   │   └── checklist_system.py  # AI system prompt for checklist generation
│   └── router.py           # GET /checklists/today, GET /checklists/{id}
├── dashboard/              # New feature: GC monitoring dashboard
│   ├── __init__.py
│   ├── models.py           # DashboardAlert SQLAlchemy model
│   ├── repository.py       # AlertRepository (TenantScopedRepository)
│   ├── schemas.py          # Pydantic: ProjectStatusCard, TradeStatusBadge, AlertResponse
│   ├── service.py          # DashboardService: aggregate + alert + AI analysis
│   ├── prompts/
│   │   └── alert_system.py # AI system prompt for delay analysis
│   └── router.py           # GET /dashboard, GET /dashboard/alerts, POST /dashboard/alerts/{id}/read
backend/app/core/
└── scheduler.py            # APScheduler AsyncIOScheduler setup, job registration

migrations/versions/
└── 0024_ai_checklists_and_alerts.py

mobile/lib/
├── core/database/tables/
│   └── daily_checklists.dart       # Drift table definition
├── features/checklists/            # New feature
│   ├── data/
│   │   ├── checklist_dao.dart      # DailyChecklistDao
│   │   ├── checklist_dao.g.dart    # generated
│   │   └── checklist_repository.dart
│   ├── domain/
│   │   └── checklist_model.dart    # Freezed model
│   └── presentation/
│       ├── providers/
│       │   └── checklist_provider.dart
│       └── screens/
│           └── daily_checklist_screen.dart
└── core/sync/handlers/
    └── checklist_sync_handler.dart

web/src/app/(dashboard)/
└── dashboard/
    ├── page.tsx                    # DASH-01: project cards overview
    └── _components/
        ├── ProjectStatusCard.tsx   # Per-project card with trade badges
        ├── TradeStatusBadge.tsx    # on track / at risk / blocked badge
        ├── AlertPanel.tsx          # DASH-03: AI alerts list
        └── TradeTimeline.tsx       # DASH-02: SVAR Gantt for trade timeline
```

### Pattern 1: APScheduler with FastAPI Lifespan

**What:** Register background jobs in FastAPI startup/shutdown lifespan events using `AsyncIOScheduler`. Jobs run in the same process but are non-blocking.

**When to use:** Two cron jobs — morning checklist (6 AM daily) and bi-hourly alert detection during work hours (7 AM–7 PM).

**Example:**
```python
# Source: APScheduler 3.x official docs + FastAPI lifespan pattern
from contextlib import asynccontextmanager
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

scheduler = AsyncIOScheduler()

@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler.add_job(
        run_morning_checklists,
        CronTrigger(hour=6, minute=0),
        id="morning_checklists",
        replace_existing=True,
    )
    scheduler.add_job(
        run_alert_detection,
        CronTrigger(hour="7-19", minute=0, second=0),  # every hour 7am-7pm
        id="alert_detection",
        replace_existing=True,
    )
    scheduler.start()
    yield
    scheduler.shutdown()

app = FastAPI(lifespan=lifespan)
```

### Pattern 2: Non-Streaming Claude API Call for Structured JSON

**What:** For checklist and alert generation, use `_anthropic_client.messages.create()` (NOT streaming) with a JSON-schema-constrained system prompt. This returns a complete message synchronously, suitable for background jobs.

**When to use:** Background jobs where SSE streaming is irrelevant — the job stores the result, not streams it to a client.

**Example:**
```python
# Source: anthropic SDK docs + existing AIService pattern in service.py
import json
from anthropic import AsyncAnthropic

_anthropic_client = AsyncAnthropic()  # reuse module-level client

async def generate_checklist_json(prompt: str, tasks_context: str) -> dict:
    """Non-streaming Claude call returning structured JSON checklist."""
    response = await _anthropic_client.messages.create(
        model="claude-sonnet-4-6",  # same model as AIService
        max_tokens=2048,
        system=CHECKLIST_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": tasks_context}],
    )
    # Parse JSON from response text
    text = response.content[0].text
    return json.loads(text)
```

### Pattern 3: FCM Morning Push (Fire-and-Forget)

**What:** Reuse `NotificationService` fire-and-forget pattern. Wrap in `asyncio.create_task` so FCM failures never block checklist storage.

**When to use:** Morning checklist push for each contractor. Identical to Phase 24's rejection notification pattern.

**Example:**
```python
# Source: backend/app/features/notifications/service.py — send_task_rejection_notification
asyncio.create_task(
    notification_svc.send_checklist_notification(
        contractor_id=contractor_id,
        checklist_summary=f"You have {n} tasks today: {top_titles}",
        checklist_id=checklist.id,
    )
)
```

### Pattern 4: Dashboard API — Project Status Aggregation

**What:** The dashboard endpoint aggregates task counts per trade scope in a single query (no N+1). Uses SQLAlchemy `selectinload` for trade_scopes → tasks, then computes status badges in Python.

**Trade status badge logic:**
- `blocked` — any task with status='blocked'
- `at_risk` — any task past due_date with status != 'complete'
- `on_track` — everything else

**Example:**
```python
# Pattern: eager-load trade_scopes + tasks in one query
from sqlalchemy.orm import selectinload

stmt = (
    select(Project)
    .options(
        selectinload(Project.trade_scopes).selectinload(TradeScope.tasks)
    )
    .where(Project.company_id == company_id)
    .where(Project.status == "active")
    .where(Project.deleted_at.is_(None))
)
```

### Pattern 5: Drift Schema v14 — DailyChecklists Table

**What:** Add `DailyChecklists` Drift table following the existing `BillingMilestones` pattern. Register in `AppDatabase` with a new `DailyChecklistDao`. Migration in `onUpgrade` block `if (from < 14)`.

**Example (table definition):**
```dart
// Source: existing BillingMilestones table pattern
class DailyChecklists extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text()();
  TextColumn get contractorId => text()();
  TextColumn get projectId => text()();
  TextColumn get tradeScopeId => text()();
  TextColumn get checklistDate => text()();  // ISO date string YYYY-MM-DD
  TextColumn get checklistJson => text()();  // Full JSON from AI
  TextColumn get summaryText => text()();    // "N tasks: title1, title2..."
  BoolColumn get isPushed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Pattern 6: SVAR Gantt for Trade Timeline (DASH-02)

**What:** Reuse the existing `GanttView` component from `web/src/components/gantt/GanttView.tsx`. For the dashboard trade timeline, create trade-level summary rows (not individual tasks) as SVAR parent tasks, with progress fill from task completion percentages.

**Key known quirk (from Phase 20):** `dynamic(ssr: false)` is required — SVAR Gantt cannot be SSR'd. ILink type must be cast as `ILink['type']` since `TLinkType` is not re-exported.

### Anti-Patterns to Avoid

- **Calling Claude API in a loop per contractor:** Batch all contractors for a company in one scheduled job iteration — Claude API calls are billed per token and have rate limits. Generate checklists sequentially per contractor with retry.
- **Auto-applying rescheduling suggestions:** D-15 is explicit — GC must accept. Never update `Task.due_date` or `Task.start_date` without explicit GC action.
- **Blocking checklist generation on FCM:** FCM is fire-and-forget. Use `asyncio.create_task` or `asyncio.gather` with `return_exceptions=True`.
- **N+1 in alert detection job:** Load all projects with scopes and tasks in one query per company using `selectinload`. Never query tasks inside a loop over scopes.
- **Using `stream_turn` from AIService for checklist/alert:** That method is for SSE streaming to web clients. For background jobs, call `_anthropic_client.messages.create()` directly (non-streaming).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Background scheduling | Custom thread + `asyncio.sleep` loop | APScheduler `AsyncIOScheduler` | APScheduler handles missed executions, timezone-aware cron, jitter, persistence |
| FCM push to multiple devices | Custom per-device loop with new error handling | Existing `NotificationService` methods | Fire-and-forget pattern, UnregisteredError cleanup, executor pool already built |
| Dependency cascade for alert detection | Custom graph traversal | `DependencyService._recompute_blocked_status` | Already handles FS/SS/SE blocking logic, FF non-blocking, cycle safety |
| Trade timeline chart | Custom SVG horizontal bars | SVAR Gantt (already installed) | Already integrated in Phase 20 with known SSR workaround |
| Progress bar in project cards | Custom CSS bars | Recharts `LinearProgress` or simple styled div | Recharts already installed; simple progress bars don't need chart library at all — use CSS |
| JSON structured output from Claude | LangChain JSON output parser | Direct `json.loads()` on response text with JSON system prompt | LangChain is not in this stack; Claude reliably returns JSON when instructed |

**Key insight:** The most complex piece is NOT the AI — it's the alert detection logic that compares `Task.due_date` vs `datetime.date.today()` across all tasks for all active projects. This is a database aggregation problem, not an AI problem.

---

## Common Pitfalls

### Pitfall 1: APScheduler Job Runs in Wrong Timezone
**What goes wrong:** `CronTrigger(hour=6)` defaults to UTC. Contractors in US timezones get the push at 1 AM or 11 PM.
**Why it happens:** APScheduler defaults to UTC unless timezone is explicitly set.
**How to avoid:** Add `timezone='America/New_York'` or store per-company timezone in settings and dynamically adjust. For MVP, use UTC+offset from company settings or accept a configurable env var `CHECKLIST_TZ`.
**Warning signs:** Contractors report receiving morning push notifications at wrong hours.

### Pitfall 2: Multiple Workers Run the Same Scheduled Job
**What goes wrong:** In production with multiple uvicorn workers (e.g. 4 workers), each worker runs its own APScheduler instance, generating 4x checklists for each contractor.
**Why it happens:** APScheduler in-process has no distributed coordination.
**How to avoid:** Use `APScheduler` with `SQLAlchemyJobStore` (PostgreSQL backend) so only one worker executes each job. Alternative: run scheduler in a single dedicated worker. For MVP, document as a known limitation and use `--workers 1` if running with gunicorn.
**Warning signs:** Duplicate `daily_checklists` records for the same contractor on the same date. Add a `UNIQUE(company_id, contractor_id, checklist_date)` constraint to catch this.

### Pitfall 3: Claude API Rate Limits Hit During Morning Job
**What goes wrong:** A company with 20 contractors triggers 20 Claude API calls in rapid succession. API returns `RateLimitError`.
**Why it happens:** Anthropic rate limits are per API key (tokens per minute and requests per minute).
**How to avoid:** Add `asyncio.sleep(0.5)` between contractor API calls in the job. Reuse the existing `_RETRY_DELAYS = [1.0, 2.0, 4.0]` backoff pattern from `AIService._call_with_retry`. Log warning but continue to next contractor if all retries fail.
**Warning signs:** `RateLimitError` in logs during 6 AM job.

### Pitfall 4: Dashboard Stale Alert Count
**What goes wrong:** GC sees stale alert counts on project cards after marking alerts as read. TanStack Query cache still shows old data.
**Why it happens:** Query invalidation not triggered after `POST /dashboard/alerts/{id}/read`.
**How to avoid:** On successful mark-as-read mutation, call `queryClient.invalidateQueries({ queryKey: ['dashboard-alerts'] })`. Follow the Phase 20 pattern of prefix-key invalidation.

### Pitfall 5: Drift `DailyChecklists` Table Missing from Sync Handler
**What goes wrong:** Checklists stored on backend never appear on mobile offline — contractor opens app without network and sees empty checklist.
**Why it happens:** Sync handlers are explicitly registered. A new entity type needs its own `SyncHandler` subclass registered in `SyncRegistry`.
**How to avoid:** Create `checklist_sync_handler.dart` following the `billing_milestone_sync_handler.dart` pattern. Register in `service_locator.dart` and `sync_engine.dart` entity types list.

### Pitfall 6: SVAR Gantt SSR Error in Dashboard Page
**What goes wrong:** `ReferenceError: window is not defined` during Next.js build/SSR.
**Why it happens:** SVAR Gantt uses browser-only APIs.
**How to avoid:** Load `TradeTimeline` component with `dynamic(ssr: false)` — identical to the Phase 20 GanttView pattern.

### Pitfall 7: Alert Detection Job Runs on Soft-Deleted Projects
**What goes wrong:** Alert job generates alerts for archived or completed projects, filling `dashboard_alerts` with noise.
**Why it happens:** Job query doesn't filter by project status.
**How to avoid:** Filter `Project.status IN ('active', 'planning')` and `Project.deleted_at IS NULL` in the alert detection query.

---

## Code Examples

Verified patterns from official/project sources:

### APScheduler AsyncIOScheduler with FastAPI Lifespan
```python
# Source: APScheduler 3.x docs (https://apscheduler.readthedocs.io/en/3.x/)
# Pattern: register scheduler in FastAPI lifespan (startup/shutdown)
from contextlib import asynccontextmanager
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

scheduler = AsyncIOScheduler(timezone="UTC")

@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler.add_job(
        run_morning_checklists,
        CronTrigger(hour=6, minute=0, timezone="UTC"),
        id="morning_checklists",
        replace_existing=True,
        misfire_grace_time=3600,  # if server down at 6am, run within 1hr
    )
    scheduler.add_job(
        run_alert_detection,
        CronTrigger(hour="7-19", minute=0, timezone="UTC"),
        id="alert_detection",
        replace_existing=True,
        misfire_grace_time=600,
    )
    scheduler.start()
    yield
    scheduler.shutdown(wait=False)

app = FastAPI(lifespan=lifespan)
```

### Non-Streaming Claude API Call for Structured JSON
```python
# Source: existing service.py _anthropic_client pattern (Phase 21)
# For background jobs — no SSE needed
async def call_claude_for_json(system_prompt: str, user_content: str) -> dict:
    """Single non-streaming Claude call returning parsed JSON dict."""
    response = await _anthropic_client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2048,
        system=system_prompt,
        messages=[{"role": "user", "content": user_content}],
    )
    raw_text = response.content[0].text.strip()
    # Strip markdown code fences if Claude wraps JSON in ```json
    if raw_text.startswith("```"):
        raw_text = "\n".join(raw_text.split("\n")[1:-1])
    return json.loads(raw_text)
```

### Drift v14 Migration Block
```dart
// Source: app_database.dart migration pattern (from < 13 for billing_milestones)
if (from < 14) {
  // Phase 26: AI daily checklists for offline contractor access
  await m.createTable(dailyChecklists);
}
```

### DashboardAlert SQLAlchemy Model
```python
# Source: TenantScopedModel pattern (base_models.py)
class DashboardAlert(TenantScopedModel):
    __tablename__ = "dashboard_alerts"

    project_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    trade_scope_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)  # soft FK
    severity: Mapped[str] = mapped_column(Text, nullable=False)  # info/warning/critical
    alert_type: Mapped[str] = mapped_column(Text, nullable=False)  # schedule_slip/rescheduling_suggestion
    days_behind: Mapped[int | None] = mapped_column(Integer, nullable=True)
    impact_text: Mapped[str] = mapped_column(Text, nullable=False)  # AI-generated plain English
    remediation_text: Mapped[str | None] = mapped_column(Text, nullable=True)  # AI suggestion
    affected_scope_ids: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    rescheduling_payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)  # proposed new dates
    rescheduling_accepted: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
```

### DailyChecklist SQLAlchemy Model
```python
class DailyChecklist(TenantScopedModel):
    __tablename__ = "daily_checklists"

    contractor_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)  # soft FK
    project_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    trade_scope_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)  # soft FK
    checklist_date: Mapped[date] = mapped_column(Date, nullable=False)  # the date this checklist is for
    checklist_json: Mapped[dict] = mapped_column(JSONB, nullable=False)  # structured AI output
    summary_text: Mapped[str] = mapped_column(Text, nullable=False)  # FCM push body
    is_pushed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    __table_args__ = (
        # Prevent duplicate checklists for same contractor/scope/date
        UniqueConstraint("company_id", "contractor_id", "trade_scope_id", "checklist_date",
                         name="uq_daily_checklist_contractor_scope_date"),
    )
```

### SVAR Gantt for Trade Timeline (Dashboard)
```tsx
// Source: web/src/components/gantt/GanttView.tsx (Phase 20 pattern)
// For dashboard: each SVAR "task" is a TradeScope, not individual tasks
import dynamic from "next/dynamic";
const GanttChart = dynamic(
  () => import("@svar-ui/react-gantt").then((mod) => mod.Gantt),
  { ssr: false }  // CRITICAL: SVAR Gantt is browser-only
);

// Trade-level summary row: start = min(task.start_date), end = max(task.due_date)
// progress: completed_tasks / total_tasks * 100
const tradeTasks: ITask[] = scopes.map(scope => ({
  id: scope.id,
  text: scope.trade_name,
  start_date: minStartDate(scope.tasks),
  end_date: maxDueDate(scope.tasks),
  progress: completionPercent(scope.tasks),
  parent: 0,
}));
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Celery + Redis for scheduled tasks | APScheduler AsyncIOScheduler in FastAPI lifespan | FastAPI lifespan API (0.93+) | No separate worker process, simpler dev setup |
| LangChain for structured AI output | Direct Claude API + JSON system prompt + `json.loads()` | Phase 21 established pattern | Less abstraction, clearer control, already implemented |
| Separate scheduler service/container | In-process APScheduler | Phase 26 (this phase) | Single deployment unit; caveat: multi-worker issue documented above |

**Deprecated/outdated in this context:**
- `@app.on_event("startup")` / `@app.on_event("shutdown")`: Deprecated in FastAPI 0.93+. Use `lifespan` context manager instead.
- APScheduler 4.x (alpha): API is completely changed. Stay on 3.10.x.

---

## Open Questions

1. **Per-company timezone for 6 AM checklist**
   - What we know: `Settings` has no timezone field. APScheduler uses UTC by default.
   - What's unclear: Is there a company timezone in the `companies` table?
   - Recommendation: Add `timezone` field to `companies` table in migration 0024, defaulting to `"America/New_York"`. Checklist job iterates companies and uses each company's timezone for `CronTrigger` scheduling. Alternative for MVP: use a single configurable env var `CHECKLIST_TZ=America/New_York`.

2. **Weather API integration (D-02 says "if available")**
   - What we know: No weather API is currently integrated. `config.py` has no weather API key.
   - What's unclear: Which weather API to use; cost implications.
   - Recommendation: Skip weather integration for MVP. Add a comment in the checklist prompt saying "weather data not available" and leave a clearly-marked TODO. The AI prompt still works without weather context.

3. **Multi-worker APScheduler coordination**
   - What we know: Production likely uses multiple uvicorn workers (gunicorn with workers > 1).
   - What's unclear: Whether the deployment uses `--workers 1` or multiple.
   - Recommendation: Add `UNIQUE(company_id, contractor_id, trade_scope_id, checklist_date)` constraint on `daily_checklists` to catch duplicate generation. Document the multi-worker limitation. Use `insert ... ON CONFLICT DO NOTHING` when storing checklists to make generation idempotent.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 (backend), flutter test + mocktail 1.0.4 (mobile) |
| Config file | `backend/pytest.ini` or `pyproject.toml` (existing), `mobile/pubspec.yaml` |
| Quick run command | `cd backend && uv run python -m pytest tests/test_phase_26_e2e.py -x` |
| Full suite command | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AI-04 | Checklist generated for contractor with unblocked tasks today | integration | `pytest tests/test_phase_26_e2e.py::test_checklist_generation -x` | Wave 0 |
| AI-04 | FCM push triggered after checklist stored | unit (mock FCM) | `pytest tests/test_phase_26_e2e.py::test_checklist_fcm_push -x` | Wave 0 |
| AI-04 | Contractor sees checklist on mobile DailyChecklistScreen | widget | `flutter test test/e2e/phase_26_checklists_e2e_test.dart` | Wave 0 |
| AI-05 | Alert generated when trade falls behind by > 1 day | integration | `pytest tests/test_phase_26_e2e.py::test_alert_schedule_slip -x` | Wave 0 |
| AI-05 | GC dismiss alert → alert marked dismissed, no date change | integration | `pytest tests/test_phase_26_e2e.py::test_alert_dismiss -x` | Wave 0 |
| AI-05 | GC accept rescheduling → task due_dates updated | integration | `pytest tests/test_phase_26_e2e.py::test_alert_accept_reschedule -x` | Wave 0 |
| DASH-01 | GET /dashboard returns active projects with trade status | integration | `pytest tests/test_phase_26_e2e.py::test_dashboard_project_list -x` | Wave 0 |
| DASH-02 | Project detail includes trade timeline with start/end dates | integration | `pytest tests/test_phase_26_e2e.py::test_dashboard_trade_timeline -x` | Wave 0 |
| DASH-03 | Alert with severity=critical when trade behind > 3 days | integration | `pytest tests/test_phase_26_e2e.py::test_dashboard_alert_severity -x` | Wave 0 |
| DASH-04 | Trade drill-down returns task list inline | integration | `pytest tests/test_phase_26_e2e.py::test_dashboard_trade_drilldown -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/test_phase_26_e2e.py -x`
- **Per wave merge:** `cd backend && uv run python -m pytest && cd ../mobile && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_26_e2e.py` — covers all AI-04, AI-05, DASH-01 through DASH-04 integration tests
- [ ] `mobile/test/e2e/phase_26_checklists_e2e_test.dart` — covers DailyChecklistScreen widget tests
- [ ] `backend/app/core/scheduler.py` — APScheduler setup (needed before jobs can be tested)
- [ ] `backend/migrations/versions/0024_ai_checklists_and_alerts.py` — new tables needed for integration tests
- [ ] Framework install: `cd backend && uv pip install "apscheduler==3.10.4"` — not yet in requirements.txt

---

## Sources

### Primary (HIGH confidence)
- Project codebase — `backend/app/features/ai/service.py` (AIService, Claude API patterns, model name `claude-sonnet-4-6`)
- Project codebase — `backend/app/features/notifications/service.py` (FCM fire-and-forget pattern, UnregisteredError handling)
- Project codebase — `backend/app/features/projects/service.py` (DependencyService._recompute_blocked_status, cascade logic)
- Project codebase — `mobile/lib/core/database/app_database.dart` (schema v13, migration pattern, Drift table registration)
- Project codebase — `web/src/components/gantt/GanttView.tsx` (SVAR Gantt integration, SSR:false pattern, ILink type cast)
- Project codebase — `web/package.json` (@svar-ui/react-gantt 2.5.2, recharts 3.8.0, @tanstack/react-query 5.90.21 confirmed installed)
- Project codebase — `backend/requirements.txt` (apscheduler NOT present — must be added; anthropic >=0.86.0 present)

### Secondary (MEDIUM confidence)
- APScheduler 3.x official docs (https://apscheduler.readthedocs.io/en/3.x/) — AsyncIOScheduler + CronTrigger + misfire_grace_time patterns
- FastAPI lifespan docs (https://fastapi.tiangolo.com/advanced/events/) — lifespan context manager replacing deprecated @on_event
- STATE.md accumulated decisions — Phase 21 SDK patterns, Phase 20 Gantt integration quirks, Phase 24 FCM fire-and-forget

### Tertiary (LOW confidence)
- APScheduler multi-worker recommendation: SQLAlchemyJobStore as coordination mechanism (community pattern, not verified against v3.10.4 docs directly)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified in requirements.txt / package.json; APScheduler is the only new package
- Architecture patterns: HIGH — all derived from existing project code patterns (AIService, NotificationService, Drift migrations, GanttView)
- Pitfalls: MEDIUM — timezone pitfall and multi-worker pitfall are well-known APScheduler issues from community, not verified against prod deployment config

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable libraries; APScheduler 3.x is mature)
