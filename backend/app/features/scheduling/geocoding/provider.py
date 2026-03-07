"""Abstract interface for geocoding providers.

Defines GeocodingResult dataclass and the GeocodingProvider ABC.
Any concrete provider (ORS Pelias, Google Maps, Nominatim, etc.) must implement
geocode() and reverse_geocode().
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass


class GeocodingError(Exception):
    """Raised when a geocoding provider API call fails.

    Distinct from returning None (no result found) — this indicates an
    actual API-level failure such as a non-200 response or network timeout.
    """


@dataclass
class GeocodingResult:
    """Structured output from a successful geocoding operation.

    Attributes:
        latitude:          WGS-84 latitude in decimal degrees.
        longitude:         WGS-84 longitude in decimal degrees.
        formatted_address: Human-readable address string from the provider.
        confidence:        Provider-reported match confidence, 0.0 (worst) to 1.0 (best).
    """

    latitude: float
    longitude: float
    formatted_address: str
    confidence: float


class GeocodingProvider(ABC):
    """Pluggable interface for address-to-coordinate and coordinate-to-address lookups.

    Implementations should raise GeocodingError on API failures and return None
    when no result is found (as opposed to an error state).  This distinction
    allows callers to distinguish between "the API is broken" and "no match".
    """

    @abstractmethod
    async def geocode(self, address: str) -> GeocodingResult | None:
        """Geocode an address string to coordinates.

        Args:
            address: Free-text address to geocode (e.g. "123 Main St, Springfield").

        Returns:
            GeocodingResult with lat/lng and metadata, or None if no result found.

        Raises:
            GeocodingError: Provider returned an error response or timed out.
        """
        ...

    @abstractmethod
    async def reverse_geocode(self, lat: float, lng: float) -> str | None:
        """Reverse geocode coordinates to a human-readable address string.

        Args:
            lat: Latitude in decimal degrees.
            lng: Longitude in decimal degrees.

        Returns:
            Formatted address string, or None if no result found.

        Raises:
            GeocodingError: Provider returned an error response or timed out.
        """
        ...
