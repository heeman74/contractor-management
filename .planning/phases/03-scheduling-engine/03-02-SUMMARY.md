---
phase: 03-scheduling-engine
plan: "02"
subsystem: backend-scheduling-travel-geocoding
tags: [httpx, openrouteservice, postgresql, caching, geocoding, async, abstract-interface]

requires:
  - phase: 03-01
    provides: TravelTimeCache ORM model and scheduling tables in PostgreSQL

provides:
  - TravelTimeProvider ABC (pluggable travel time interface)
  - OpenRouteServiceProvider (ORS Directions API via httpx, lng,lat GeoJSON order)
  - TravelTimeCacheService (PostgreSQL cache, 30-day TTL, bidirectional key, expired fallback)
  - CachedTravelTimeProvider (cache wrapper as clean TravelTimeProvider interface)
  - apply_safety_margin() helper for company-configurable % padding
  - GeocodingProvider ABC (pluggable geocoding interface)
  - GeocodingResult dataclass (lat, lng, formatted_address, confidence)
  - ORSGeocodingProvider (ORS Pelias geocoding via httpx)

affects: [03-03-availability-engine, 03-04-conflict-detection, scheduling-service]

tech-stack:
  added: []
  patterns:
    - Pluggable provider interface pattern (ABC) for travel time and geocoding — swap ORS for Google Maps without touching business logic
    - Bidirectional cache key normalization: sort coordinate pairs so A->B == B->A halves cache entries and ORS quota usage
    - Coordinate rounding to 3 decimal places (~100m precision) for cache key stability
    - Expired cache fallback: serve stale value when API is down rather than failing availability calculation
    - INSERT ON CONFLICT DO UPDATE (upsert) for race-condition-free cache population
    - GeoJSON coordinate order awareness: ORS API requires lng,lat (not lat,lng) in all endpoints

key-files:
  created:
    - backend/app/features/scheduling/travel/__init__.py
    - backend/app/features/scheduling/travel/provider.py
    - backend/app/features/scheduling/travel/ors_provider.py
    - backend/app/features/scheduling/travel/cache.py
    - backend/app/features/scheduling/geocoding/__init__.py
    - backend/app/features/scheduling/geocoding/provider.py
    - backend/app/features/scheduling/geocoding/ors_geocoder.py
  modified: []

key-decisions:
  - "httpx.AsyncClient (not openrouteservice-py) — the official library is synchronous and blocks the event loop"
  - "Bidirectional key: sort coordinate pairs lexicographically so A->B == B->A — halves ORS API calls for round-trip scheduling"
  - "Expired cache entries kept as fallback — availability calculation degrades gracefully when ORS API is down"
  - "INSERT ON CONFLICT DO UPDATE for cache upsert — atomic, no ORM read-then-write race condition"
  - "GeoJSON coordinate order: ORS uses lng,lat in all coordinate strings and response arrays"
  - "GeocodingProvider returns None on empty results (no match) vs raises GeocodingError on API failures — callers must distinguish both"
  - "CachedTravelTimeProvider wraps cache with bound company_id — callers depend only on TravelTimeProvider ABC"

patterns-established:
  - "Provider interface pattern: all external API integrations go behind an ABC so the scheduling engine is decoupled from specific vendors"
  - "Cache-aside with fallback: fetch from cache first, refresh from API on miss/expiry, serve stale on API failure"

requirements-completed: [SCHED-06]

duration: 7min
completed: 2026-03-07
---

# Phase 3 Plan 2: Travel Time and Geocoding Infrastructure Summary

**Pluggable travel time and geocoding provider interfaces with ORS Directions/Pelias implementations, PostgreSQL cache (30-day TTL, bidirectional key), and expired-entry fallback for resilient availability calculations.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-07T01:50:00Z
- **Completed:** 2026-03-07T01:57:00Z
- **Tasks:** 2
- **Files modified:** 7 created, 0 modified

## Accomplishments

- Travel time provider interface (TravelTimeProvider ABC) with ORS Directions implementation using httpx.AsyncClient — correctly uses GeoJSON lng,lat coordinate order
- PostgreSQL-backed cache (TravelTimeCacheService) with 30-day TTL, bidirectional key normalization (A->B == B->A halves API calls), expired-entry fallback, and race-condition-free upsert via INSERT ON CONFLICT DO UPDATE
- CachedTravelTimeProvider wraps cache as a clean TravelTimeProvider so the scheduling service has no caching knowledge leakage
- Geocoding provider interface (GeocodingProvider ABC) with ORS Pelias implementation — returns None on empty results vs raises GeocodingError on API failures
- apply_safety_margin() helper for company-configurable percentage padding on raw travel times

## Task Commits

Each task was committed atomically:

1. **Task 1: Travel time provider interface, ORS implementation, and PostgreSQL cache** - `28c9ea3` (feat)
2. **Task 2: Geocoding provider interface and ORS Pelias implementation** - `2d75092` (feat)

## Files Created/Modified

- `backend/app/features/scheduling/travel/provider.py` — TravelTimeProvider ABC + TravelTimeError hierarchy
- `backend/app/features/scheduling/travel/ors_provider.py` — OpenRouteServiceProvider via httpx with GeoJSON lng,lat order
- `backend/app/features/scheduling/travel/cache.py` — TravelTimeCacheService + CachedTravelTimeProvider + apply_safety_margin()
- `backend/app/features/scheduling/travel/__init__.py` — Public API exports
- `backend/app/features/scheduling/geocoding/provider.py` — GeocodingProvider ABC + GeocodingResult dataclass + GeocodingError
- `backend/app/features/scheduling/geocoding/ors_geocoder.py` — ORSGeocodingProvider via httpx
- `backend/app/features/scheduling/geocoding/__init__.py` — Public API exports

## Decisions Made

- Used `httpx.AsyncClient` (not `openrouteservice-py`) — the official Python SDK is synchronous and blocks the async event loop
- Bidirectional key: coordinate pairs sorted lexicographically so (A->B) and (B->A) share a cache entry — halves ORS API quota usage for round-trip scheduling scenarios
- Expired cache entries are served as fallback on API failure — availability calculation degrades gracefully instead of crashing when ORS is down
- INSERT ON CONFLICT DO UPDATE for cache upsert — atomic, no race condition between concurrent requests populating the same key
- GeocodingProvider returns `None` on empty results (no geocodable match) vs raises `GeocodingError` on API-level failures — callers must handle both cases explicitly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ruff B904: raise-without-from in exception handler**
- **Found during:** Task 1 (TravelTimeCacheService verification — ruff check)
- **Issue:** `raise TravelTimeUnavailableError(...)` inside an `except Exception` block without `from exc` chain violated ruff B904 (within except clause, raise with `from`).
- **Fix:** Changed `except Exception:` to `except Exception as exc:` and appended `from exc` to the raise statement.
- **Files modified:** `backend/app/features/scheduling/travel/cache.py`
- **Verification:** `ruff check app/features/scheduling/travel/` passes.
- **Committed in:** `28c9ea3` (part of Task 1 commit)

**2. [Rule 1 - Bug] ruff format: long string lines in ors_provider.py and ors_geocoder.py**
- **Found during:** Task 1 and Task 2 verification (ruff format --check)
- **Issue:** Error message f-strings in exception handlers exceeded the line length limit and were not reformatted to match ruff's style.
- **Fix:** Ran `uv run ruff format` on both travel/ and geocoding/ directories; ruff collapsed the multi-line strings to single lines within the character limit.
- **Files modified:** `backend/app/features/scheduling/travel/ors_provider.py`, `backend/app/features/scheduling/geocoding/ors_geocoder.py`
- **Verification:** `ruff format --check` reports "N files already formatted".
- **Committed in:** `28c9ea3` and `2d75092` (part of respective task commits)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 — bug/lint)
**Impact on plan:** Both auto-fixes are ruff compliance issues, not logic changes. No scope creep.

## Issues Encountered

None — all planned functionality implemented on first pass.

## User Setup Required

None - no external service configuration required at this stage. ORS API key will be wired in via environment variable (`ORS_API_KEY`) when the scheduling service is assembled in Plan 03-03.

## Next Phase Readiness

- Travel time infrastructure complete and importable — Plan 03-03 (SchedulingService) can consume TravelTimeProvider directly
- Geocoding infrastructure complete — job site address-to-coordinates flow ready
- Both providers use pluggable ABCs — ORS can be swapped for Google Maps in future without touching scheduling logic
- apply_safety_margin() ready for company-configurable scheduling buffer

---
*Phase: 03-scheduling-engine*
*Completed: 2026-03-07*
