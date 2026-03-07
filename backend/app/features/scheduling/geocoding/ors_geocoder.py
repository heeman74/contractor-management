"""OpenRouteService Pelias geocoding implementation.

Uses httpx.AsyncClient to call ORS Geocoding API endpoints:
- /geocode/search  — forward geocoding (address -> coordinates)
- /geocode/reverse — reverse geocoding (coordinates -> address)

ORS Geocoding returns GeoJSON FeatureCollections where coordinates are in
GeoJSON order: [longitude, latitude].  The confidence score is available
as features[0].properties.confidence (0.0 to 1.0).
"""

import httpx

from app.features.scheduling.geocoding.provider import (
    GeocodingError,
    GeocodingProvider,
    GeocodingResult,
)

_ORS_GEOCODE_SEARCH_URL = "https://api.openrouteservice.org/geocode/search"
_ORS_GEOCODE_REVERSE_URL = "https://api.openrouteservice.org/geocode/reverse"
_REQUEST_TIMEOUT = 10.0


class ORSGeocodingProvider(GeocodingProvider):
    """Geocoding provider backed by OpenRouteService Pelias API.

    ORS Geocoding is built on top of Pelias, an open-source geocoder.
    The API accepts a free-text address or coordinate pair and returns
    GeoJSON FeatureCollections.

    Coordinate order note (GeoJSON standard):
        All coordinate arrays in GeoJSON are [longitude, latitude], which is
        the opposite of the more intuitive (lat, lng) order.  This provider
        correctly swaps to return GeocodingResult.latitude and .longitude in
        the conventional (lat first) order.

    Args:
        api_key: ORS API key (from environment — never hardcode).
        client:  Shared httpx.AsyncClient.  Lifecycle managed by caller.
    """

    def __init__(self, api_key: str, client: httpx.AsyncClient) -> None:
        self._api_key = api_key
        self._client = client

    async def geocode(self, address: str) -> GeocodingResult | None:
        """Forward geocode an address string to coordinates via ORS Pelias.

        Returns None if no features are found in the response (not an error).
        Raises GeocodingError on HTTP or network failures.

        Args:
            address: Free-text address string to geocode.

        Returns:
            GeocodingResult or None if no match.

        Raises:
            GeocodingError: ORS returned non-200 or request timed out.
        """
        params = {
            "api_key": self._api_key,
            "text": address,
            "size": 1,
        }

        try:
            response = await self._client.get(
                _ORS_GEOCODE_SEARCH_URL,
                params=params,
                timeout=_REQUEST_TIMEOUT,
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise GeocodingError(
                f"ORS geocode/search returned {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.TimeoutException as exc:
            raise GeocodingError("ORS geocode/search request timed out") from exc

        data = response.json()
        features = data.get("features", [])
        if not features:
            return None

        feature = features[0]
        # GeoJSON coordinates: [longitude, latitude]
        coords = feature["geometry"]["coordinates"]
        lng: float = coords[0]
        lat: float = coords[1]
        props = feature["properties"]
        formatted_address: str = props.get("label", "")
        confidence: float = float(props.get("confidence", 0.0))

        return GeocodingResult(
            latitude=lat,
            longitude=lng,
            formatted_address=formatted_address,
            confidence=confidence,
        )

    async def reverse_geocode(self, lat: float, lng: float) -> str | None:
        """Reverse geocode coordinates to an address string via ORS Pelias.

        Returns None if no features are found in the response (not an error).
        Raises GeocodingError on HTTP or network failures.

        Args:
            lat: Latitude in decimal degrees.
            lng: Longitude in decimal degrees.

        Returns:
            Formatted address string or None if no match.

        Raises:
            GeocodingError: ORS returned non-200 or request timed out.
        """
        params = {
            "api_key": self._api_key,
            "point.lat": lat,
            "point.lon": lng,
            "size": 1,
        }

        try:
            response = await self._client.get(
                _ORS_GEOCODE_REVERSE_URL,
                params=params,
                timeout=_REQUEST_TIMEOUT,
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise GeocodingError(
                f"ORS geocode/reverse returned {exc.response.status_code}: "
                f"{exc.response.text[:200]}"
            ) from exc
        except httpx.TimeoutException as exc:
            raise GeocodingError("ORS geocode/reverse request timed out") from exc

        data = response.json()
        features = data.get("features", [])
        if not features:
            return None

        label: str = features[0]["properties"].get("label", "")
        return label if label else None
