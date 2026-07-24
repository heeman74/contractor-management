"""Pure scheduling geometry — availability math with no I/O.

This module holds the side-effect-free core of the scheduling engine:
working-hour resolution, interval subtraction, timezone conversion, and
great-circle distance. Keeping these functions free of database and network
access makes them trivial to unit test and keeps SchedulingService focused on
orchestration.
"""

from __future__ import annotations

import math
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.features.scheduling.models import (
    ContractorDateOverride,
    ContractorWeeklySchedule,
)
from app.features.scheduling.schemas import (
    BlockedInterval,
    DayBlock,
    FreeWindow,
    SchedulingConfig,
)

_UTC = ZoneInfo("UTC")

DEFAULT_BLOCK_REASON = "existing_job"
OUTSIDE_WORKING_HOURS_REASON = "outside_working_hours"
_EARTH_RADIUS_KM = 6371.0


def get_zoneinfo(tz_name: str) -> ZoneInfo:
    """Return ZoneInfo for the given IANA name, falling back to UTC when invalid."""
    try:
        return ZoneInfo(tz_name)
    except (ZoneInfoNotFoundError, KeyError):
        return _UTC


def blocks_to_utc(
    target_date,
    blocks: list[tuple],
    contractor_tz: ZoneInfo,
) -> list[tuple[datetime, datetime]]:
    """Convert (start_time, end_time) pairs to UTC datetime tuples for target_date.

    Uses zoneinfo for DST-safe conversion. Blocks with end <= start are skipped.
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
        utc_start = local_start.astimezone(_UTC)
        utc_end = local_end.astimezone(_UTC)
        if utc_end > utc_start:
            utc_blocks.append((utc_start, utc_end))
    return utc_blocks


def _parse_default_working_hours(raw_blocks: list[dict]) -> list[tuple[time, time]]:
    """Parse company default working-hour dicts into (start, end) time pairs."""
    parsed_blocks: list[tuple[time, time]] = []
    for block in raw_blocks:
        try:
            start_parts = [int(p) for p in block["start"].split(":")]
            end_parts = [int(p) for p in block["end"].split(":")]
            start_t = time(start_parts[0], start_parts[1] if len(start_parts) > 1 else 0)
            end_t = time(end_parts[0], end_parts[1] if len(end_parts) > 1 else 0)
            parsed_blocks.append((start_t, end_t))
        except (KeyError, ValueError, IndexError):
            continue
    return parsed_blocks


def resolve_working_blocks(
    target_date,
    weekly_schedule: list[ContractorWeeklySchedule],
    date_overrides: list[ContractorDateOverride],
    contractor_tz: ZoneInfo,
    default_config: SchedulingConfig,
) -> list[tuple[datetime, datetime]]:
    """Resolve working hours for target_date as UTC datetime ranges.

    Resolution order (two-level override model):
    1. Date override with is_unavailable=True  -> [] (day off)
    2. Date override with custom blocks         -> those blocks
    3. Weekly schedule for that day_of_week     -> those blocks
    4. Company default_working_hours for the DOW -> those blocks
    5. None of the above                        -> [] (not schedulable)
    """
    day_overrides = [o for o in date_overrides if o.override_date == target_date]
    if day_overrides:
        if any(o.is_unavailable for o in day_overrides):
            return []
        return blocks_to_utc(
            target_date,
            [(o.start_time, o.end_time) for o in day_overrides if o.start_time and o.end_time],
            contractor_tz,
        )

    # ISO weekday: Monday=1 ... Sunday=7; our model: 0=Mon ... 6=Sun
    day_of_week = target_date.isoweekday() - 1
    weekly_blocks = [s for s in weekly_schedule if s.day_of_week == day_of_week]
    if weekly_blocks:
        return blocks_to_utc(
            target_date,
            [(b.start_time, b.end_time) for b in weekly_blocks],
            contractor_tz,
        )

    day_key = str(day_of_week)
    if default_config.default_working_hours and day_key in default_config.default_working_hours:
        parsed_blocks = _parse_default_working_hours(default_config.default_working_hours[day_key])
        return blocks_to_utc(target_date, parsed_blocks, contractor_tz)

    return []


def _merge_blocked_intervals(
    blocked_intervals: list[tuple[datetime, datetime, str]],
    buffer_minutes: int,
) -> list[tuple[datetime, datetime, list[str]]]:
    """Expand each interval by buffer_minutes on both sides, then merge overlaps."""
    buffer = timedelta(minutes=buffer_minutes)
    expanded = [(start - buffer, end + buffer, reason) for start, end, reason in blocked_intervals]
    expanded.sort(key=lambda x: x[0])

    merged: list[tuple[datetime, datetime, list[str]]] = []
    for start, end, reason in expanded:
        if merged and start <= merged[-1][1]:
            prev_start, prev_end, prev_reasons = merged[-1]
            merged[-1] = (prev_start, max(prev_end, end), [*prev_reasons, reason])
        else:
            merged.append((start, end, [reason]))
    return merged


def compute_free_windows(
    working_blocks: list[tuple[datetime, datetime]],
    blocked_intervals: list[tuple[datetime, datetime, str]],
    min_duration_minutes: int,
    buffer_minutes: int,
) -> tuple[list[FreeWindow], list[BlockedInterval]]:
    """Interval subtraction: working_blocks - blocked_intervals = free windows.

    Returns (free_windows, blocked_intervals_with_reasons).
    """
    if not working_blocks:
        return [], []

    merged_blocks = _merge_blocked_intervals(blocked_intervals, buffer_minutes)

    free_windows: list[FreeWindow] = []
    result_blocked: list[BlockedInterval] = []

    for work_start, work_end in working_blocks:
        current = work_start

        for block_start, block_end, reasons in merged_blocks:
            if block_end <= work_start or block_start >= work_end:
                continue

            clamped_start = max(block_start, work_start)
            clamped_end = min(block_end, work_end)

            _append_free_window(
                free_windows,
                result_blocked,
                current,
                clamped_start,
                work_start,
                min_duration_minutes,
            )

            primary_reason = reasons[0] if reasons else DEFAULT_BLOCK_REASON
            result_blocked.append(
                BlockedInterval(start=clamped_start, end=clamped_end, reason=primary_reason)
            )
            current = clamped_end

        _append_free_window(
            free_windows, result_blocked, current, work_end, work_start, min_duration_minutes
        )

    return free_windows, result_blocked


def _append_free_window(
    free_windows: list[FreeWindow],
    result_blocked: list[BlockedInterval],
    window_start: datetime,
    window_end: datetime,
    work_start: datetime,
    min_duration_minutes: int,
) -> None:
    """Append a FreeWindow for [window_start, window_end) when it is long enough."""
    if window_start >= window_end:
        return
    duration_min = (window_end - window_start).total_seconds() / 60
    if duration_min < min_duration_minutes:
        return

    reason_before: str | None = None
    if window_start == work_start:
        reason_before = OUTSIDE_WORKING_HOURS_REASON
    elif result_blocked:
        reason_before = result_blocked[-1].reason

    free_windows.append(FreeWindow(start=window_start, end=window_end, reason_before=reason_before))


def day_block_to_utc_range(
    day_block: DayBlock,
    contractor_tz: ZoneInfo,
) -> tuple[datetime, datetime]:
    """Convert a DayBlock (date + start_time + end_time) to a UTC datetime range."""
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
    return local_start.astimezone(_UTC), local_end.astimezone(_UTC)


def haversine_distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Compute approximate great-circle distance in km using the Haversine formula."""
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return _EARTH_RADIUS_KM * c
