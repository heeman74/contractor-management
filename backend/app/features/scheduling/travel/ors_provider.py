"""OpenRouteService implementation of TravelTimeProvider.

Uses httpx.AsyncClient to call the ORS Directions API (driving-car profile).
ORS follows GeoJSON coordinate order: longitude first, then latitude.
Do NOT use the synchronous openrouteservice-py library — it blocks the event loop.
"""

import httpx

from app.features.scheduling.travel.provider import (
    TravelTimeAPIError,
    TravelTimeProvider,
    TravelTimeUnavailableError,
)

_ORS_DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions/driving-car"
_REQUEST_TIMEOUT = 10.0


class OpenRouteServiceProvider(TravelTimeProvider):
    """Travel time provider backed by OpenRouteService Directions API.

    The ORS Directions endpoint accepts coordinates as GeoJSON-order strings:
    "{longitude},{latitude}" (NOT latitude-first).  This is the most common
    source of silent bugs when integrating with ORS — the API returns HTTP 200
    even when coordinates are reversed if they happen to be valid, yielding
    wildly incorrect travel times.

    Args:
        api_key: ORS API key (from environment — never hardcode).
        client:  Shared httpx.AsyncClient.  Callers are responsible for
                 lifecycle management (open/close).  This allows the client
                 to be reused across requests and configured with connection
                 pooling at the application level.
    """

    def __init__(self, api_key: str, client: httpx.AsyncClient) -> None:
        self._api_key = api_key
        self._client = client

    async def get_travel_seconds(
        self,
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
    ) -> int:
        """Fetch driving duration from ORS Directions API.

        IMPORTANT: ORS uses GeoJSON coordinate order — longitude comes before
        latitude in the coordinate string.

        Returns:
            Driving duration in whole seconds.

        Raises:
            TravelTimeAPIError: ORS returned a non-2xx HTTP status.
            TravelTimeUnavailableError: Network timeout or connection error.
        """
        # ORS GeoJSON order: longitude,latitude
        origin_coord = f"{origin_lng},{origin_lat}"
        dest_coord = f"{dest_lng},{dest_lat}"

        params = {
            "api_key": self._api_key,
            "start": origin_coord,
            "end": dest_coord,
        }

        try:
            response = await self._client.get(
                _ORS_DIRECTIONS_URL,
                params=params,
                timeout=_REQUEST_TIMEOUT,
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise TravelTimeAPIError(
                f"ORS Directions API returned {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.TimeoutException as exc:
            raise TravelTimeUnavailableError("ORS Directions API request timed out") from exc

        data = response.json()
        try:
            duration_float: float = data["features"][0]["properties"]["segments"][0]["duration"]
        except (KeyError, IndexError, TypeError) as exc:
            raise TravelTimeAPIError(f"Unexpected ORS response structure: {exc}") from exc

        return int(duration_float)
