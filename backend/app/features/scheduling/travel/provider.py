"""Abstract interface for travel time providers.

Custom exceptions and the TravelTimeProvider ABC are defined here.
Any concrete provider (ORS, Google Maps, etc.) must implement
get_travel_seconds() returning seconds as an integer.
"""

from abc import ABC, abstractmethod


class TravelTimeError(Exception):
    """Base exception for all travel time failures."""


class TravelTimeAPIError(TravelTimeError):
    """API returned a non-200 response."""


class TravelTimeUnavailableError(TravelTimeError):
    """No cache fallback available and API call failed."""


class TravelTimeProvider(ABC):
    """Pluggable interface for fetching driving travel times.

    Implementations must return the estimated driving duration in seconds
    between two coordinate pairs. Callers should prefer CachedTravelTimeProvider
    (cache.py) over using a raw provider to avoid exhausting API quota.
    """

    @abstractmethod
    async def get_travel_seconds(
        self,
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
    ) -> int:
        """Return driving travel time in seconds.

        Args:
            origin_lat: Origin latitude in decimal degrees.
            origin_lng: Origin longitude in decimal degrees.
            dest_lat:   Destination latitude in decimal degrees.
            dest_lng:   Destination longitude in decimal degrees.

        Returns:
            Estimated driving duration in whole seconds.

        Raises:
            TravelTimeAPIError: Provider returned a non-200 HTTP response.
            TravelTimeUnavailableError: Provider timed out or is unavailable.
        """
        ...
