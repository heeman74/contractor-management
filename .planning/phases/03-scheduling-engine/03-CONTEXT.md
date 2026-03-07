# Phase 3: Scheduling Engine - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

The backend scheduling engine computes contractor availability, detects booking conflicts (including travel time buffers), and safely blocks multiple days for spanning jobs — all enforced at the database level. This is a pure business logic module exercised by unit tests independent of any HTTP routing. API endpoints that expose the engine are part of the planned work (03-05), but the engine itself is the core deliverable.

Requirements: SCHED-04, SCHED-05, SCHED-06, SCHED-07

</domain>

<decisions>
## Implementation Decisions

### Working Hours Model
- Company default schedule + per-contractor overrides at two levels:
  1. **Weekly template override**: Contractor gets a personal weekly template that starts as copy of company default. Can permanently change their regular hours.
  2. **Date-specific override**: Specific dates can have custom hours or be marked unavailable (days off, holidays, sick days).
- Per-day hours — each day of the week can have different start/end times (e.g., Mon 7am-4pm, Fri 7am-12pm)
- Multiple time blocks per day supported — lunch breaks and gaps modeled as separate available blocks (e.g., 7am-12pm + 1pm-4pm)
- Break times defined in weekly template — automatically excluded from scheduling
- Per-contractor timezone — each contractor can have their own timezone for scheduling
- Hard constraint — cannot schedule jobs outside defined working hours. No override.
- Both admin and contractor can freely edit the contractor's schedule — no approval workflow
- Contractor with no personal template inherits company default — schedulable immediately after being added
- Trade-filtered availability — get_available_slots() accepts optional trade type filter, using trade_types already on contractors from Phase 1
- No recurring block system beyond weekly template — the per-day hours in the template cover recurring patterns
- Date overrides support full flexibility — custom multi-block schedules per override date, same structure as weekly template
- Block days/date ranges for unavailability — no categorized leave types (holiday, sick, etc.)

### Time Slot Granularity
- Free-form times — no fixed grid. Jobs can start/end at any minute.
- Engine returns free windows (available time ranges), not discrete slots — caller decides how to use the window
- Free windows include reason for gaps — response shows why each gap is blocked (existing job, time off, outside working hours). Feeds into Phase 5 calendar UI.
- Configurable minimum job duration — company admin sets minimum (e.g., 30 min), engine rejects bookings shorter than this
- Configurable buffer between jobs — company sets fixed buffer (e.g., 15 min) for cleanup/setup, added on top of travel time
- Both min duration and buffer are per-contractor overridable (company default + contractor override, consistent with hours model)
- Multi-contractor query supported — API accepts list of contractor IDs or trade filter, returns each contractor's free windows
- Proximity sorting — results sorted by distance to job site. Prefer contractor's last job site address, fallback to home base address.

### Multi-Day Job Structure
- Custom per-day times — each day of a multi-day job can have different start/end times (Mon 8am-4pm, Tue 10am-2pm, Wed 8am-12pm)
- Non-consecutive days allowed — jobs can span specific days with gaps (e.g., Monday and Wednesday, not Tuesday). Supports drying time, inspections, etc.
- Single contractor per job — one contractor owns the entire multi-day job across all days
- All-or-nothing booking — if any day conflicts, the entire multi-day booking fails. No partial scheduling.
- Per day-block GIST constraints — each day of a multi-day job creates a separate booking record with its own time range. Allows other jobs in gaps between non-consecutive days.
- Per-day modification — individual days can be rescheduled, cancelled, or time-adjusted without affecting other days of the same job
- No maximum job span — jobs can span any number of days
- Engine suggests date combinations for multi-day scheduling — returns available date sets that fit the requested number of days
- Prefer consecutive dates when suggesting — prioritize consecutive blocks, suggest non-consecutive only if consecutive isn't available
- Travel time conflicts block rescheduling — treat travel time conflicts same as booking conflicts (hard rejection)

### Concurrent Booking Safety
- Application-level lock first — SELECT FOR UPDATE on contractor's schedule row before booking attempt
- GIST constraint as safety net — belt and suspenders. Application lock is primary, GIST catches anything that slips through.
- Per-contractor lock scope — two admins can book different contractors simultaneously, only serializes bookings for the same contractor
- Conflict error includes details — error response shows conflicting job ID, time range, and contractor name
- Pre-check then insert — query available slots first (availability check), then insert. Admin sees what's available before committing.

### Travel Time
- **API provider**: OpenRouteService (free tier: 2000 requests/day)
- **Pluggable provider interface** — abstract travel time behind an interface. ORS is default, easy to swap to Google Maps later.
- **Cache**: PostgreSQL table with 30-day TTL
- **Cache key**: lat/lng coordinates rounded to 3 decimal places (~100m precision)
- **Bidirectional**: A->B and B->A treated as same value (halves cache and API calls)
- **Driving mode only** — contractors drive between sites
- **Configurable safety margin** — company sets a percentage buffer (e.g., 20%) on top of raw API travel time. Accounts for parking, loading tools, etc.
- **On-demand with cache** — calculate when needed, cache result. No batch precompute.
- **Fallback**: Use cached value if available (even if expired), else company-configurable default travel time (e.g., 30 min)

### Address & Geocoding
- Geocode on address entry — store lat/lng alongside address immediately. Travel time uses cached coordinates.
- Address input supports manual text entry and GPS device location (GPS capture is Phase 6/FIELD-02, but the engine expects lat/lng stored)
- **Pluggable geocoding provider** — same pattern as travel time. ORS geocoding (Pelias) as default.
- Require valid geocode — reject job creation if address can't be geocoded. Ensures travel time can always be calculated.
- Contractor home base address — add home_address + lat/lng to contractor profile in this phase (needed for proximity sorting fallback)

### Scheduling Settings Storage
- Company-level scheduling config stored as **JSONB column on companies table** (scheduling_config)
- Validated by a **Pydantic SchedulingConfig model** — typed fields for default working hours, buffer minutes, min job duration, travel margin percentage, default travel time
- Per-contractor overrides stored in **dedicated tables**:
  - `contractor_weekly_schedule`: (contractor_id, day_of_week, block_index, start_time, end_time) — multiple blocks per day
  - `contractor_date_overrides`: same structure but keyed by specific date instead of day_of_week — full flexibility (multi-block per override date)

### Engine API Pattern
- SchedulingService class with methods (get_available_slots, check_conflicts, book_slot, suggest_dates, etc.)
- Follows BaseService/TenantScopedService pattern from app/core/base_service.py
- Pure business logic module — unit tested independent of HTTP routing

### Testing Strategy
- **Mixed approach**: Unit tests with mocked DB for pure logic + integration tests with real PostgreSQL for constraints
- **GIST constraint testing**: Both sequential (insert overlapping booking) AND concurrent (asyncio.gather for race condition proof)
- **Load test**: ~50-100 concurrent booking attempts for same slot — verify lock + GIST hold under pressure
- **Travel time mocking**: Record/replay fixtures from real ORS API responses
- **Geocoding mocking**: Record/replay fixtures (consistent with travel time approach)
- **Fixtures**: Extend Phase 1/2 fixtures (users, companies) with scheduling-specific data (schedules, bookings, job sites)
- **Multi-day edge cases**: Non-consecutive days, partial last day, timezone boundary spanning, overlapping multi-day jobs, single-day-of-multiday reschedule
- **DST edge case**: Test bookings that span daylight saving time transitions
- **Success criteria test**: Two simultaneous booking attempts for same slot — exactly one success (concurrent asyncio.gather test)

### Claude's Discretion
- Exact table schemas and column types for scheduling tables
- SchedulingService internal method decomposition
- Travel time provider interface design details
- Alembic migration structure (single vs multiple migrations)
- Test fixture data composition
- Error response format details
- Geocoding coordinate rounding implementation

</decisions>

<specifics>
## Specific Ideas

- The scheduling engine is the product differentiator — must handle real-world complexity (travel time, multi-day, team availability)
- Working hours should feel natural for trade companies — 7am starts, lunch breaks, early Friday finishes
- Address entry supports both manual text and GPS device location (GPS capture deferred to Phase 6, but lat/lng storage needed now)
- Proximity sorting uses "last job site, fallback to home base" — reflects how field dispatch actually works

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TenantScopedModel` (app/core/base_models.py): Base for all scheduling tables — provides UUID PK, version, timestamps, company_id FK
- `TenantScopedService` / `TenantScopedRepository` (app/core/): OOP base classes for scheduling service/repository
- `BaseRouter` / `CRUDRouter` (app/core/base_router.py): Router patterns for scheduling API endpoints
- `BaseResponseSchema` (app/core/base_schemas.py): Response schema base for scheduling API responses
- `btree_gist` extension already installed in migration 0001 — ready for EXCLUDE USING GIST constraint
- Existing company model has `trade_types` ARRAY column — usable for trade-filtered availability queries

### Established Patterns
- Domain-driven backend structure: `app/features/<domain>/` with routes, services, models, schemas
- OOP architecture required: all services/repos/routers must inherit from base classes
- AsyncSession via `get_db` dependency — no manual commit, use flush() for generated IDs
- RLS policies on all tenant-scoped tables — scheduling tables must follow same pattern
- Sync registry pattern (Phase 2) — scheduling entities will register handlers for offline sync in later phases
- PostgreSQL triggers for `updated_at` — use migration-level trigger, not SQLAlchemy onupdate

### Integration Points
- Alembic migration 0007+ — new tables for scheduling (bookings, weekly schedules, date overrides, travel cache)
- Companies table: add `scheduling_config` JSONB column
- Users table: add `home_address`, `home_latitude`, `home_longitude`, `timezone` columns for contractor scheduling
- RLS policies needed on all new scheduling tables
- Sync handlers to be registered in later phases when scheduling data syncs to mobile

</code_context>

<deferred>
## Deferred Ideas

- GPS-based address capture from device (Phase 6 — FIELD-02)
- Contractor self-managed availability calendar UI (v2 — ADV-01)
- Route optimization for daily job sequences (v2 — ADV-02)
- Crew/team scheduling — multiple contractors per job (future consideration)

</deferred>

---

*Phase: 03-scheduling-engine*
*Context gathered: 2026-03-06*
