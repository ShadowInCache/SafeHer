"""Nearby safety locations, backed by real OpenStreetMap data.

Why OSM/Overpass rather than Google Places: SafeHer has no Places API key
provisioned, and the alternative — the approach the reference project used —
is to hand the query string to a `google.com/maps/search?q=police+station`
URL and let the browser do it. That returns no coordinates, no distances and
no structured results, so the app could not honestly show "2.3 km away" for
anything. Overpass is keyless, returns real tagged coordinates, and lets us
compute genuine distances.

Nothing here invents a place. If Overpass is unreachable or returns nothing
in range, the caller gets an empty list and the UI says so.
"""

from __future__ import annotations

import logging
import math
import time
from typing import Any, Iterable

import httpx

logger = logging.getLogger(__name__)

OVERPASS_ENDPOINT = "https://overpass-api.de/api/interpreter"
REQUEST_TIMEOUT_SECONDS = 20.0

# The public Overpass instance rate-limits aggressively. Safety locations move
# on the order of months, so a short cache keyed on a ~110 m grid square costs
# the user nothing in accuracy and keeps a screen that refreshes on every
# resume from burning the shared quota.
_CACHE_TTL_SECONDS = 300.0
_CACHE_MAX_ENTRIES = 64
_cache: dict[tuple, tuple[float, list[dict[str, Any]]]] = {}


class PlacesRateLimited(RuntimeError):
    """Overpass refused the request because we (or the shared public instance)
    are over quota. Distinct from an outage — retrying shortly will work."""


def _cache_key(lat: float, lng: float, radius: int, categories: tuple[str, ...]) -> tuple:
    return (round(lat, 3), round(lng, 3), radius, categories)

# Category -> the OSM tag filters that genuinely represent it.
_CATEGORY_FILTERS: dict[str, tuple[str, ...]] = {
    "police": ('["amenity"="police"]',),
    "hospital": ('["amenity"="hospital"]', '["amenity"="clinic"]'),
    "pharmacy": ('["amenity"="pharmacy"]',),
    "transit": ('["highway"="bus_stop"]', '["railway"="station"]', '["public_transport"="station"]'),
    "shelter": ('["amenity"="shelter"]', '["social_facility"="shelter"]'),
    "fire_station": ('["amenity"="fire_station"]',),
}

SUPPORTED_CATEGORIES = tuple(_CATEGORY_FILTERS)


def _haversine_metres(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    earth_radius_m = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * earth_radius_m * math.asin(math.sqrt(a))


def _build_query(lat: float, lng: float, radius_m: int, categories: Iterable[str]) -> str:
    clauses: list[str] = []
    for category in categories:
        for tag_filter in _CATEGORY_FILTERS.get(category, ()):
            # node + way covers both point POIs and building footprints.
            clauses.append(f'node{tag_filter}(around:{radius_m},{lat},{lng});')
            clauses.append(f'way{tag_filter}(around:{radius_m},{lat},{lng});')
    body = "".join(clauses)
    return f"[out:json][timeout:25];({body});out center tags;"


def _category_of(tags: dict[str, str]) -> str | None:
    amenity = tags.get("amenity")
    if amenity == "police":
        return "police"
    if amenity in {"hospital", "clinic"}:
        return "hospital"
    if amenity == "pharmacy":
        return "pharmacy"
    if amenity == "fire_station":
        return "fire_station"
    if amenity == "shelter" or tags.get("social_facility") == "shelter":
        return "shelter"
    if tags.get("highway") == "bus_stop" or tags.get("railway") == "station":
        return "transit"
    if tags.get("public_transport") == "station":
        return "transit"
    return None


def _element_to_place(element: dict[str, Any], origin_lat: float, origin_lng: float) -> dict[str, Any] | None:
    tags = element.get("tags") or {}
    name = tags.get("name")
    if not name:
        # An unnamed node is not something we can usefully show or navigate to.
        return None

    if element.get("type") == "node":
        lat, lng = element.get("lat"), element.get("lon")
    else:
        center = element.get("center") or {}
        lat, lng = center.get("lat"), center.get("lon")

    if lat is None or lng is None:
        return None

    category = _category_of(tags)
    if category is None:
        return None

    address_parts = [
        tags.get("addr:housenumber"),
        tags.get("addr:street"),
        tags.get("addr:city"),
    ]
    address = " ".join(part for part in address_parts if part) or None

    return {
        "id": f"{element.get('type')}/{element.get('id')}",
        "name": name,
        "category": category,
        "latitude": float(lat),
        "longitude": float(lng),
        "distance_metres": round(_haversine_metres(origin_lat, origin_lng, float(lat), float(lng))),
        "phone": tags.get("phone") or tags.get("contact:phone"),
        "address": address,
        "open_hours": tags.get("opening_hours"),
    }


async def find_nearby(
    *,
    latitude: float,
    longitude: float,
    radius_metres: int = 3000,
    categories: Iterable[str] | None = None,
    limit: int = 40,
) -> list[dict[str, Any]]:
    """Return real nearby safety locations sorted by true distance.

    Raises `httpx.HTTPError` upward so the router can distinguish "the data
    source is down" from "there is genuinely nothing nearby" — the UI must
    not show an empty list for an outage.
    """
    selected = tuple(sorted(categories)) if categories else SUPPORTED_CATEGORIES

    key = _cache_key(latitude, longitude, radius_metres, selected)
    cached = _cache.get(key)
    if cached is not None and (time.monotonic() - cached[0]) < _CACHE_TTL_SECONDS:
        return cached[1][:limit]

    query = _build_query(latitude, longitude, radius_metres, selected)

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS) as client:
        response = await client.post(
            OVERPASS_ENDPOINT,
            data={"data": query},
            headers={"User-Agent": "SafeHer/1.0 (safety app; nearby-safety lookup)"},
        )
        if response.status_code in (429, 504):
            raise PlacesRateLimited(f"Overpass returned {response.status_code}")
        response.raise_for_status()
        payload = response.json()

    places: list[dict[str, Any]] = []
    for element in payload.get("elements", []):
        place = _element_to_place(element, latitude, longitude)
        if place is not None:
            places.append(place)

    places.sort(key=lambda item: item["distance_metres"])

    if len(_cache) >= _CACHE_MAX_ENTRIES:
        oldest = min(_cache, key=lambda k: _cache[k][0])
        _cache.pop(oldest, None)
    _cache[key] = (time.monotonic(), places)

    return places[:limit]
