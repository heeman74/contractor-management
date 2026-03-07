"""Travel time infrastructure for the scheduling engine.

Public API:
    TravelTimeProvider          — Abstract interface for travel time backends.
    OpenRouteServiceProvider    — ORS Directions API implementation (httpx, async).
    TravelTimeCacheService      — PostgreSQL-backed cache with 30-day TTL.
    CachedTravelTimeProvider    — Cache wrapper as a clean TravelTimeProvider.
    apply_safety_margin         — Apply company-configured percentage padding.
    TravelTimeError             — Base exception.
    TravelTimeAPIError          — Non-200 response from the provider.
    TravelTimeUnavailableError  — No fallback and API call failed.
"""

from app.features.scheduling.travel.cache import (
    CachedTravelTimeProvider,
    TravelTimeCacheService,
    apply_safety_margin,
)
from app.features.scheduling.travel.ors_provider import OpenRouteServiceProvider
from app.features.scheduling.travel.provider import (
    TravelTimeAPIError,
    TravelTimeError,
    TravelTimeProvider,
    TravelTimeUnavailableError,
)

__all__ = [
    "TravelTimeProvider",
    "OpenRouteServiceProvider",
    "TravelTimeCacheService",
    "CachedTravelTimeProvider",
    "apply_safety_margin",
    "TravelTimeError",
    "TravelTimeAPIError",
    "TravelTimeUnavailableError",
]
