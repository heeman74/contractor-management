"""Pydantic schemas for the scheduling domain.

Schemas used across the scheduling API surface:
  - SchedulingConfig      — JSONB-backed company scheduling configuration
  - TimeBlock             — a single time range (start/end times)
  - FreeWindow            — available time window returned by availability engine
  - BlockedInterval       — blocked time interval with reason classification
  - AvailabilityRequest   — query parameters for the availability endpoint
  - AvailabilityResponse  — per-contractor availability result
  - BookingCreate         — single-day booking creation payload
  - MultiDayBookingCreate — multi-day booking with per-day time blocks
  - DayBlock              — one day's time block in a multi-day booking
  - BookingResponse       — booking read response (inherits TenantResponseSchema)
  - ConflictDetail        — conflict information returned on booking failure
  - DateSuggestion        — suggested date(s) for multi-day job scheduling
  - WeeklyScheduleCreate  — create/replace a contractor's weekly schedule
  - DateOverrideCreate    — create a date-specific schedule override

All response schemas inherit from BaseResponseSchema or TenantResponseSchema per
CLAUDE.md convention. Input schemas inherit from pydantic BaseModel directly.
"""

import uuid
from datetime import date, datetime, time

from pydantic import BaseModel, Field

from app.core.base_schemas import TenantResponseSchema


class SchedulingConfig(BaseModel):
    """Company-wide scheduling configuration stored as JSONB on the companies table.

    All fields have sensible defaults so an empty JSONB ({}) produces a valid config.
    Pydantic fills in defaults on read; model_dump(mode='json') serializes for storage.

    Fields:
    - default_min_job_duration_minutes: Minimum job length. Jobs shorter than this
      are rejected at creation time. Admin-configurable per company.
    - default_buffer_minutes: Gap inserted between consecutive jobs for setup/cleanup.
      Applied on both sides of each booking when computing free windows.
    - default_travel_time_minutes: Fallback travel time used when ORS is unavailable
      or the cache has no entry and the API quota is exhausted.
    - travel_margin_percent: Safety margin added on top of raw ORS travel time
      (e.g., 20.0 means multiply ORS seconds by 1.20).
    - default_working_hours: Company-level default weekly schedule as a dict mapping
      day_of_week (0=Mon..6=Sun) to list of {start, end} time blocks. Contractors
      without a personal weekly schedule inherit this configuration.
    """

    default_min_job_duration_minutes: int = Field(default=30, ge=5)
    default_buffer_minutes: int = Field(default=15, ge=0)
    default_travel_time_minutes: int = Field(default=30, ge=0)
    travel_margin_percent: float = Field(default=20.0, ge=0.0, le=100.0)
    # day_of_week (0-6 as string key) -> list of {start: "HH:MM", end: "HH:MM"} blocks
    default_working_hours: dict[str, list[dict[str, str]]] = Field(default_factory=dict)


class TimeBlock(BaseModel):
    """A single time range within a day (no date component).

    Used for:
    - Defining blocks within a ContractorWeeklySchedule (weekly template)
    - Defining blocks within a ContractorDateOverride (date-specific override)
    - The 'blocks' field in WeeklyScheduleCreate and DateOverrideCreate
    """

    start_time: time
    end_time: time


class FreeWindow(BaseModel):
    """An available time window returned by the availability engine.

    start and end are UTC datetimes. The window is a continuous free period
    that satisfies the minimum job duration constraint after subtracting all
    blocked intervals (bookings, travel buffers, outside-working-hours).

    reason_before documents why a gap exists before this window starts
    (e.g., "outside_working_hours" if this window begins at contractor start-of-day,
    "existing_job" if the previous block was a booking). Used by the UI to explain
    the schedule layout to the dispatcher.
    """

    start: datetime
    end: datetime
    reason_before: str | None = None


class BlockedInterval(BaseModel):
    """A blocked time interval within a contractor's day.

    Returned alongside free windows so the UI can render a full day view
    showing both available and blocked time.

    reason values:
    - "existing_job"           — a committed booking occupies this slot
    - "travel_buffer"          — travel time to/from next/previous job
    - "outside_working_hours"  — before start or after end of working day
    - "time_off"               — date override marks this period as unavailable
    """

    start: datetime
    end: datetime
    reason: str


class AvailabilityRequest(BaseModel):
    """Query parameters for the contractor availability endpoint.

    Either contractor_ids OR trade_type must be provided (or both).
    If trade_type is given, all contractors with that trade are included.

    job_site_id is optional — if provided, results are sorted by proximity
    (nearest contractor home base to job site first).
    """

    contractor_ids: list[uuid.UUID] | None = None
    trade_type: str | None = None
    date: date
    job_site_id: uuid.UUID | None = None


class AvailabilityResponse(BaseModel):
    """Availability result for a single contractor on the requested date.

    free_windows and blocked_intervals together form a complete timeline
    for the contractor's day. The UI can render them as a Gantt-style view.

    distance_km is populated when job_site_id was provided in the request.
    None when the contractor has no home_latitude/home_longitude set.
    """

    contractor_id: uuid.UUID
    contractor_name: str
    date: date
    free_windows: list[FreeWindow]
    blocked_intervals: list[BlockedInterval]
    distance_km: float | None = None


class DayBlock(BaseModel):
    """A single day's time block in a multi-day booking.

    Used in MultiDayBookingCreate.day_blocks to specify the exact start and end
    times for each individual day of the multi-day job. Days can be non-consecutive.
    """

    date: date
    start_time: time
    end_time: time


class BookingCreate(BaseModel):
    """Payload for creating a single-day booking.

    start and end are UTC datetimes forming the booking's time range.
    The booking service converts them to a TSTZRANGE before insert.
    """

    contractor_id: uuid.UUID
    job_id: uuid.UUID
    job_site_id: uuid.UUID | None = None
    start: datetime
    end: datetime
    notes: str | None = None


class MultiDayBookingCreate(BaseModel):
    """Payload for creating a multi-day booking (all-or-nothing).

    day_blocks defines each day's schedule independently, allowing non-consecutive
    dates and different hours per day. The booking service checks ALL days for
    conflicts before inserting any records. If any day conflicts, all fail.
    """

    contractor_id: uuid.UUID
    job_id: uuid.UUID
    job_site_id: uuid.UUID | None = None
    day_blocks: list[DayBlock] = Field(min_length=2)
    notes: str | None = None


class BookingResponse(TenantResponseSchema):
    """Response schema for a single booking record.

    Inherits id, version, created_at, updated_at, deleted_at, company_id
    from TenantResponseSchema.

    time_range_start and time_range_end are extracted from the TSTZRANGE column
    (SQLAlchemy's Range type provides .lower and .upper attributes).
    day_index and parent_booking_id are non-None only for multi-day booking records.
    """

    contractor_id: uuid.UUID
    job_id: uuid.UUID
    job_site_id: uuid.UUID | None = None
    time_range_start: datetime
    time_range_end: datetime
    day_index: int | None = None
    parent_booking_id: uuid.UUID | None = None
    notes: str | None = None


class ConflictDetail(BaseModel):
    """Details about a conflicting booking, returned when a booking attempt fails (409).

    Provides enough information for the dispatcher to understand which job conflicts
    and to offer rescheduling options.
    """

    booking_id: uuid.UUID
    contractor_id: uuid.UUID
    contractor_name: str | None = None
    time_range_start: datetime
    time_range_end: datetime
    job_id: uuid.UUID


class DateSuggestion(BaseModel):
    """Suggested date combination for a multi-day job.

    The engine returns a list of DateSuggestion objects, each representing a
    candidate set of dates on which the contractor has sufficient availability.
    is_consecutive is True when all dates are adjacent (no gaps) — preferred
    for jobs that benefit from continuity.
    """

    dates: list[date]
    is_consecutive: bool


class WeeklyScheduleCreate(BaseModel):
    """Create or replace a contractor's weekly schedule for a specific day.

    blocks replaces all existing blocks for (contractor_id, day_of_week) atomically.
    An empty blocks list effectively clears the contractor's schedule for that day,
    meaning the contractor is treated as having no working hours on that day of the week.
    """

    contractor_id: uuid.UUID
    day_of_week: int = Field(ge=0, le=6)
    blocks: list[TimeBlock]


class DateOverrideCreate(BaseModel):
    """Create a date-specific schedule override for a contractor.

    Two modes:
    1. Full-day unavailable: is_unavailable=True, blocks must be None or empty.
    2. Custom hours: is_unavailable=False, blocks define the day's time windows.

    An override replaces the weekly template for override_date entirely.
    """

    contractor_id: uuid.UUID
    override_date: date
    is_unavailable: bool = False
    blocks: list[TimeBlock] | None = None
