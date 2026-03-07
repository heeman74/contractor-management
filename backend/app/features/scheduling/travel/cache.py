"""PostgreSQL-backed travel time cache with 30-day TTL and bidirectional key normalization.

Key design decisions:
- Coordinates rounded to 3 decimal places (~100m precision) to maximize cache hits.
- Bidirectional key: (A->B) and (B->A) are treated as identical lookups, halving
  the number of ORS API calls and cache entries for round-trip scheduling scenarios.
- Expired entries are kept as a fallback: if the API is unavailable, we serve the
  stale value rather than crashing the availability calculation.
- INSERT ON CONFLICT UPDATE (upsert) keeps the table footprint minimal — no
  duplicate rows accumulate from retries.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.scheduling.models import TravelTimeCache
from app.features.scheduling.travel.provider import (
    TravelTimeProvider,
    TravelTimeUnavailableError,
)

_CACHE_TTL_DAYS = 30


def _round_coord(value: float) -> float:
    """Round coordinate to 3 decimal places (~100m precision cache key)."""
    return round(value, 3)


def _normalize_key(
    lat1: float,
    lng1: float,
    lat2: float,
    lng2: float,
) -> tuple[float, float, float, float]:
    """Return a canonical (lat1, lng1, lat2, lng2) that treats A->B == B->A.

    The smaller coordinate pair (lexicographic sort of the string representation)
    is always placed first so that the key is identical regardless of travel
    direction.
    """
    pair_a = (lat1, lng1)
    pair_b = (lat2, lng2)
    if pair_a <= pair_b:
        return (pair_a[0], pair_a[1], pair_b[0], pair_b[1])
    return (pair_b[0], pair_b[1], pair_a[0], pair_a[1])


def apply_safety_margin(seconds: int, margin_percent: float) -> int:
    """Apply a company-configurable percentage safety margin to a travel time.

    Args:
        seconds:        Raw travel time in seconds from the provider.
        margin_percent: Additional percentage to add (e.g. 20 means +20%).

    Returns:
        Padded duration in whole seconds.
    """
    return int(seconds * (1 + margin_percent / 100))


class TravelTimeCacheService:
    """PostgreSQL-backed cache for ORS travel time results.

    Wraps a raw TravelTimeProvider to add:
    - Coordinate normalization and rounding for cache key stability.
    - Bidirectional key deduplication (A->B == B->A).
    - 30-day TTL with expired-entry fallback when the API is down.
    - Upsert on success to keep the table tidy.

    The caller is responsible for passing a valid AsyncSession; do NOT call
    db.commit() inside this service — the get_db dependency handles that.
    """

    def __init__(self, db: AsyncSession, provider: TravelTimeProvider) -> None:
        self._db = db
        self._provider = provider

    async def get_travel_seconds(
        self,
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
        company_id: uuid.UUID,
    ) -> int:
        """Return driving duration in seconds, using cache where possible.

        Algorithm:
        1. Round and normalize coordinates into a canonical cache key.
        2. Query TravelTimeCache for a matching entry (scoped by company_id).
        3. If found and fresh (< 30 days): return cached value immediately.
        4. If found but stale: keep as fallback, attempt API refresh.
        5. If not found: call the provider directly.
        6. On provider success: upsert the cache entry, return fresh value.
        7. On provider failure: return stale fallback or raise TravelTimeUnavailableError.

        Args:
            origin_lat:  Origin latitude.
            origin_lng:  Origin longitude.
            dest_lat:    Destination latitude.
            dest_lng:    Destination longitude.
            company_id:  Tenant scoping for the cache lookup.

        Returns:
            Driving duration in whole seconds.

        Raises:
            TravelTimeUnavailableError: API failed and no fallback is cached.
        """
        # Step 1: normalize key
        r_lat1, r_lng1, r_lat2, r_lng2 = _normalize_key(
            _round_coord(origin_lat),
            _round_coord(origin_lng),
            _round_coord(dest_lat),
            _round_coord(dest_lng),
        )

        # Step 2: look up cache entry
        stmt = select(TravelTimeCache).where(
            TravelTimeCache.company_id == company_id,
            TravelTimeCache.lat1 == r_lat1,
            TravelTimeCache.lng1 == r_lng1,
            TravelTimeCache.lat2 == r_lat2,
            TravelTimeCache.lng2 == r_lng2,
        )
        result = await self._db.execute(stmt)
        cached: TravelTimeCache | None = result.scalar_one_or_none()

        now = datetime.now(UTC)
        ttl_boundary = now - timedelta(days=_CACHE_TTL_DAYS)

        # Step 3: fresh cache hit — serve immediately
        if cached is not None and cached.fetched_at >= ttl_boundary:
            return cached.duration_seconds

        # Steps 4/5: stale or missing — try the provider
        fallback: int | None = cached.duration_seconds if cached is not None else None

        try:
            fresh_seconds = await self._provider.get_travel_seconds(
                origin_lat, origin_lng, dest_lat, dest_lng
            )
        except Exception as exc:
            # Step 7: provider failed — use stale fallback or raise
            if fallback is not None:
                return fallback
            raise TravelTimeUnavailableError(
                f"Travel time unavailable for ({origin_lat},{origin_lng}) -> "
                f"({dest_lat},{dest_lng}) and no cached fallback exists."
            ) from exc

        # Step 6: upsert fresh value
        await self._upsert(
            company_id=company_id,
            lat1=r_lat1,
            lng1=r_lng1,
            lat2=r_lat2,
            lng2=r_lng2,
            duration_seconds=fresh_seconds,
        )
        return fresh_seconds

    async def _upsert(
        self,
        company_id: uuid.UUID,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float,
        duration_seconds: int,
    ) -> None:
        """INSERT or UPDATE a cache entry.

        Uses raw SQL INSERT ... ON CONFLICT DO UPDATE to atomically upsert
        without an ORM read-then-write cycle, avoiding race conditions when
        multiple concurrent requests populate the same cache key simultaneously.
        """
        sql = text(
            """
            INSERT INTO travel_time_cache
                (company_id, lat1, lng1, lat2, lng2, duration_seconds, fetched_at)
            VALUES
                (:company_id, :lat1, :lng1, :lat2, :lng2, :duration_seconds, now())
            ON CONFLICT (company_id, lat1, lng1, lat2, lng2)
            DO UPDATE SET
                duration_seconds = EXCLUDED.duration_seconds,
                fetched_at       = EXCLUDED.fetched_at
            """
        )
        await self._db.execute(
            sql,
            {
                "company_id": company_id,
                "lat1": lat1,
                "lng1": lng1,
                "lat2": lat2,
                "lng2": lng2,
                "duration_seconds": duration_seconds,
            },
        )


class CachedTravelTimeProvider(TravelTimeProvider):
    """Wraps TravelTimeCacheService as a clean TravelTimeProvider interface.

    Callers that only need travel time durations can depend on the abstract
    TravelTimeProvider type without knowing that caching is involved.
    The company_id is bound at construction time so the caller does not need
    to thread it through every call.

    Args:
        cache_service: Initialized TravelTimeCacheService instance.
        company_id:    Tenant identifier for cache scoping.
    """

    def __init__(
        self,
        cache_service: TravelTimeCacheService,
        company_id: uuid.UUID,
    ) -> None:
        self._cache_service = cache_service
        self._company_id = company_id

    async def get_travel_seconds(
        self,
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
    ) -> int:
        """Delegate to the cache service with the bound company_id."""
        return await self._cache_service.get_travel_seconds(
            origin_lat=origin_lat,
            origin_lng=origin_lng,
            dest_lat=dest_lat,
            dest_lng=dest_lng,
            company_id=self._company_id,
        )
