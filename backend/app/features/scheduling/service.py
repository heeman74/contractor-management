"""SchedulingService — core scheduling business logic engine.

Implements the full scheduling domain:
  - Availability computation (interval subtraction: working_hours - bookings - travel_buffers)
  - Conflict detection with SELECT FOR UPDATE per-contractor lock
  - Single-day booking (book_slot) with two-layer protection (lock + GIST)
  - Multi-day atomic booking (book_multiday_job) — all-or-nothing
  - Date suggestion for multi-day jobs (consecutive first, non-consecutive fallback)
  - Schedule CRUD (set_weekly_schedule, set_date_override)

All methods use class-level patterns from CLAUDE.md:
  - Inherits TenantScopedService[Booking]
  - No db.commit() calls — get_db handles transaction lifecycle
  - Specific exception types over generic ValueError
  - N+1 prevention via eager loading in repository layer
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select as sa_select
from sqlalchemy.dialects.postgresql import Range
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import TenantScopedService
from app.features.scheduling.models import (
    Booking,
    ContractorDateOverride,
    ContractorWeeklySchedule,
    JobSite,
)
from app.features.scheduling.repository import BookingConflictError, SchedulingRepository
from app.features.scheduling.schemas import (
    AvailabilityRequest,
    AvailabilityResponse,
    BlockedInterval,
    BookingCreate,
    ConflictDetail,
    DateSuggestion,
    DayBlock,
    FreeWindow,
    MultiDayBookingCreate,
    SchedulingConfig,
    TimeBlock,
)
from app.features.scheduling.travel.provider import TravelTimeProvider, TravelTimeUnavailableError

# ---------------------------------------------------------------------------
# Custom exceptions
# ---------------------------------------------------------------------------


class SchedulingConflictError(Exception):
    """Raised when a booking attempt conflicts with existing bookings.

    Provides detailed conflict information for the 409 response body.
    """

    def __init__(self, conflicts: list[ConflictDetail]) -> None:
        super().__init__(f"{len(conflicts)} conflict(s) detected")
        self.conflicts = conflicts


class OutsideWorkingHoursError(Exception):
    """Raised when a booking falls outside the contractor's working hours.

    Message describes when the contractor is available on that date.
    """

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class BookingTooShortError(Exception):
    """Raised when requested booking duration is below company minimum.

    Provides the requested and minimum durations for the error response.
    """

    def __init__(self, requested_minutes: float, minimum_minutes: int) -> None:
        super().__init__(
            f"Booking duration {requested_minutes:.0f} min is below "
            f"company minimum of {minimum_minutes} min"
        )
        self.requested_minutes = requested_minutes
        self.minimum_minutes = minimum_minutes


# ---------------------------------------------------------------------------
# SchedulingService
# ---------------------------------------------------------------------------


class SchedulingService(TenantScopedService[Booking]):
    """Core scheduling engine: availability, conflict detection, and booking.

    Inherits from TenantScopedService[Booking]. The repository is a
    SchedulingRepository that also queries related scheduling models.

    travel_provider is optional — when None, travel time computation is skipped
    and config.default_travel_time_minutes is used as a fixed buffer. This allows
    pure-logic unit testing without mocking an external travel API.
    """

    repository_class = SchedulingRepository

    def __init__(
        self,
        db: AsyncSession,
        travel_provider: TravelTimeProvider | None = None,
    ) -> None:
        super().__init__(db)
        self.travel_provider = travel_provider
        # Type-narrow the inherited self.repository to SchedulingRepository
        self.repository: SchedulingRepository = self.repository  # type: ignore[assignment]

    # -------------------------------------------------------------------------
    # Private helpers
    # -------------------------------------------------------------------------

    def _get_contractor_tz(self, tz_name: str) -> ZoneInfo:
        """Return ZoneInfo for the given IANA timezone name.

        Falls back to UTC if the zone name is invalid or unknown.
        """
        try:
            return ZoneInfo(tz_name)
        except (ZoneInfoNotFoundError, KeyError):
            return ZoneInfo("UTC")

    def _resolve_working_blocks(
        self,
        target_date: date,
        weekly_schedule: list[ContractorWeeklySchedule],
        date_overrides: list[ContractorDateOverride],
        contractor_tz: ZoneInfo,
        default_config: SchedulingConfig,
    ) -> list[tuple[datetime, datetime]]:
        """Resolve working hours for target_date as UTC datetime ranges.

        Resolution order (two-level override model):
        1. Date override exists + is_unavailable=True  -> return [] (day off)
        2. Date override exists with custom blocks      -> use those blocks
        3. Weekly schedule for that day_of_week         -> use those blocks
        4. Company default_working_hours for that DOW   -> use those blocks
        5. None of the above                            -> return [] (not schedulable)

        All time blocks are converted from contractor local time to UTC using
        DST-safe zoneinfo conversion.
        """
        # Check for date override
        day_overrides = [o for o in date_overrides if o.override_date == target_date]

        if day_overrides:
            # If any block is marked unavailable, the whole day is off
            if any(o.is_unavailable for o in day_overrides):
                return []
            # Custom override blocks
            return self._blocks_to_utc(
                target_date,
                [(o.start_time, o.end_time) for o in day_overrides if o.start_time and o.end_time],
                contractor_tz,
            )

        # ISO weekday: Monday=1 ... Sunday=7; our model: 0=Mon ... 6=Sun
        day_of_week = target_date.isoweekday() - 1
        weekly_blocks = [s for s in weekly_schedule if s.day_of_week == day_of_week]

        if weekly_blocks:
            return self._blocks_to_utc(
                target_date,
                [(b.start_time, b.end_time) for b in weekly_blocks],
                contractor_tz,
            )

        # Fall back to company-level default working hours
        day_key = str(day_of_week)
        if default_config.default_working_hours and day_key in default_config.default_working_hours:
            from datetime import time

            raw_blocks = default_config.default_working_hours[day_key]
            parsed_blocks: list[tuple] = []
            for block in raw_blocks:
                try:
                    start_parts = [int(p) for p in block["start"].split(":")]
                    end_parts = [int(p) for p in block["end"].split(":")]
                    start_t = time(start_parts[0], start_parts[1] if len(start_parts) > 1 else 0)
                    end_t = time(end_parts[0], end_parts[1] if len(end_parts) > 1 else 0)
                    parsed_blocks.append((start_t, end_t))
                except (KeyError, ValueError, IndexError):
                    continue
            return self._blocks_to_utc(target_date, parsed_blocks, contractor_tz)

        return []

    def _blocks_to_utc(
        self,
        target_date: date,
        blocks: list[tuple],
        contractor_tz: ZoneInfo,
    ) -> list[tuple[datetime, datetime]]:
        """Convert (start_time, end_time) pairs to UTC datetime tuples for target_date.

        Uses zoneinfo for DST-safe conversion. Each block becomes a UTC range.
        Blocks with end <= start are skipped (malformed data guard).
        """
        utc_blocks: list[tuple[datetime, datetime]] = []
        for start_t, end_t in blocks:
            if start_t is None or end_t is None:
                continue
            local_start = datetime(
                target_date.year,
                target_date.month,
                target_date.day,
                start_t.hour,
                start_t.minute,
                tzinfo=contractor_tz,
            )
            local_end = datetime(
                target_date.year,
                target_date.month,
                target_date.day,
                end_t.hour,
                end_t.minute,
                tzinfo=contractor_tz,
            )
            utc_start = local_start.astimezone(ZoneInfo("UTC"))
            utc_end = local_end.astimezone(ZoneInfo("UTC"))
            if utc_end > utc_start:
                utc_blocks.append((utc_start, utc_end))
        return utc_blocks

    def _compute_free_windows(
        self,
        working_blocks: list[tuple[datetime, datetime]],
        blocked_intervals: list[tuple[datetime, datetime, str]],
        min_duration_minutes: int,
        buffer_minutes: int,
    ) -> tuple[list[FreeWindow], list[BlockedInterval]]:
        """Interval subtraction: working_blocks - blocked_intervals = free windows.

        Algorithm:
        1. Expand each blocked interval by buffer_minutes on each side.
        2. Merge overlapping blocked intervals (sort by start, sweep).
        3. For each working block, subtract merged blocked intervals.
        4. Keep resulting free windows >= min_duration_minutes.
        5. Build BlockedInterval list with gap reasons for the UI.

        Returns:
            (free_windows, all_blocked_intervals_with_reasons)
        """
        if not working_blocks:
            return [], []

        # Step 1: Expand blocked intervals by buffer on each side
        buffer = timedelta(minutes=buffer_minutes)
        expanded: list[tuple[datetime, datetime, str]] = []
        for start, end, reason in blocked_intervals:
            expanded_start = start - buffer
            expanded_end = end + buffer
            expanded.append((expanded_start, expanded_end, reason))

        # Step 2: Sort and merge overlapping blocked intervals
        # Keep track of reasons for each merged block
        expanded.sort(key=lambda x: x[0])
        merged_blocks: list[tuple[datetime, datetime, list[str]]] = []
        for start, end, reason in expanded:
            if merged_blocks and start <= merged_blocks[-1][1]:
                prev_start, prev_end, prev_reasons = merged_blocks[-1]
                new_end = max(prev_end, end)
                merged_blocks[-1] = (prev_start, new_end, [*prev_reasons, reason])
            else:
                merged_blocks.append((start, end, [reason]))

        # Step 3 & 4: Subtract from working blocks and collect free windows
        free_windows: list[FreeWindow] = []
        result_blocked: list[BlockedInterval] = []

        for work_start, work_end in working_blocks:
            # Add "outside_working_hours" blocked intervals at day boundaries
            # (implicit — the FreeWindow reason_before will document this)
            current = work_start

            for block_start, block_end, reasons in merged_blocks:
                # Skip blocks entirely outside this working window
                if block_end <= work_start or block_start >= work_end:
                    continue

                # Clamp block to working window
                clamped_start = max(block_start, work_start)
                clamped_end = min(block_end, work_end)

                # Free window before this block
                if current < clamped_start:
                    duration_min = (clamped_start - current).total_seconds() / 60
                    if duration_min >= min_duration_minutes:
                        reason_before: str | None = None
                        if current == work_start:
                            reason_before = "outside_working_hours"
                        elif result_blocked:
                            reason_before = result_blocked[-1].reason
                        free_windows.append(
                            FreeWindow(
                                start=current,
                                end=clamped_start,
                                reason_before=reason_before,
                            )
                        )

                # Record the blocked interval with primary reason
                primary_reason = reasons[0] if reasons else "existing_job"
                result_blocked.append(
                    BlockedInterval(
                        start=clamped_start,
                        end=clamped_end,
                        reason=primary_reason,
                    )
                )
                current = clamped_end

            # Free window after last block (tail of working day)
            if current < work_end:
                duration_min = (work_end - current).total_seconds() / 60
                if duration_min >= min_duration_minutes:
                    reason_before = None
                    if current == work_start:
                        # Entire working block is free (no blocked intervals within)
                        reason_before = "outside_working_hours"
                    elif result_blocked:
                        reason_before = result_blocked[-1].reason
                    free_windows.append(
                        FreeWindow(
                            start=current,
                            end=work_end,
                            reason_before=reason_before,
                        )
                    )

        return free_windows, result_blocked

    async def _get_travel_buffers(
        self,
        existing_bookings: list[Booking],
        config: SchedulingConfig,
    ) -> list[tuple[datetime, datetime, str]]:
        """Compute travel time blocked intervals between consecutive bookings.

        For each pair of consecutive bookings (by time), compute the travel time
        between job sites and add a buffer. Returns blocked intervals with reason
        "travel_buffer" for each gap between consecutive jobs.

        Falls back to config.default_travel_time_minutes when:
        - travel_provider is None
        - A booking has no job_site
        - A job_site has no coordinates
        - TravelTimeUnavailableError is raised

        Safety margin is applied via apply_safety_margin() before converting to timedelta.
        """
        if not existing_bookings or len(existing_bookings) < 2:
            return []

        from app.features.scheduling.travel.cache import apply_safety_margin

        travel_intervals: list[tuple[datetime, datetime, str]] = []

        # Sort bookings by start time
        sorted_bookings = sorted(existing_bookings, key=lambda b: b.time_range.lower)

        for i in range(len(sorted_bookings) - 1):
            current_booking = sorted_bookings[i]
            next_booking = sorted_bookings[i + 1]

            current_end = current_booking.time_range.upper
            next_start = next_booking.time_range.lower

            # Determine travel seconds between these consecutive jobs
            travel_seconds: int | None = None

            if (
                self.travel_provider is not None
                and current_booking.job_site is not None
                and next_booking.job_site is not None
                and current_booking.job_site.latitude is not None
                and current_booking.job_site.longitude is not None
                and next_booking.job_site.latitude is not None
                and next_booking.job_site.longitude is not None
            ):
                try:
                    raw_seconds = await self.travel_provider.get_travel_seconds(
                        origin_lat=float(current_booking.job_site.latitude),
                        origin_lng=float(current_booking.job_site.longitude),
                        dest_lat=float(next_booking.job_site.latitude),
                        dest_lng=float(next_booking.job_site.longitude),
                    )
                    travel_seconds = apply_safety_margin(raw_seconds, config.travel_margin_percent)
                except TravelTimeUnavailableError:
                    travel_seconds = None

            if travel_seconds is None:
                travel_seconds = config.default_travel_time_minutes * 60

            if travel_seconds > 0:
                # The blocked travel interval starts at end of current job
                # and lasts for travel_seconds
                travel_end = current_end + timedelta(seconds=travel_seconds)
                # Only add if there's actually a gap between jobs
                if travel_end > current_end and current_end < next_start:
                    travel_intervals.append(
                        (current_end, min(travel_end, next_start), "travel_buffer")
                    )

        return travel_intervals

    def _to_utc_range(
        self,
        day_block: DayBlock,
        contractor_tz: ZoneInfo,
    ) -> tuple[datetime, datetime]:
        """Convert a DayBlock (date + start_time + end_time) to UTC datetime range.

        Uses zoneinfo for DST-safe conversion. Returns (utc_start, utc_end).
        """
        local_start = datetime(
            day_block.date.year,
            day_block.date.month,
            day_block.date.day,
            day_block.start_time.hour,
            day_block.start_time.minute,
            tzinfo=contractor_tz,
        )
        local_end = datetime(
            day_block.date.year,
            day_block.date.month,
            day_block.date.day,
            day_block.end_time.hour,
            day_block.end_time.minute,
            tzinfo=contractor_tz,
        )
        return local_start.astimezone(ZoneInfo("UTC")), local_end.astimezone(ZoneInfo("UTC"))

    def _compute_distance_km(
        self,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float,
    ) -> float:
        """Compute approximate great-circle distance in km using the Haversine formula."""
        import math

        r = 6371.0  # Earth radius in km
        d_lat = math.radians(lat2 - lat1)
        d_lng = math.radians(lng2 - lng1)
        a = (
            math.sin(d_lat / 2) ** 2
            + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
        )
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return r * c

    # -------------------------------------------------------------------------
    # Public methods — availability
    # -------------------------------------------------------------------------

    async def get_available_slots(
        self,
        request: AvailabilityRequest,
    ) -> list[AvailabilityResponse]:
        """Compute contractor availability for the requested date.

        Accepts contractor_ids list OR trade_type (or both). For each contractor:
        1. Resolve working blocks for the requested date (override > weekly > company default).
        2. Fetch existing bookings for that day.
        3. Compute travel buffer intervals between consecutive bookings.
        4. Subtract bookings + travel buffers from working blocks = free windows.
        5. If job_site_id provided: compute distance for proximity sorting.

        Returns list of AvailabilityResponse sorted nearest-first when job_site_id is given.
        """
        company_id = self._require_tenant_id()

        # Resolve contractor IDs
        contractor_ids: list[uuid.UUID] = []
        if request.contractor_ids:
            contractor_ids.extend(request.contractor_ids)
        if request.trade_type:
            trade_contractors = await self.repository.get_contractors_by_trade(
                request.trade_type, company_id
            )
            existing_ids = set(contractor_ids)
            for c in trade_contractors:
                if c.id not in existing_ids:
                    contractor_ids.append(c.id)

        if not contractor_ids:
            return []

        # Fetch job_site coordinates for distance sorting if requested
        job_site_lat: float | None = None
        job_site_lng: float | None = None
        if request.job_site_id:
            js_result = await self.db.execute(
                sa_select(JobSite).where(JobSite.id == request.job_site_id)
            )
            job_site = js_result.scalar_one_or_none()
            if job_site and job_site.latitude and job_site.longitude:
                job_site_lat = float(job_site.latitude)
                job_site_lng = float(job_site.longitude)

        config = await self.repository.get_company_scheduling_config(company_id)

        # Compute availability for each contractor
        results: list[AvailabilityResponse] = []
        target_date = request.date

        # Date range for booking query: the full requested day in UTC
        # Use a broad window covering the full calendar day in UTC
        day_start_utc = datetime(target_date.year, target_date.month, target_date.day, tzinfo=UTC)
        day_end_utc = day_start_utc + timedelta(days=1)

        for contractor_id in contractor_ids:
            contractor = await self.repository.get_contractor_with_location(contractor_id)
            if contractor is None:
                continue

            contractor_tz = self._get_contractor_tz(contractor.timezone)
            contractor_name = f"{contractor.first_name or ''} {contractor.last_name or ''}".strip()
            if not contractor_name:
                contractor_name = contractor.email

            # Fetch schedule data (no N+1: single query per contractor)
            weekly_schedule = await self.repository.get_weekly_schedule(contractor_id)
            date_overrides = await self.repository.get_date_overrides(
                contractor_id, target_date, target_date
            )
            existing_bookings = await self.repository.get_bookings_in_range(
                contractor_id, day_start_utc, day_end_utc
            )

            # Resolve working hours as UTC blocks
            working_blocks = self._resolve_working_blocks(
                target_date, weekly_schedule, date_overrides, contractor_tz, config
            )

            if not working_blocks:
                # Contractor is off this day — return empty availability
                results.append(
                    AvailabilityResponse(
                        contractor_id=contractor_id,
                        contractor_name=contractor_name,
                        date=target_date,
                        free_windows=[],
                        blocked_intervals=[
                            BlockedInterval(
                                start=day_start_utc,
                                end=day_end_utc,
                                reason="time_off",
                            )
                        ],
                        distance_km=None,
                    )
                )
                continue

            # Compute travel buffer intervals
            travel_buffers = await self._get_travel_buffers(existing_bookings, config)

            # Build blocked intervals from existing bookings
            booking_intervals: list[tuple[datetime, datetime, str]] = [
                (b.time_range.lower, b.time_range.upper, "existing_job")
                for b in existing_bookings
                if b.time_range.lower is not None and b.time_range.upper is not None
            ]

            all_blocked = booking_intervals + travel_buffers

            free_windows, blocked_intervals = self._compute_free_windows(
                working_blocks=working_blocks,
                blocked_intervals=all_blocked,
                min_duration_minutes=config.default_min_job_duration_minutes,
                buffer_minutes=config.default_buffer_minutes,
            )

            # Compute distance if job_site provided and contractor has home location
            distance_km: float | None = None
            if (
                job_site_lat is not None
                and job_site_lng is not None
                and contractor.home_latitude is not None
                and contractor.home_longitude is not None
            ):
                distance_km = self._compute_distance_km(
                    float(contractor.home_latitude),
                    float(contractor.home_longitude),
                    job_site_lat,
                    job_site_lng,
                )

            results.append(
                AvailabilityResponse(
                    contractor_id=contractor_id,
                    contractor_name=contractor_name,
                    date=target_date,
                    free_windows=free_windows,
                    blocked_intervals=blocked_intervals,
                    distance_km=distance_km,
                )
            )

        # Sort by distance (nearest first) when job_site provided
        if job_site_lat is not None:
            results.sort(key=lambda r: (r.distance_km is None, r.distance_km or 0.0))

        return results

    async def check_conflicts(
        self,
        contractor_id: uuid.UUID,
        start: datetime,
        end: datetime,
    ) -> list[ConflictDetail]:
        """Return conflict details for any existing bookings that overlap [start, end).

        Read-only pre-check — does NOT acquire a lock. The service calls this
        after acquiring the contractor lock in book_slot/book_multiday_job.
        """
        conflicts = await self.repository.find_conflicts(
            contractor_id=contractor_id,
            utc_ranges=[(start, end)],
        )
        return [
            ConflictDetail(
                booking_id=b.id,
                contractor_id=b.contractor_id,
                time_range_start=b.time_range.lower,
                time_range_end=b.time_range.upper,
                job_id=b.job_id,
            )
            for b in conflicts
            if b.time_range.lower and b.time_range.upper
        ]

    # -------------------------------------------------------------------------
    # Public methods — booking
    # -------------------------------------------------------------------------

    async def book_slot(self, booking_data: BookingCreate) -> Booking:
        """Book a single time slot for a contractor.

        Two-layer protection:
        1. Application layer: SELECT FOR UPDATE lock + pre-check conflict query
        2. Database layer: GIST exclusion constraint as safety net

        Validation:
        - No overlap with existing bookings (raises SchedulingConflictError)
        - Booking is within contractor's working hours (raises OutsideWorkingHoursError)
        - Duration >= company minimum (raises BookingTooShortError)

        Returns the created Booking with server-generated fields populated.
        """
        company_id = self._require_tenant_id()
        contractor_id = booking_data.contractor_id

        # Acquire per-contractor lock (serializes concurrent booking attempts)
        await self.repository.acquire_contractor_lock(contractor_id)

        # Validate duration
        duration_minutes = (booking_data.end - booking_data.start).total_seconds() / 60
        config = await self.repository.get_company_scheduling_config(company_id)
        if duration_minutes < config.default_min_job_duration_minutes:
            raise BookingTooShortError(
                requested_minutes=duration_minutes,
                minimum_minutes=config.default_min_job_duration_minutes,
            )

        # Pre-check: conflict detection (within the lock)
        conflicts = await self.check_conflicts(contractor_id, booking_data.start, booking_data.end)
        if conflicts:
            raise SchedulingConflictError(conflicts)

        # Validate booking is within working hours
        contractor = await self.repository.get_contractor_with_location(contractor_id)
        if contractor is None:
            raise OutsideWorkingHoursError(f"Contractor {contractor_id} not found")

        contractor_tz = self._get_contractor_tz(contractor.timezone)
        booking_date = booking_data.start.astimezone(contractor_tz).date()
        weekly_schedule = await self.repository.get_weekly_schedule(contractor_id)
        date_overrides = await self.repository.get_date_overrides(
            contractor_id, booking_date, booking_date
        )
        working_blocks = self._resolve_working_blocks(
            booking_date, weekly_schedule, date_overrides, contractor_tz, config
        )

        if not working_blocks:
            raise OutsideWorkingHoursError(
                f"Contractor has no working hours on {booking_date} "
                f"(timezone: {contractor.timezone})"
            )

        # Check containment: booking must fit within a working block
        is_within = False
        for work_start, work_end in working_blocks:
            if booking_data.start >= work_start and booking_data.end <= work_end:
                is_within = True
                break
        if not is_within:
            blocks_str = ", ".join(
                f"{ws.isoformat()}-{we.isoformat()}" for ws, we in working_blocks
            )
            raise OutsideWorkingHoursError(
                f"Booking [{booking_data.start.isoformat()}, {booking_data.end.isoformat()}] "
                f"falls outside contractor's working hours on {booking_date}: [{blocks_str}]"
            )

        # Create booking
        booking = Booking(
            company_id=company_id,
            contractor_id=contractor_id,
            job_id=booking_data.job_id,
            job_site_id=booking_data.job_site_id,
            time_range=Range(booking_data.start, booking_data.end, bounds="[)"),
            notes=booking_data.notes,
        )

        try:
            return await self.repository.create_booking(booking)
        except BookingConflictError as exc:
            # GIST constraint violation (race condition bypassed application lock)
            raise SchedulingConflictError([]) from exc

    async def book_multiday_job(
        self,
        booking_data: MultiDayBookingCreate,
    ) -> list[Booking]:
        """Book all days of a multi-day job atomically.

        All-or-nothing: if ANY day has a conflict or validation failure,
        the entire multi-day booking is rejected (no partial bookings).

        Algorithm:
        1. Acquire contractor lock (single lock covers all days)
        2. Convert all DayBlocks to UTC ranges
        3. Pre-check ALL days for conflicts in one batch query
        4. Validate each day is within working hours
        5. Insert all booking records sharing a parent_booking_id
        6. GIST constraint catches any remaining races

        Returns list of created Booking records (one per day_block).
        """
        company_id = self._require_tenant_id()
        contractor_id = booking_data.contractor_id

        # Acquire lock (covers all days — same contractor)
        await self.repository.acquire_contractor_lock(contractor_id)

        contractor = await self.repository.get_contractor_with_location(contractor_id)
        if contractor is None:
            raise OutsideWorkingHoursError(f"Contractor {contractor_id} not found")

        contractor_tz = self._get_contractor_tz(contractor.timezone)
        config = await self.repository.get_company_scheduling_config(company_id)

        # Convert all DayBlocks to UTC ranges
        utc_ranges: list[tuple[datetime, datetime]] = []
        for day_block in booking_data.day_blocks:
            utc_start, utc_end = self._to_utc_range(day_block, contractor_tz)
            utc_ranges.append((utc_start, utc_end))

        # Validate durations
        for utc_start, utc_end in utc_ranges:
            duration_minutes = (utc_end - utc_start).total_seconds() / 60
            if duration_minutes < config.default_min_job_duration_minutes:
                raise BookingTooShortError(
                    requested_minutes=duration_minutes,
                    minimum_minutes=config.default_min_job_duration_minutes,
                )

        # Batch conflict check: single query covering all days
        conflicts = await self.repository.find_conflicts(
            contractor_id=contractor_id,
            utc_ranges=utc_ranges,
        )
        if conflicts:
            conflict_details = [
                ConflictDetail(
                    booking_id=b.id,
                    contractor_id=b.contractor_id,
                    time_range_start=b.time_range.lower,
                    time_range_end=b.time_range.upper,
                    job_id=b.job_id,
                )
                for b in conflicts
                if b.time_range.lower and b.time_range.upper
            ]
            raise SchedulingConflictError(conflict_details)

        # Validate each day is within working hours
        all_dates = [db.date for db in booking_data.day_blocks]
        if all_dates:
            date_overrides = await self.repository.get_date_overrides(
                contractor_id, min(all_dates), max(all_dates)
            )
        else:
            date_overrides = []
        weekly_schedule = await self.repository.get_weekly_schedule(contractor_id)

        for day_block, (utc_start, utc_end) in zip(
            booking_data.day_blocks, utc_ranges, strict=True
        ):
            working_blocks = self._resolve_working_blocks(
                day_block.date, weekly_schedule, date_overrides, contractor_tz, config
            )
            if not working_blocks:
                raise OutsideWorkingHoursError(
                    f"Contractor has no working hours on {day_block.date}"
                )
            is_within = any(utc_start >= ws and utc_end <= we for ws, we in working_blocks)
            if not is_within:
                raise OutsideWorkingHoursError(
                    f"Day block {day_block.date} falls outside contractor working hours"
                )

        # Insert all booking records (all-or-nothing within the transaction)
        created_bookings: list[Booking] = []
        parent_booking_id: uuid.UUID | None = None

        for day_index, (_day_block, (utc_start, utc_end)) in enumerate(
            zip(booking_data.day_blocks, utc_ranges, strict=True)
        ):
            booking = Booking(
                company_id=company_id,
                contractor_id=contractor_id,
                job_id=booking_data.job_id,
                job_site_id=booking_data.job_site_id,
                time_range=Range(utc_start, utc_end, bounds="[)"),
                day_index=day_index,
                parent_booking_id=parent_booking_id,
                notes=booking_data.notes,
            )
            try:
                created = await self.repository.create_booking(booking)
            except BookingConflictError as exc:
                raise SchedulingConflictError([]) from exc

            # Link all subsequent bookings to the first one
            if day_index == 0:
                parent_booking_id = created.id

            created_bookings.append(created)

        return created_bookings

    # -------------------------------------------------------------------------
    # Public methods — date suggestion
    # -------------------------------------------------------------------------

    async def suggest_dates(
        self,
        contractor_id: uuid.UUID,
        num_days: int,
        preferred_start: date,
        duration_hours: float,
        within_days: int = 30,
    ) -> list[DateSuggestion]:
        """Suggest date combinations for a multi-day job.

        Strategy:
        1. Scan from preferred_start to preferred_start + within_days
        2. For each candidate date, check if there is a free window >= duration_hours
        3. Find all eligible dates, then find consecutive runs of length num_days
        4. Return up to 5 DateSuggestion results:
           - Consecutive combinations first
           - Non-consecutive combinations as fallback
           - Sorted by earliest start date within each category

        Per user decision: prefer consecutive dates; non-consecutive only as fallback.
        """
        company_id = self._require_tenant_id()

        contractor = await self.repository.get_contractor_with_location(contractor_id)
        if contractor is None:
            return []

        contractor_tz = self._get_contractor_tz(contractor.timezone)
        config = await self.repository.get_company_scheduling_config(company_id)
        min_duration_minutes = int(duration_hours * 60)

        # Build candidate date range
        end_date = preferred_start + timedelta(days=within_days)
        all_dates_in_window: list[date] = []
        check_date = preferred_start
        while check_date <= end_date:
            all_dates_in_window.append(check_date)
            check_date += timedelta(days=1)

        # Fetch schedule data in bulk
        weekly_schedule = await self.repository.get_weekly_schedule(contractor_id)
        date_overrides = await self.repository.get_date_overrides(
            contractor_id, preferred_start, end_date
        )

        # Fetch all bookings in window
        window_start_utc = datetime(
            preferred_start.year, preferred_start.month, preferred_start.day, tzinfo=UTC
        )
        window_end_utc = datetime(
            end_date.year, end_date.month, end_date.day, tzinfo=UTC
        ) + timedelta(days=1)
        all_bookings = await self.repository.get_bookings_in_range(
            contractor_id, window_start_utc, window_end_utc
        )

        # Find eligible dates (have free window >= min_duration_minutes)
        eligible_dates: list[date] = []
        for candidate_date in all_dates_in_window:
            working_blocks = self._resolve_working_blocks(
                candidate_date, weekly_schedule, date_overrides, contractor_tz, config
            )
            if not working_blocks:
                continue

            # Filter bookings to this day
            day_start = datetime(
                candidate_date.year, candidate_date.month, candidate_date.day, tzinfo=UTC
            )
            day_end = day_start + timedelta(days=1)
            day_bookings = [
                b
                for b in all_bookings
                if b.time_range.lower is not None and day_start <= b.time_range.lower < day_end
            ]

            booking_intervals: list[tuple[datetime, datetime, str]] = [
                (b.time_range.lower, b.time_range.upper, "existing_job")
                for b in day_bookings
                if b.time_range.lower and b.time_range.upper
            ]

            free_windows, _ = self._compute_free_windows(
                working_blocks=working_blocks,
                blocked_intervals=booking_intervals,
                min_duration_minutes=min_duration_minutes,
                buffer_minutes=config.default_buffer_minutes,
            )

            # Check if any free window is long enough
            has_slot = any(
                (fw.end - fw.start).total_seconds() / 60 >= min_duration_minutes
                for fw in free_windows
            )
            if has_slot:
                eligible_dates.append(candidate_date)

        if len(eligible_dates) < num_days:
            return []

        # Find consecutive date combinations of length num_days
        suggestions: list[DateSuggestion] = []

        # Build consecutive runs
        for i in range(len(eligible_dates) - num_days + 1):
            window = eligible_dates[i : i + num_days]
            # Check if all dates are consecutive (no gaps)
            is_consecutive = all(
                (window[j + 1] - window[j]).days == 1 for j in range(len(window) - 1)
            )
            if is_consecutive:
                suggestions.append(DateSuggestion(dates=window, is_consecutive=True))
                if len(suggestions) >= 5:
                    break

        # If fewer than 5 consecutive found, add non-consecutive combinations
        if len(suggestions) < 5:
            from itertools import combinations

            for combo in combinations(eligible_dates, num_days):
                combo_dates = list(combo)
                is_consecutive = all(
                    (combo_dates[j + 1] - combo_dates[j]).days == 1
                    for j in range(len(combo_dates) - 1)
                )
                if not is_consecutive:
                    suggestions.append(DateSuggestion(dates=combo_dates, is_consecutive=False))
                    if len(suggestions) >= 5:
                        break

        # Sort: consecutive first, then by earliest start date
        suggestions.sort(key=lambda s: (not s.is_consecutive, s.dates[0]))
        return suggestions[:5]

    # -------------------------------------------------------------------------
    # Public methods — rescheduling
    # -------------------------------------------------------------------------

    async def reschedule_booking(
        self,
        booking_id: uuid.UUID,
        new_start: datetime,
        new_end: datetime,
    ) -> Booking:
        """Reschedule an existing booking to a new time slot.

        Algorithm:
        1. Fetch and soft-delete the existing booking
        2. Attempt to book the new slot via book_slot
        3. If new booking fails (conflict): restore the old booking (remove soft-delete)
        4. Return the new booking on success

        Travel time conflicts are treated as hard rejections (same as booking conflicts).
        """
        self._require_tenant_id()

        # Fetch existing booking
        existing = await self.repository.get_by_id(booking_id)
        if existing is None:
            raise ValueError(f"Booking {booking_id} not found")

        # Soft-delete the existing booking to free the slot for conflict checking
        deleted = await self.repository.soft_delete(booking_id)
        if not deleted:
            raise ValueError(f"Failed to soft-delete booking {booking_id}")

        # Attempt to create the new booking
        try:
            new_booking_data = BookingCreate(
                contractor_id=existing.contractor_id,
                job_id=existing.job_id,
                job_site_id=existing.job_site_id,
                start=new_start,
                end=new_end,
                notes=existing.notes,
            )
            return await self.book_slot(new_booking_data)
        except (SchedulingConflictError, OutsideWorkingHoursError, BookingTooShortError):
            # Restore the original booking by clearing deleted_at
            await self.repository.update(booking_id, {"deleted_at": None})
            raise

    # -------------------------------------------------------------------------
    # Public methods — schedule management
    # -------------------------------------------------------------------------

    async def set_weekly_schedule(
        self,
        contractor_id: uuid.UUID,
        day_of_week: int,
        blocks: list[TimeBlock],
    ) -> list[ContractorWeeklySchedule]:
        """Replace all weekly schedule blocks for a contractor's day.

        Atomically replaces all blocks for (contractor_id, day_of_week):
        1. Soft-delete all existing blocks for this day
        2. Insert new blocks with sequential block_index
        3. Ensure contractor_schedule_lock row exists (for future lock acquisition)

        An empty blocks list clears the contractor's schedule for that day.
        Returns the newly created blocks.
        """
        company_id = self._require_tenant_id()

        # Soft-delete existing blocks for this day
        await self.repository.delete_weekly_schedule_for_day(contractor_id, day_of_week)

        # Insert replacement blocks
        created: list[ContractorWeeklySchedule] = []
        for block_index, time_block in enumerate(blocks):
            schedule_block = ContractorWeeklySchedule(
                company_id=company_id,
                contractor_id=contractor_id,
                day_of_week=day_of_week,
                block_index=block_index,
                start_time=time_block.start_time,
                end_time=time_block.end_time,
            )
            new_block = await self.repository.create_weekly_schedule_block(schedule_block)
            created.append(new_block)

        # Ensure lock row exists for this contractor
        await self.repository.ensure_schedule_lock_exists(contractor_id, company_id)

        return created

    async def set_date_override(
        self,
        contractor_id: uuid.UUID,
        override_date: date,
        is_unavailable: bool,
        blocks: list[TimeBlock] | None,
    ) -> list[ContractorDateOverride]:
        """Replace date-specific schedule overrides for a contractor.

        Two modes:
        1. is_unavailable=True: single record with no time blocks (full day off)
        2. is_unavailable=False: insert blocks with sequential block_index

        Returns the newly created override records.
        """
        company_id = self._require_tenant_id()

        # Soft-delete existing overrides for this date
        await self.repository.delete_date_overrides_for_date(contractor_id, override_date)

        created: list[ContractorDateOverride] = []

        if is_unavailable:
            # Single "full day off" record
            override = ContractorDateOverride(
                company_id=company_id,
                contractor_id=contractor_id,
                override_date=override_date,
                is_unavailable=True,
                block_index=0,
                start_time=None,
                end_time=None,
            )
            new_override = await self.repository.create_date_override(override)
            created.append(new_override)
        else:
            # Custom time blocks
            if blocks:
                for block_index, time_block in enumerate(blocks):
                    override = ContractorDateOverride(
                        company_id=company_id,
                        contractor_id=contractor_id,
                        override_date=override_date,
                        is_unavailable=False,
                        block_index=block_index,
                        start_time=time_block.start_time,
                        end_time=time_block.end_time,
                    )
                    new_override = await self.repository.create_date_override(override)
                    created.append(new_override)

        return created
