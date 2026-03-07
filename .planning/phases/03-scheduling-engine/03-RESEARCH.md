# Phase 3: Scheduling Engine - Research

**Researched:** 2026-03-06
**Domain:** PostgreSQL range types / GIST constraints, SQLAlchemy async ORM, scheduling algorithm, OpenRouteService API, timezone-aware datetime
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Working Hours Model**
- Company default schedule + per-contractor overrides at two levels:
  1. Weekly template override: Contractor gets a personal weekly template that starts as copy of company default.
  2. Date-specific override: Specific dates can have custom hours or be marked unavailable.
- Per-day hours — each day of the week can have different start/end times
- Multiple time blocks per day supported (lunch breaks modeled as separate blocks)
- Break times defined in weekly template — automatically excluded from scheduling
- Per-contractor timezone — each contractor can have their own timezone
- Hard constraint — cannot schedule jobs outside defined working hours. No override.
- Both admin and contractor can freely edit the contractor's schedule — no approval workflow
- Contractor with no personal template inherits company default — schedulable immediately
- Trade-filtered availability — get_available_slots() accepts optional trade type filter
- No recurring block system beyond weekly template
- Date overrides support full flexibility — custom multi-block schedules per override date
- Block days/date ranges for unavailability — no categorized leave types

**Time Slot Granularity**
- Free-form times — no fixed grid. Jobs can start/end at any minute.
- Engine returns free windows (available time ranges), not discrete slots
- Free windows include reason for gaps (existing job, time off, outside working hours)
- Configurable minimum job duration — company admin sets minimum (e.g., 30 min)
- Configurable buffer between jobs — company sets fixed buffer (e.g., 15 min) for cleanup/setup
- Both min duration and buffer are per-contractor overridable
- Multi-contractor query supported — API accepts list of contractor IDs or trade filter
- Proximity sorting — results sorted by distance to job site

**Multi-Day Job Structure**
- Custom per-day times — each day of a multi-day job can have different start/end times
- Non-consecutive days allowed
- Single contractor per job
- All-or-nothing booking — if any day conflicts, entire multi-day booking fails
- Per day-block GIST constraints — each day creates a separate booking record
- Per-day modification — individual days can be rescheduled/cancelled
- No maximum job span
- Engine suggests date combinations for multi-day scheduling
- Prefer consecutive dates when suggesting
- Travel time conflicts block rescheduling (hard rejection, same as booking conflicts)

**Concurrent Booking Safety**
- Application-level lock first — SELECT FOR UPDATE on contractor's schedule row before booking
- GIST constraint as safety net — belt and suspenders
- Per-contractor lock scope
- Conflict error includes details — conflicting job ID, time range, and contractor name
- Pre-check then insert — query available slots first, then insert

**Travel Time**
- API provider: OpenRouteService (free tier: 2000 requests/day)
- Pluggable provider interface — abstract travel time behind an interface
- Cache: PostgreSQL table with 30-day TTL
- Cache key: lat/lng coordinates rounded to 3 decimal places (~100m precision)
- Bidirectional: A->B and B->A treated as same value
- Driving mode only
- Configurable safety margin — company sets percentage buffer (e.g., 20%) on top of raw API travel time
- On-demand with cache — calculate when needed, cache result
- Fallback: Use cached value if available (even if expired), else company-configurable default

**Address & Geocoding**
- Geocode on address entry — store lat/lng alongside address
- Pluggable geocoding provider — ORS geocoding (Pelias) as default
- Require valid geocode — reject job creation if address can't be geocoded
- Contractor home base address — add home_address + lat/lng to contractor profile

**Scheduling Settings Storage**
- Company-level scheduling config stored as JSONB column on companies table (scheduling_config)
- Validated by a Pydantic SchedulingConfig model
- Per-contractor overrides stored in dedicated tables:
  - `contractor_weekly_schedule`: (contractor_id, day_of_week, block_index, start_time, end_time)
  - `contractor_date_overrides`: same structure but keyed by specific date

**Engine API Pattern**
- SchedulingService class with methods (get_available_slots, check_conflicts, book_slot, suggest_dates, etc.)
- Follows BaseService/TenantScopedService pattern from app/core/base_service.py
- Pure business logic module — unit tested independent of HTTP routing

**Testing Strategy**
- Mixed approach: Unit tests with mocked DB for pure logic + integration tests with real PostgreSQL for constraints
- GIST constraint testing: Both sequential AND concurrent (asyncio.gather for race condition proof)
- Load test: ~50-100 concurrent booking attempts for same slot
- Travel time mocking: Record/replay fixtures from real ORS API responses
- Geocoding mocking: Record/replay fixtures
- Multi-day edge cases: Non-consecutive days, partial last day, timezone boundary spanning, overlapping multi-day jobs
- DST edge case: Test bookings that span daylight saving time transitions
- Success criteria test: Two simultaneous booking attempts for same slot — exactly one success

### Claude's Discretion
- Exact table schemas and column types for scheduling tables
- SchedulingService internal method decomposition
- Travel time provider interface design details
- Alembic migration structure (single vs multiple migrations)
- Test fixture data composition
- Error response format details
- Geocoding coordinate rounding implementation

### Deferred Ideas (OUT OF SCOPE)
- GPS-based address capture from device (Phase 6 — FIELD-02)
- Contractor self-managed availability calendar UI (v2 — ADV-01)
- Route optimization for daily job sequences (v2 — ADV-02)
- Crew/team scheduling — multiple contractors per job (future consideration)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-04 | Contractor availability tracking (who's free when) | Weekly template + date override tables, get_available_slots() engine method with interval subtraction algorithm |
| SCHED-05 | Conflict detection preventing double-bookings | EXCLUDE USING GIST on tstzrange + SELECT FOR UPDATE application lock; both layers researched |
| SCHED-06 | Travel time awareness in scheduling (buffer between jobs) | OpenRouteService API integration, PostgreSQL travel cache table, pluggable provider interface pattern |
| SCHED-07 | Multi-day job support (jobs spanning days/weeks with partial-day assignments) | Per-day booking records with independent GIST constraints; all-or-nothing booking transaction; suggest_dates() algorithm |
</phase_requirements>

---

## Summary

Phase 3 introduces the backend scheduling engine for ContractorHub. The engine is a pure business logic module (no HTTP dependency) that computes contractor availability, detects booking conflicts, and handles multi-day job spanning. Three interlocking mechanisms enforce correctness: (1) a PostgreSQL GIST exclusion constraint on `tstzrange` prevents overlapping bookings at the database level, (2) `SELECT FOR UPDATE` on a contractor schedule row serializes concurrent booking attempts at the application level, and (3) the availability computation algorithm subtracts existing bookings, travel time, and working-hour boundaries before returning free windows.

The scheduling domain brings six new tables (bookings, contractor_weekly_schedule, contractor_date_overrides, job_sites, travel_time_cache, and a contractor_schedule_locks anchor) plus a JSONB column on companies. All tables follow existing `TenantScopedModel` patterns with RLS policies. The `btree_gist` PostgreSQL extension is already installed (migration 0001), so GIST constraints on mixed scalar + range columns are immediately available.

Travel time is fetched from OpenRouteService (ORS) via a direct `httpx` async call (not the synchronous `openrouteservice-py` client, which would block the event loop). Results are cached in PostgreSQL with a 30-day TTL. Timezone handling uses Python's built-in `zoneinfo` module (Python 3.12, no extra dependencies) with UTC storage in the database and per-contractor local-time conversion at computation time.

**Primary recommendation:** Build the scheduling engine as a `TenantScopedService` subclass with repository, test it pure-logic-first (mocked DB for interval arithmetic), then integration-test the GIST constraint with real PostgreSQL using `asyncio.gather` to simulate concurrent booking races.

---

## Standard Stack

### Core (already in requirements.txt — no new installs needed for most)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SQLAlchemy asyncio | 2.0.38 (installed) | ORM + async queries, TSTZRANGE column type, ExcludeConstraint | Already project standard; 2.0 has native Range type support |
| asyncpg | 0.30.0 (installed) | PostgreSQL async driver, supports range types | Already project standard |
| Alembic | 1.14.1 (installed) | Schema migrations for new tables | Already project standard |
| Python zoneinfo | stdlib (Python 3.12) | IANA timezone support, DST-safe arithmetic | Built-in; pytz is deprecated pattern for Python 3.9+ |
| httpx | 0.28.1 (installed) | Async HTTP calls to ORS API | Already in requirements.txt; async-native; do NOT use openrouteservice-py (sync only, blocks event loop) |
| pytest-asyncio | 0.25.3 (installed) | Async test support for concurrent booking tests | Already project standard |

### New Additions

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tzdata | latest | IANA timezone data for cross-platform support | Add to requirements.txt — Python 3.12's zoneinfo needs tzdata on systems without /usr/share/zoneinfo (common in Docker) |

**Installation:**
```bash
# Add to requirements.txt:
tzdata
```

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| httpx (async) | openrouteservice-py | openrouteservice-py uses synchronous `requests` internally — blocks asyncpg event loop; httpx has async client support |
| zoneinfo (stdlib) | pytz | pytz is deprecated for Python 3.9+; zoneinfo is the correct modern approach |
| PostgreSQL travel cache | Redis | Redis requires a new infrastructure dependency; PostgreSQL cache table is simpler for 2000 req/day quota |
| TSTZRANGE column | two datetime columns | Two-column approach requires application-level range logic; TSTZRANGE with GIST gives database-enforced atomicity |

---

## Architecture Patterns

### Recommended Project Structure

```
backend/
├── app/
│   └── features/
│       └── scheduling/              # New domain
│           ├── __init__.py
│           ├── models.py            # ORM models: Booking, ContractorWeeklySchedule, ContractorDateOverride, JobSite, TravelTimeCache
│           ├── schemas.py           # Pydantic: AvailabilityRequest, FreeWindow, BookingCreate, BookingResponse, SchedulingConfig
│           ├── service.py           # SchedulingService(TenantScopedService): get_available_slots, book_slot, suggest_dates
│           ├── repository.py        # SchedulingRepository(TenantScopedRepository): booking queries, lock acquisition
│           ├── router.py            # CRUDRouter subclass + custom endpoints for availability/conflict check
│           └── travel/
│               ├── __init__.py
│               ├── provider.py      # Abstract TravelTimeProvider interface
│               └── ors_provider.py  # OpenRouteServiceProvider(TravelTimeProvider) using httpx.AsyncClient
├── migrations/
│   └── versions/
│       ├── 0007_scheduling_tables.py    # bookings, contractor_weekly_schedule, contractor_date_overrides, job_sites
│       ├── 0008_travel_time_cache.py    # travel_time_cache table
│       └── 0009_scheduling_config.py    # JSONB column on companies, home_address columns on users
└── tests/
    └── scheduling/
        ├── conftest.py              # Scheduling fixtures extending base conftest
        ├── test_availability.py     # Pure logic tests (mocked DB)
        ├── test_multiday.py         # Multi-day spanning tests
        ├── test_conflicts.py        # GIST constraint + concurrent booking tests
        └── test_travel_time.py      # ORS integration with record/replay fixtures
```

### Pattern 1: GIST Exclusion Constraint on bookings table

**What:** Database-level constraint that rejects INSERT/UPDATE if the new `(contractor_id, time_range)` overlaps an existing row for the same contractor.

**When to use:** Every booking INSERT goes through this constraint automatically. No application code path can bypass it.

**Migration SQL (use raw op.execute — Alembic autogenerate is unreliable with ExcludeConstraint + TSTZRANGE functions):**
```python
# Source: PostgreSQL docs https://www.postgresql.org/docs/current/rangetypes.html
# btree_gist already installed in migration 0001

op.execute(text("""
    CREATE TABLE bookings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        company_id UUID NOT NULL REFERENCES companies(id),
        contractor_id UUID NOT NULL REFERENCES users(id),
        job_id UUID NOT NULL,
        time_range TSTZRANGE NOT NULL,
        day_index INTEGER,         -- NULL for single-day; 0-based for multi-day
        notes TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        deleted_at TIMESTAMPTZ,
        EXCLUDE USING GIST (
            contractor_id WITH =,
            time_range WITH &&
        ) WHERE (deleted_at IS NULL)
    )
"""))
```

**Key details:**
- `WHERE (deleted_at IS NULL)` — partial index excludes soft-deleted bookings from conflict checks
- `company_id` NOT in the GIST constraint — the RLS policy handles tenant scoping; the GIST prevents within-tenant overlaps
- `btree_gist` extension required for mixing scalar (`contractor_id UUID WITH =`) and range (`time_range WITH &&`) in one constraint

**SQLAlchemy ORM model using TSTZRANGE:**
```python
# Source: SQLAlchemy 2.0 docs — Range types with asyncpg
from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import TSTZRANGE, ExcludeConstraint, Range
from sqlalchemy.orm import Mapped, mapped_column
from app.core.base_models import TenantScopedModel
import uuid
from datetime import datetime

class Booking(TenantScopedModel):
    __tablename__ = "bookings"

    contractor_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    job_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    time_range: Mapped[Range[datetime]] = mapped_column(TSTZRANGE, nullable=False)
    day_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        ExcludeConstraint(
            ("contractor_id", "="),
            ("time_range", "&&"),
            name="exclude_overlapping_bookings",
            where="deleted_at IS NULL",
        ),
    )
```

**Note:** Declare the GIST constraint in raw migration SQL (op.execute) rather than relying on Alembic autogenerate — there are known bugs with ExcludeConstraint + function expressions in autogenerate. The ORM model's `__table_args__` ExcludeConstraint is for documentation/metadata only; the actual constraint comes from the migration.

### Pattern 2: SELECT FOR UPDATE per-contractor row lock

**What:** Acquires an exclusive row-level lock on a contractor-specific scheduling lock row before performing the availability check + insert. Prevents two concurrent requests from both passing the availability check before either commits.

**Why needed:** Even with the GIST constraint, without application-level locking, two concurrent transactions can both read "slot is free", both compute "no conflict", then one succeeds and one fails with a GIST violation. The SELECT FOR UPDATE serializes them so only one sees the slot as free.

**Implementation:**
```python
# Source: SQLAlchemy 2.0 async docs + verified pattern
from sqlalchemy import select, text

async def _acquire_contractor_lock(self, contractor_id: uuid.UUID) -> None:
    """Acquire exclusive row lock on contractor schedule row.

    Lock is released automatically when the enclosing transaction commits/rolls back.
    Uses contractor_schedule_locks table — one row per contractor, never deleted.
    """
    await self.db.execute(
        select(ContractorScheduleLock)
        .where(ContractorScheduleLock.contractor_id == contractor_id)
        .with_for_update()
    )
```

**ContractorScheduleLock table:** A lightweight anchor table with one row per contractor. The SELECT FOR UPDATE locks this row, serializing all booking attempts for that contractor without blocking other contractors.

```sql
CREATE TABLE contractor_schedule_locks (
    contractor_id UUID PRIMARY KEY REFERENCES users(id),
    company_id UUID NOT NULL REFERENCES companies(id)
);
```

**Alternative: PostgreSQL advisory lock** — `pg_try_advisory_xact_lock(hashtext(contractor_id::text))` is lighter (no table row required) but less debuggable and requires careful hash collision management. Prefer the table-based approach for observability.

### Pattern 3: Availability Computation Algorithm

**What:** Computes free time windows for a contractor on a given date by subtracting blocked intervals from the working-hour template.

**Algorithm (pure Python, no DB queries):**
```python
# Interval subtraction pattern — verified approach for availability computation
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

def compute_free_windows(
    working_blocks: list[tuple[datetime, datetime]],  # Contractor's working time blocks (UTC)
    blocked_intervals: list[tuple[datetime, datetime]],  # Bookings + travel time buffers (UTC)
    min_duration_minutes: int,
    buffer_minutes: int,
) -> list[FreeWindow]:
    """
    Subtract blocked intervals from working blocks.
    Returns free windows >= min_duration_minutes.

    Algorithm:
    1. Expand each blocked interval by buffer_minutes on each side
    2. Merge overlapping blocked intervals (sort by start, sweep)
    3. For each working block, subtract all overlapping blocked intervals
    4. Return remaining gaps >= min_duration_minutes
    """
    # Expand blocks by buffer
    expanded = [
        (start - timedelta(minutes=buffer_minutes),
         end + timedelta(minutes=buffer_minutes))
        for start, end in blocked_intervals
    ]
    # Merge overlapping
    expanded.sort(key=lambda x: x[0])
    merged = []
    for start, end in expanded:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append([start, end])
    # Subtract from working blocks
    free_windows = []
    for w_start, w_end in working_blocks:
        cursor = w_start
        for b_start, b_end in merged:
            if b_start >= w_end:
                break
            if b_end <= cursor:
                continue
            gap_start = cursor
            gap_end = min(b_start, w_end)
            if gap_end - gap_start >= timedelta(minutes=min_duration_minutes):
                free_windows.append(FreeWindow(start=gap_start, end=gap_end))
            cursor = max(cursor, b_end)
        # Trailing window after last block
        if w_end - cursor >= timedelta(minutes=min_duration_minutes):
            free_windows.append(FreeWindow(start=cursor, end=w_end))
    return free_windows
```

**Timezone handling:** All datetimes stored and computed in UTC. Convert to contractor's local timezone only for display and for interpreting the weekly template (e.g., "Mon 7am" means 7am in the contractor's ZoneInfo timezone):
```python
from zoneinfo import ZoneInfo

contractor_tz = ZoneInfo("America/Vancouver")  # Stored as IANA string on user record
# Convert local "7am Monday" to UTC for storage
local_start = datetime(2026, 3, 9, 7, 0, 0, tzinfo=contractor_tz)
utc_start = local_start.astimezone(ZoneInfo("UTC"))
```

### Pattern 4: Travel Time Provider Interface

**What:** Abstract interface that decouples the scheduling engine from any specific mapping API.

```python
from abc import ABC, abstractmethod

class TravelTimeProvider(ABC):
    """Abstract travel time provider interface."""

    @abstractmethod
    async def get_travel_seconds(
        self,
        origin_lat: float, origin_lng: float,
        dest_lat: float, dest_lng: float,
    ) -> int:
        """Return driving travel time in seconds between two coordinates."""
        ...


class OpenRouteServiceProvider(TravelTimeProvider):
    """ORS implementation using httpx.AsyncClient.

    Does NOT use openrouteservice-py — that library uses synchronous requests,
    which blocks the asyncpg event loop.
    """

    def __init__(self, api_key: str, client: httpx.AsyncClient) -> None:
        self._api_key = api_key
        self._client = client

    async def get_travel_seconds(self, origin_lat, origin_lng, dest_lat, dest_lng) -> int:
        response = await self._client.get(
            "https://api.openrouteservice.org/v2/directions/driving-car",
            params={
                "api_key": self._api_key,
                "start": f"{origin_lng},{origin_lat}",
                "end": f"{dest_lng},{dest_lat}",
            },
        )
        response.raise_for_status()
        data = response.json()
        return data["features"][0]["properties"]["segments"][0]["duration"]
```

**ORS API note:** The directions endpoint uses `lng,lat` order (GeoJSON standard — longitude first). The response duration is in seconds. Free tier: 2000 Directions requests/day, 40/minute.

### Pattern 5: Travel Time Cache with PostgreSQL

**What:** Cache ORS results in a PostgreSQL table to avoid hitting the 2000/day quota. TTL is 30 days. Cache key uses coordinates rounded to 3 decimal places (~111m precision).

```python
import math

def _round_coord(value: float, decimals: int = 3) -> float:
    """Round coordinate for cache key (~111m precision at 3 decimals)."""
    return round(value, decimals)

def _cache_key(lat1, lng1, lat2, lng2, decimals=3) -> tuple[float, float, float, float]:
    """Bidirectional cache key — (A,B) == (B,A) by ordering."""
    p1 = (_round_coord(lat1, decimals), _round_coord(lng1, decimals))
    p2 = (_round_coord(lat2, decimals), _round_coord(lng2, decimals))
    # Sort to make A->B == B->A
    if p1 > p2:
        p1, p2 = p2, p1
    return (*p1, *p2)
```

```sql
CREATE TABLE travel_time_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    lat1 NUMERIC(9,6) NOT NULL,
    lng1 NUMERIC(9,6) NOT NULL,
    lat2 NUMERIC(9,6) NOT NULL,
    lng2 NUMERIC(9,6) NOT NULL,
    duration_seconds INTEGER NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, lat1, lng1, lat2, lng2)
);
CREATE INDEX idx_travel_cache_company ON travel_time_cache (company_id);
```

Cache lookup: Query by `(company_id, lat1, lng1, lat2, lng2)` with both orderings. If result exists and `fetched_at > now() - interval '30 days'`, use it. If expired: use it as fallback AND refresh asynchronously. If not found at all: call ORS, store result, return duration.

### Pattern 6: SchedulingConfig JSONB on companies

**What:** Company-wide scheduling defaults stored in a typed JSONB column. Pydantic model validates on read/write.

```python
# SQLAlchemy TypeDecorator for JSONB-backed Pydantic model
from sqlalchemy import TypeDecorator, JSON
from pydantic import BaseModel, Field

class SchedulingConfig(BaseModel):
    default_min_job_duration_minutes: int = Field(default=30, ge=5)
    default_buffer_minutes: int = Field(default=15, ge=0)
    default_travel_time_minutes: int = Field(default=30, ge=0)  # Fallback when ORS fails
    travel_margin_percent: float = Field(default=20.0, ge=0.0, le=100.0)
    default_working_hours: dict = Field(default_factory=dict)  # day_of_week -> [{start, end}]

class PydanticJSONB(TypeDecorator):
    """SQLAlchemy type that serializes/deserializes a Pydantic model from JSONB."""
    impl = JSON
    cache_ok = True

    def __init__(self, pydantic_type: type[BaseModel]) -> None:
        super().__init__()
        self._pydantic_type = pydantic_type

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if isinstance(value, self._pydantic_type):
            return value.model_dump(mode="json")
        return value

    def process_result_value(self, value, dialect):
        if value is None:
            return self._pydantic_type()  # Return default config
        return self._pydantic_type.model_validate(value)
```

### Pattern 7: Multi-Day All-or-Nothing Booking

**What:** Creating a multi-day job atomically — all booking records succeed or all fail.

**Algorithm:**
```python
async def book_multiday_job(
    self,
    contractor_id: uuid.UUID,
    job_id: uuid.UUID,
    day_blocks: list[DayBlock],  # [{date, start_time, end_time}]
) -> list[Booking]:
    """
    1. Acquire contractor lock (SELECT FOR UPDATE)
    2. For each day_block, convert local time to UTC tstzrange
    3. Check all day_blocks for conflicts (SELECT existing bookings in range)
    4. If ANY conflict found, raise ConflictError with details
    5. If all clear, INSERT all booking records in single transaction
    6. GIST constraint provides final safety net
    """
    await self._acquire_contractor_lock(contractor_id)

    # Convert day blocks to UTC ranges
    utc_ranges = [self._to_utc_range(block, contractor_tz) for block in day_blocks]

    # Pre-check all days for conflicts
    conflicts = await self.repository.find_conflicts(contractor_id, utc_ranges)
    if conflicts:
        raise BookingConflictError(conflicts)

    # Insert all — GIST constraint catches any race conditions that slipped through
    bookings = []
    for i, (block, utc_range) in enumerate(zip(day_blocks, utc_ranges)):
        booking = Booking(
            contractor_id=contractor_id,
            job_id=job_id,
            time_range=Range(utc_range[0], utc_range[1]),
            day_index=i,
            company_id=self._require_tenant_id(),
        )
        bookings.append(await self.repository.create(booking))
    return bookings
```

### Anti-Patterns to Avoid

- **Using `openrouteservice-py` directly**: Its `Client` uses synchronous `requests`. Calling it inside an async FastAPI handler blocks the asyncpg event loop. Use `httpx.AsyncClient` instead.
- **Checking availability then inserting without a lock**: The time between checking and inserting creates a TOCTOU race. Always use SELECT FOR UPDATE before the check.
- **Storing local times in the database**: Always store UTC. Convert to local only for display and for interpreting weekly templates.
- **Applying RLS to `companies` table**: The companies table is the tenant root — never apply RLS to it. (Already established pattern.)
- **Placing `company_id` in the GIST constraint**: The GIST constraint should only contain `contractor_id` (equality) and `time_range` (overlap). RLS handles tenant scoping automatically.
- **Using pytz instead of zoneinfo**: Python 3.12 project should use `zoneinfo.ZoneInfo`. pytz's `localize()` pattern is outdated and error-prone.
- **autogenerate for ExcludeConstraint migrations**: Alembic autogenerate has known bugs with `ExcludeConstraint` + function expressions. Write migration SQL manually using `op.execute(text(...))`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Range overlap detection | Custom SQL WHERE with BETWEEN | PostgreSQL TSTZRANGE + `&&` operator + GIST | Handles half-open intervals, DST gaps, and concurrent inserts correctly |
| Concurrent booking protection | Application-level flag check | SELECT FOR UPDATE + GIST constraint | Two-phase protection; flag check has TOCTOU race |
| Timezone database | Hard-coded UTC offsets | `zoneinfo.ZoneInfo` + `tzdata` package | IANA database handles DST transitions, historical changes |
| HTTP client for ORS | openrouteservice-py | `httpx.AsyncClient` | openrouteservice-py is sync-only (blocks event loop) |
| Interval arithmetic for availability | Custom overlap detection | Pure Python interval subtraction algorithm (see Pattern 3) | The algorithm is simple enough to hand-roll correctly; use it as documented |
| Travel time cache | Redis | PostgreSQL table with TTL column | Already have PostgreSQL; Redis adds infrastructure complexity for 2000 req/day |

**Key insight:** The GIST constraint + btree_gist is the most underused PostgreSQL feature in scheduling systems. It moves conflict detection from "application checks that can race" to "database enforces atomically." At 2000 ORS requests/day limit, the cache table prevents quota exhaustion within a single busy day.

---

## Common Pitfalls

### Pitfall 1: GIST Constraint Missing `WHERE (deleted_at IS NULL)`
**What goes wrong:** Soft-deleted bookings still block future bookings for the same time range. A cancelled job makes the slot permanently unavailable.
**Why it happens:** Exclusion constraints by default apply to all rows including logically-deleted ones.
**How to avoid:** Always include `WHERE (deleted_at IS NULL)` as a partial constraint predicate in the migration SQL.
**Warning signs:** Tests show "conflict" for a time slot where the only booking is soft-deleted.

### Pitfall 2: Alembic ExcludeConstraint Autogenerate Failures
**What goes wrong:** `alembic revision --autogenerate` generates broken migration code for ExcludeConstraint with TSTZRANGE, causing `ConstraintColumnNotFoundError` on upgrade.
**Why it happens:** Known Alembic issue (GitHub #1184, #1230, #958) — autogenerate doesn't handle function-based expressions in ExcludeConstraint correctly.
**How to avoid:** Write migration SQL manually using `op.execute(text("CREATE TABLE ... EXCLUDE USING GIST ..."))`. Keep ORM model's `__table_args__` ExcludeConstraint for metadata/documentation only.
**Warning signs:** Autogenerated migration references columns named `tstzrange(...)` — that's the bug.

### Pitfall 3: openrouteservice-py Blocking Asyncpg
**What goes wrong:** Service hangs under load; all concurrent requests share one event loop thread that's blocked by a synchronous HTTP call.
**Why it happens:** `openrouteservice-py` uses `requests` (synchronous) internally. Calling it in an `async def` function doesn't make it async.
**How to avoid:** Use `httpx.AsyncClient` directly for ORS API calls. Already in requirements.txt.
**Warning signs:** Travel time fetches take unusually long; event loop stall detectable with `asyncio.get_event_loop().set_debug(True)`.

### Pitfall 4: ORS Coordinate Order (lng, lat vs lat, lng)
**What goes wrong:** Routes return wrong directions or API returns 400 errors.
**Why it happens:** ORS directions API uses GeoJSON coordinate order: `longitude, latitude`. Python convention (and most geocoding results) is `latitude, longitude`.
**How to avoid:** Always pass `f"{lng},{lat}"` to ORS `start` and `end` parameters. Add a unit test that validates the coordinate order with a known city pair.
**Warning signs:** Routes pointing in wrong direction; distance wildly off expected value.

### Pitfall 5: DST Boundary Booking Corruption
**What goes wrong:** A booking crossing a DST transition stores an incorrect duration, or a weekly template generates wrong UTC times on the DST transition day.
**Why it happens:** Naive datetime arithmetic (adding hours to local time) doesn't account for the 1-hour DST jump.
**How to avoid:** Always convert local time → UTC before arithmetic. Use `zoneinfo.ZoneInfo` (not fixed offsets). The `datetime.astimezone()` method handles DST correctly when ZoneInfo is attached.
**Warning signs:** Tests that run in non-UTC timezone environments show different results than UTC environments.

### Pitfall 6: TSTZRANGE Half-Open Interval Edge Cases
**What goes wrong:** A booking ending at 5pm doesn't conflict with a booking starting at 5pm, but does conflict with one starting at 4:59pm — unexpected `&&` behavior.
**Why it happens:** PostgreSQL ranges are half-open by default: `[start, end)` means start is included, end is excluded. Two adjacent ranges `[1pm, 5pm)` and `[5pm, 8pm)` do NOT overlap (`&&` returns false).
**How to avoid:** Use the default half-open interval notation consistently. This is correct behavior for scheduling (end of one job is start of next — no buffer). Buffer time should be added to the blocked interval before inserting, not to the range bounds.
**Warning signs:** Buffer time between jobs is added to `time_range` end rather than as a separate blocked interval.

### Pitfall 7: Concurrent Test Isolation with NullPool
**What goes wrong:** Concurrent booking tests (asyncio.gather) with NullPool create separate connections that each get their own transaction — this is correct for testing the GIST constraint but requires each concurrent path to use a DIFFERENT session.
**Why it happens:** `SELECT FOR UPDATE` only serializes within a connection pool. For concurrent tests, each booking attempt MUST use a separate DB session (separate connection) to simulate real concurrent requests.
**How to avoid:** In concurrent test, create multiple `AsyncClient` instances each making independent HTTP requests (not direct service calls). The HTTP layer creates a new `get_db` session per request automatically.
**Warning signs:** Concurrent booking test always shows "both succeed" even though they should conflict — the concurrent calls share a session and serialize automatically.

---

## Code Examples

Verified patterns from official sources:

### TSTZRANGE Range value insertion (SQLAlchemy 2.0 + asyncpg)
```python
# Source: SQLAlchemy 2.0 PostgreSQL dialect docs
from sqlalchemy.dialects.postgresql import Range
from datetime import datetime, timezone

# Creating a Range value for TSTZRANGE column
start = datetime(2026, 3, 9, 9, 0, 0, tzinfo=timezone.utc)
end = datetime(2026, 3, 9, 17, 0, 0, tzinfo=timezone.utc)
time_range = Range(start, end)  # Half-open [start, end) by default

booking = Booking(
    contractor_id=contractor_id,
    job_id=job_id,
    time_range=time_range,
    company_id=company_id,
)
db.add(booking)
await db.flush()
```

### SELECT FOR UPDATE in async SQLAlchemy
```python
# Source: SQLAlchemy 2.0 ORM querying docs — with_for_update() in async context
from sqlalchemy import select

async def _acquire_contractor_lock(self, contractor_id: uuid.UUID) -> None:
    result = await self.db.execute(
        select(ContractorScheduleLock)
        .where(ContractorScheduleLock.contractor_id == contractor_id)
        .with_for_update()
    )
    lock_row = result.scalar_one_or_none()
    if lock_row is None:
        # First booking for this contractor — create the lock row
        lock_row = ContractorScheduleLock(contractor_id=contractor_id, company_id=...)
        self.db.add(lock_row)
        await self.db.flush()
        # Re-acquire the lock on the newly created row
        await self.db.execute(
            select(ContractorScheduleLock)
            .where(ContractorScheduleLock.contractor_id == contractor_id)
            .with_for_update()
        )
```

### ORS Travel Time via httpx.AsyncClient
```python
# Source: ORS API docs + httpx async docs
import httpx

async def get_travel_seconds(
    self,
    origin_lat: float, origin_lng: float,
    dest_lat: float, dest_lng: float,
) -> int:
    # ORS uses GeoJSON order: lng,lat (NOT lat,lng)
    response = await self._client.get(
        "https://api.openrouteservice.org/v2/directions/driving-car",
        params={
            "api_key": self._api_key,
            "start": f"{origin_lng},{origin_lat}",   # lng first!
            "end": f"{dest_lng},{dest_lat}",
        },
        timeout=10.0,
    )
    response.raise_for_status()
    data = response.json()
    # Response: features[0].properties.segments[0].duration (seconds as float)
    return int(data["features"][0]["properties"]["segments"][0]["duration"])
```

### Timezone-aware weekly template to UTC
```python
# Source: Python stdlib zoneinfo docs
from zoneinfo import ZoneInfo
from datetime import datetime, date

def template_block_to_utc(
    target_date: date,
    start_hour: int,
    start_minute: int,
    end_hour: int,
    end_minute: int,
    contractor_tz_name: str,  # e.g., "America/Vancouver"
) -> tuple[datetime, datetime]:
    """Convert weekly template block to UTC datetimes for a specific date."""
    tz = ZoneInfo(contractor_tz_name)
    local_start = datetime(target_date.year, target_date.month, target_date.day,
                           start_hour, start_minute, tzinfo=tz)
    local_end = datetime(target_date.year, target_date.month, target_date.day,
                         end_hour, end_minute, tzinfo=tz)
    # .astimezone() correctly handles DST transitions
    return local_start.astimezone(ZoneInfo("UTC")), local_end.astimezone(ZoneInfo("UTC"))
```

### Concurrent booking test pattern
```python
# Source: pytest-asyncio docs + asyncio.gather pattern
import asyncio
import pytest

@pytest.mark.asyncio
async def test_concurrent_booking_exactly_one_succeeds(async_client, seed_contractor):
    """Two simultaneous booking requests for same slot — exactly one must succeed."""
    booking_payload = {
        "contractor_id": str(seed_contractor["id"]),
        "start": "2026-03-09T09:00:00Z",
        "end": "2026-03-09T11:00:00Z",
    }

    # Use separate HTTP clients to get separate DB sessions (NOT same session)
    async def attempt_booking(client):
        return await client.post("/api/v1/scheduling/bookings", json=booking_payload)

    results = await asyncio.gather(
        attempt_booking(client_instance_1),
        attempt_booking(client_instance_2),
        return_exceptions=True,
    )

    statuses = [r.status_code for r in results if hasattr(r, "status_code")]
    successes = [s for s in statuses if s == 201]
    conflicts = [s for s in statuses if s == 409]

    assert len(successes) == 1, f"Expected exactly 1 success, got {len(successes)}"
    assert len(conflicts) == 1, f"Expected exactly 1 conflict, got {len(conflicts)}"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| pytz for timezone handling | `zoneinfo` (stdlib) + `tzdata` | Python 3.9 (2020), recommended by 3.12 | No external dependency needed for timezone support |
| openrouteservice-py (sync) | httpx.AsyncClient directly | Async FastAPI became standard ~2022 | Prevents event loop blocking; keeps async chain unbroken |
| Two datetime columns for ranges | TSTZRANGE + GIST | PostgreSQL 9.2+ (ranges); widely adopted 2020+ | Atomic constraint enforcement; no application-level race conditions |
| Redis for caching | PostgreSQL table with TTL | Pattern preference when Redis not already in stack | Reduces infrastructure complexity for low-volume caching |

**Deprecated/outdated:**
- `openrouteservice-py` for async FastAPI: Library uses `requests` (sync) — blocks event loop
- `pytz.localize()` and `normalize()`: Use `datetime(..., tzinfo=ZoneInfo(...))` and `astimezone()` instead

---

## Open Questions

1. **ContractorScheduleLock table initialization**
   - What we know: The SELECT FOR UPDATE approach requires a pre-existing row per contractor to lock
   - What's unclear: Should the row be created when the contractor is created (migration trigger or application logic)?
   - Recommendation: Create the lock row as part of the contractor onboarding flow (when a contractor user role is assigned). Also handle the "first booking" case defensively in the service.

2. **ORS geocoding vs. standalone Pelias**
   - What we know: ORS provides geocoding via the Pelias engine; the same API key works for both directions and geocoding
   - What's unclear: Whether ORS geocoding quota (separate from Directions) is sufficient for the address-entry-time geocoding requirement
   - Recommendation: Use ORS geocoding endpoint (`/geocode/search`) with the same API key. Quota is separate from directions. If quota becomes an issue in later phases, swap to Nominatim (free, no key required).

3. **TSTZRANGE in existing Alembic migration (autogenerate safe list)**
   - What we know: Alembic autogenerate has bugs with ExcludeConstraint + TSTZRANGE
   - What's unclear: Whether include_schemas or specific table exclusions need to be added to env.py to prevent autogenerate from attempting to diff ExcludeConstraints
   - Recommendation: Write all scheduling migrations manually (op.execute raw SQL for table creation); add a comment in env.py warning future developers to avoid autogenerating scheduling table migrations.

---

## Sources

### Primary (HIGH confidence)
- PostgreSQL official docs — Range types and EXCLUDE USING GIST: https://www.postgresql.org/docs/current/rangetypes.html
- SQLAlchemy 2.0 PostgreSQL dialect — ExcludeConstraint, TSTZRANGE, Range type: https://docs.sqlalchemy.org/en/20/dialects/postgresql.html
- SQLAlchemy 2.0 asyncio docs — AsyncSession, with_for_update(): https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html
- Python stdlib zoneinfo docs: https://docs.python.org/3/library/zoneinfo.html
- OpenRouteService Python quickstart — directions() method, response structure: https://openrouteservice-py.readthedocs.io/en/latest/
- Existing project conftest.py — NullPool pattern, test session setup: verified from codebase
- Existing migration 0001 — btree_gist already installed: verified from codebase

### Secondary (MEDIUM confidence)
- Alembic GitHub issues #1184, #1230, #958 — ExcludeConstraint autogenerate bugs: confirmed by multiple issue threads
- OpenRouteService free tier: 2000 Directions requests/day, 40/minute — from openrouteservice.org/services/ (confirmed by multiple sources)
- httpx vs openrouteservice-py — sync blocking issue: https://oxylabs.io/blog/httpx-vs-requests-vs-aiohttp (verified openrouteservice-py uses requests)

### Tertiary (LOW confidence — flag for validation)
- ORS GeoJSON coordinate order (lng,lat): Confirmed from quickstart example but validate with a real API call in first travel time test
- 30-day travel cache TTL adequacy: Based on decision in CONTEXT.md; actual ORS data freshness not independently verified

---

## Metadata

**Confidence breakdown:**
- Standard stack (PostgreSQL GIST, SQLAlchemy Range, httpx): HIGH — verified from official docs and existing codebase
- Architecture (interval algorithm, SELECT FOR UPDATE pattern, travel provider interface): HIGH — standard patterns with verified SQL/Python syntax
- Pitfalls (Alembic ExcludeConstraint bug, ORS sync blocking, coordinate order): HIGH for Alembic bug (multiple GitHub issues confirmed); MEDIUM for ORS details (need first integration test to confirm)
- Testing patterns: HIGH — consistent with existing conftest.py patterns in codebase

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable domain; ORS API terms may change — verify quota before launch)
