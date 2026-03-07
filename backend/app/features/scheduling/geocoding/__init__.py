"""Geocoding infrastructure for the scheduling engine.

Public API:
    GeocodingProvider    — Abstract interface for geocoding backends.
    GeocodingResult      — Structured result dataclass (lat, lng, address, confidence).
    ORSGeocodingProvider — ORS Pelias implementation via httpx (async).
    GeocodingError       — Exception raised on API failures (not on empty results).
"""

from app.features.scheduling.geocoding.ors_geocoder import ORSGeocodingProvider
from app.features.scheduling.geocoding.provider import (
    GeocodingError,
    GeocodingProvider,
    GeocodingResult,
)

__all__ = [
    "GeocodingProvider",
    "GeocodingResult",
    "ORSGeocodingProvider",
    "GeocodingError",
]
