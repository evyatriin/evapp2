from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import logging
import math
import re
from typing import Any, Iterable, Optional

import httpx

from config import settings
from supabase_client import service_supabase, supabase
from metrics_tracker import track_external_api

logger = logging.getLogger(__name__)

HERE_CACHE_MAX_AGE = timedelta(hours=12)
HERE_CACHE_MAX_RESULTS = 100


SOURCE_PRIORITY: dict[str, int] = {
    "evraahein_canonical": 100,
    "evraahein_db": 90,
    "here_ev": 80,
    "google_places": 70,
    "open_charge_map": 60,
}


@dataclass
class NormalizedCharger:
    source_name: str
    source_station_id: str
    name: str
    latitude: float
    longitude: float
    address: Optional[str] = None
    provider: Optional[str] = None
    connector_types: list[str] = field(default_factory=list)
    power_kw: Optional[float] = None
    status: str = "Operational"
    availability_status: str = "Unknown"
    amenities: list[str] = field(default_factory=list)
    access_type: str = "Public"
    access_instructions: Optional[str] = None
    is_private: bool = False
    station_record_id: Optional[str] = None
    host_name: Optional[str] = None
    host_phone: Optional[str] = None
    host_upi_id: Optional[str] = None
    price_per_kwh: Optional[float] = None
    price_per_session: Optional[float] = None
    available_from: Optional[str] = None
    available_to: Optional[str] = None
    available_days: list[str] = field(default_factory=list)
    is_accepting_requests: bool = False
    parking_notes: Optional[str] = None
    house_rules: Optional[str] = None
    verified_by: str = "EVraahein"
    freshness_score: Optional[int] = None
    last_verified: Optional[str] = None
    rating: Optional[float] = None
    user_rating_count: Optional[int] = None
    average_rating: Optional[float] = None
    total_reviews: int = 0
    total_checkins: int = 0
    canonical_id: Optional[str] = None
    raw_payload: dict[str, Any] = field(default_factory=dict)
    distance_m: Optional[float] = None
    data_sources: list[str] = field(default_factory=list)
    source_priority: int = 0

    def __post_init__(self) -> None:
        self.name = self.name.strip() or "Charging Station"
        self.connector_types = _unique_strings(self.connector_types)
        self.amenities = _unique_strings(self.amenities)
        self.available_days = _unique_strings(self.available_days)
        self.verified_by = self.verified_by or "EVraahein"
        self.source_priority = SOURCE_PRIORITY.get(self.source_name, 0)
        if not self.data_sources:
            self.data_sources = [self.source_name]

    @property
    def response_id(self) -> str:
        return self.canonical_id or f"{self.source_name}:{self.source_station_id}"

    @property
    def normalized_name(self) -> str:
        return _normalize_station_name(self.name)

    @property
    def normalized_address(self) -> str:
        return _normalize_address(self.address)

    def to_response_json(self) -> dict[str, Any]:
        return {
            "id": self.response_id,
            "name": self.name,
            "location": {
                "lat": self.latitude,
                "lng": self.longitude,
            },
            "provider": self.provider,
            "status": self.status,
            "last_verified": self.last_verified,
            "verified_by": self.verified_by,
            "connectors": self.connector_types,
            "amenities": self.amenities,
            "freshness_score": self.freshness_score,
            "issue_type": None,
            "rating": self.rating if self.rating is not None else self.average_rating,
            "user_rating_count": self.user_rating_count or self.total_reviews,
            "address": self.address,
            "cost": None,
            "is_private": self.is_private,
            "access_type": self.access_type,
            "availability_status": self.availability_status,
            "data_sources": sorted(set(self.data_sources)),
            "distance_m": self.distance_m,
            "source_count": len(set(self.data_sources)),
            "station_record_id": self.station_record_id,
            "host_name": self.host_name,
            "host_phone": self.host_phone,
            "host_upi_id": self.host_upi_id,
            "price_per_kwh": self.price_per_kwh,
            "price_per_session": self.price_per_session,
            "available_from": self.available_from,
            "available_to": self.available_to,
            "available_days": self.available_days,
            "is_accepting_requests": self.is_accepting_requests,
            "parking_notes": self.parking_notes,
            "house_rules": self.house_rules,
        }

    def to_canonical_upsert(self) -> dict[str, Any]:
        return {
            "id": self.canonical_id,
            "name": self.name,
            "normalized_name": self.normalized_name,
            "address": self.address,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "provider": self.provider,
            "connector_types": self.connector_types,
            "power_kw": self.power_kw,
            "status": self.status,
            "availability_status": self.availability_status,
            "amenities": self.amenities,
            "access_type": self.access_type,
            "access_instructions": self.access_instructions,
            "is_private": self.is_private,
            "verified_by": self.verified_by,
            "freshness_score": self.freshness_score,
            "last_verified_at": self.last_verified,
            "average_rating": self.average_rating if self.average_rating is not None else self.rating,
            "total_reviews": self.total_reviews or self.user_rating_count or 0,
            "total_checkins": self.total_checkins,
            "source_count": len(set(self.data_sources)),
            "metadata": {"data_sources": sorted(set(self.data_sources))},
        }


async def aggregate_chargers_nearby(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    sources = await _fetch_all_sources(latitude, longitude, radius_km)
    merged = _merge_deduped_chargers(sources)
    await _persist_canonical_results(merged)
    merged.sort(key=lambda charger: (charger.distance_m is None, charger.distance_m or math.inf, charger.name.lower()))
    return merged


async def _fetch_all_sources(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    results = await _gather_optional(
        _fetch_canonical_db_nearby(latitude, longitude, radius_km),
        _fetch_legacy_db_stations(latitude, longitude, radius_km),
        _fetch_here_ev_nearby(latitude, longitude, radius_km),
        _fetch_google_places_nearby(latitude, longitude, radius_km),
        _fetch_open_charge_map_nearby(latitude, longitude, radius_km),
    )
    chargers: list[NormalizedCharger] = []
    for batch in results:
        chargers.extend(batch)
    return chargers


async def _gather_optional(*coroutines: Any) -> list[list[NormalizedCharger]]:
    settled = await asyncio.gather(*coroutines, return_exceptions=True)
    results: list[list[NormalizedCharger]] = []
    for batch in settled:
        if isinstance(batch, Exception):
            exc = batch
            logger.warning("Charger source fetch failed: %s", exc)
            batch = []
        results.append(batch)
    return results


async def _fetch_canonical_db_nearby(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    client = service_supabase or supabase
    if not client:
        return []

    try:
        response = client.rpc(
            "nearby_canonical_chargers",
            {
                "lat": latitude,
                "long": longitude,
                "radius_km": radius_km,
            },
        ).execute()
    except Exception as exc:
        logger.info("Canonical charger RPC unavailable: %s", exc)
        return []

    chargers: list[NormalizedCharger] = []
    for row in response.data or []:
        metadata = row.get("metadata") or {}
        data_sources = metadata.get("data_sources") if isinstance(metadata, dict) else None
        chargers.append(
            NormalizedCharger(
                source_name="evraahein_canonical",
                source_station_id=str(row["id"]),
                canonical_id=str(row["id"]),
                name=row["name"],
                latitude=row["latitude"],
                longitude=row["longitude"],
                address=row.get("address"),
                provider=row.get("provider"),
                connector_types=list(row.get("connector_types") or []),
                power_kw=row.get("power_kw"),
                status=row.get("status") or "Operational",
                availability_status=row.get("availability_status") or "Unknown",
                amenities=list(row.get("amenities") or []),
                access_type=row.get("access_type") or "Public",
                access_instructions=row.get("access_instructions"),
                is_private=bool(row.get("is_private") or False),
                verified_by=row.get("verified_by") or "EVraahein",
                freshness_score=row.get("freshness_score"),
                last_verified=_as_iso(row.get("last_verified_at")),
                average_rating=_safe_float(row.get("average_rating")),
                total_reviews=int(row.get("total_reviews") or 0),
                total_checkins=int(row.get("total_checkins") or 0),
                distance_m=_safe_float(row.get("distance_m")),
                data_sources=list(data_sources or ["evraahein_canonical"]),
                raw_payload=row,
            )
        )
    return chargers


async def _fetch_legacy_db_stations(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    client = supabase
    if not client:
        return []

    rows: list[dict[str, Any]] = []
    try:
        response = client.rpc(
            "nearby_stations",
            {
                "lat": latitude,
                "long": longitude,
                "radius_km": radius_km,
            },
        ).execute()
        rows = response.data or []
    except Exception as rpc_error:
        logger.info("Legacy nearby_stations RPC unavailable: %s", rpc_error)
        lat_offset = radius_km / 111.0
        lng_offset = radius_km / max(
            1.0,
            111.0 * abs(math.cos(math.radians(latitude))),
        )
        try:
            response = (
                client.table("charging_stations")
                .select("*")
                .eq("verification_status", "verified")
                .gte("latitude", latitude - lat_offset)
                .lte("latitude", latitude + lat_offset)
                .gte("longitude", longitude - lng_offset)
                .lte("longitude", longitude + lng_offset)
                .limit(250)
                .execute()
            )
            rows = response.data or []
        except Exception as exc:
            logger.warning("Legacy DB charger fetch failed: %s", exc)
            return []

    chargers: list[NormalizedCharger] = []
    for row in rows:
        if not _legacy_station_is_visible(row):
            continue
        lat = _safe_float(row.get("latitude"))
        lng = _safe_float(row.get("longitude"))
        if lat is None or lng is None:
            continue

        chargers.append(
            NormalizedCharger(
                source_name="evraahein_db",
                source_station_id=str(row.get("id") or f"{lat}:{lng}:{row.get('name', '')}"),
                name=row.get("name") or "Charging Station",
                latitude=lat,
                longitude=lng,
                address=row.get("address"),
                provider=row.get("provider"),
                connector_types=list(row.get("connector_types") or row.get("connectors") or []),
                power_kw=_safe_float(row.get("power_kw")),
                status=_map_legacy_status(row.get("status")),
                availability_status=row.get("availability_status") or "Unknown",
                amenities=list(row.get("amenities") or []),
                access_type=row.get("access_type") or "Public",
                access_instructions=row.get("access_instructions"),
                is_private=bool(row.get("is_private") or False),
                station_record_id=str(row.get("id")) if row.get("id") is not None else None,
                host_name=row.get("host_name"),
                host_phone=row.get("host_phone"),
                host_upi_id=row.get("host_upi_id"),
                price_per_kwh=_safe_float(row.get("price_per_kwh")),
                price_per_session=_safe_float(row.get("price_per_session")),
                available_from=str(row.get("available_from")) if row.get("available_from") else None,
                available_to=str(row.get("available_to")) if row.get("available_to") else None,
                available_days=list(row.get("available_days") or []),
                is_accepting_requests=bool(row.get("is_accepting_requests") or False),
                parking_notes=row.get("parking_notes"),
                house_rules=row.get("house_rules"),
                verified_by="EVraahein Community",
                freshness_score=_build_freshness_score(row.get("updated_at"), row.get("created_at")),
                last_verified=_as_iso(row.get("updated_at") or row.get("created_at")),
                average_rating=_safe_float(row.get("average_rating")),
                total_reviews=int(row.get("total_reviews") or 0),
                total_checkins=int(row.get("total_checkins") or 0),
                distance_m=_distance_m(latitude, longitude, lat, lng),
                raw_payload=row,
            )
        )
    return chargers


def _legacy_station_is_visible(row: dict[str, Any]) -> bool:
    if (row.get("verification_status") or "pending") != "verified":
        return False
    if not bool(row.get("is_private") or False):
        return True
    return bool(row.get("is_accepting_requests") or False)


async def _fetch_google_places_nearby(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    if not settings.GOOGLE_MAPS_API_KEY:
        return []

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.location,places.formattedAddress,"
            "places.evChargeOptions,places.rating,places.userRatingCount"
        ),
    }
    body = {
        "includedTypes": ["electric_vehicle_charging_station"],
        "maxResultCount": 20,
        "rankPreference": "DISTANCE",
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": latitude,
                    "longitude": longitude,
                },
                "radius": min(max(radius_km * 1000, 1000.0), 50000.0),
            }
        },
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.post(
                "https://places.googleapis.com/v1/places:searchNearby",
                headers=headers,
                json=body,
            )
            response.raise_for_status()
            track_external_api("google_places_nearby", success=True)
        except httpx.HTTPError:
            track_external_api("google_places_nearby", success=False)
            raise
        data = response.json()

    chargers: list[NormalizedCharger] = []
    for place in data.get("places", []):
        location = place.get("location") or {}
        lat = _safe_float(location.get("latitude"))
        lng = _safe_float(location.get("longitude"))
        if lat is None or lng is None:
            continue

        connectors, status, availability = _extract_google_connectors(place.get("evChargeOptions") or {})
        chargers.append(
            NormalizedCharger(
                source_name="google_places",
                source_station_id=str(place.get("id") or f"{lat}:{lng}:{place.get('displayName', {}).get('text', '')}"),
                name=place.get("displayName", {}).get("text") or "Charging Station",
                latitude=lat,
                longitude=lng,
                address=place.get("formattedAddress"),
                connector_types=connectors,
                status=status,
                availability_status=availability,
                verified_by="Google Places",
                rating=_safe_float(place.get("rating")),
                user_rating_count=int(place.get("userRatingCount") or 0),
                distance_m=_distance_m(latitude, longitude, lat, lng),
                raw_payload=place,
            )
        )
    return chargers


async def _fetch_here_ev_nearby(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    if await _has_fresh_legacy_public_coverage(
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        freshness_window=HERE_CACHE_MAX_AGE,
    ):
        logger.info(
            "Skipping live HERE lookup for %.5f,%.5f within %.1fkm because fresh legacy public coverage exists",
            latitude,
            longitude,
            radius_km,
        )
        return []

    if await _has_fresh_canonical_source_coverage(
        source_name="here_ev",
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        freshness_window=HERE_CACHE_MAX_AGE,
    ):
        logger.info(
            "Skipping live HERE lookup for %.5f,%.5f within %.1fkm because fresh canonical HERE coverage exists",
            latitude,
            longitude,
            radius_km,
        )
        return []

    cached = await _fetch_cached_source_records_nearby(
        source_name="here_ev",
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        freshness_window=HERE_CACHE_MAX_AGE,
    )
    if cached:
        logger.info(
            "Using %s cached HERE charger records for %.5f,%.5f within %.1fkm",
            len(cached),
            latitude,
            longitude,
            radius_km,
        )
        return cached

    if not settings.HERE_API_KEY:
        return []

    params = {
        "at": f"{latitude},{longitude}",
        "in": f"circle:{latitude},{longitude};r={int(min(max(radius_km * 1000, 1000.0), 50000.0))}",
        "categories": "700-7600-0322,700-7600-0323,700-7600-0324",
        "show": "ev,eMobilityServiceProviders",
        "limit": "50",
        "apiKey": settings.HERE_API_KEY,
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.get(
                "https://browse.search.hereapi.com/v1/browse",
                params=params,
            )
            response.raise_for_status()
            track_external_api("here_browse", success=True)
        except httpx.HTTPError:
            track_external_api("here_browse", success=False)
            raise
        data = response.json()

    chargers: list[NormalizedCharger] = []
    for item in data.get("items", []):
        position = item.get("position") or {}
        lat = _safe_float(position.get("lat"))
        lng = _safe_float(position.get("lng"))
        if lat is None or lng is None:
            continue

        connector_types = _extract_here_connectors(item)
        provider = _extract_here_provider(item)
        power_kw = _extract_here_power(item)
        status, availability = _extract_here_status(item)
        last_verified = _extract_here_last_verified(item)
        access_value = _extract_here_access(item)
        access_type = "Public" if access_value == "public" else "Restricted"
        is_private = access_value not in {"", "public"}

        chargers.append(
            NormalizedCharger(
                source_name="here_ev",
                source_station_id=str(item.get("id") or f"{lat}:{lng}:{item.get('title', '')}"),
                name=item.get("title") or "Charging Station",
                latitude=lat,
                longitude=lng,
                address=(item.get("address") or {}).get("label"),
                provider=provider,
                connector_types=connector_types,
                power_kw=power_kw,
                status=status,
                availability_status=availability,
                access_type=access_type,
                is_private=is_private,
                verified_by="HERE EV",
                freshness_score=_build_freshness_score(last_verified),
                last_verified=last_verified,
                distance_m=_safe_float(item.get("distance")) or _distance_m(latitude, longitude, lat, lng),
                raw_payload=item,
            )
        )
    return chargers


async def _has_fresh_canonical_source_coverage(
    source_name: str,
    latitude: float,
    longitude: float,
    radius_km: float,
    freshness_window: timedelta,
) -> bool:
    client = service_supabase or supabase
    if not client:
        return False

    lat_offset = radius_km / 111.0
    lng_offset = radius_km / max(
        1.0,
        111.0 * abs(math.cos(math.radians(latitude))),
    )
    cutoff = (datetime.now(timezone.utc) - freshness_window).isoformat()

    try:
        response = (
            client.table("canonical_chargers")
            .select("latitude,longitude,metadata,updated_at")
            .gte("updated_at", cutoff)
            .gte("latitude", latitude - lat_offset)
            .lte("latitude", latitude + lat_offset)
            .gte("longitude", longitude - lng_offset)
            .lte("longitude", longitude + lng_offset)
            .limit(HERE_CACHE_MAX_RESULTS)
            .execute()
        )
    except Exception as exc:
        logger.info("Canonical coverage lookup unavailable for %s: %s", source_name, exc)
        return False

    for row in response.data or []:
        lat = _safe_float(row.get("latitude"))
        lng = _safe_float(row.get("longitude"))
        if lat is None or lng is None:
            continue
        metadata = row.get("metadata") or {}
        data_sources = metadata.get("data_sources") if isinstance(metadata, dict) else []
        if source_name not in set(data_sources or []):
            continue
        if _distance_m(latitude, longitude, lat, lng) <= radius_km * 1000:
            return True
    return False


async def _has_fresh_legacy_public_coverage(
    latitude: float,
    longitude: float,
    radius_km: float,
    freshness_window: timedelta,
) -> bool:
    client = service_supabase or supabase
    if not client:
        return False

    lat_offset = radius_km / 111.0
    lng_offset = radius_km / max(
        1.0,
        111.0 * abs(math.cos(math.radians(latitude))),
    )
    cutoff = (datetime.now(timezone.utc) - freshness_window).isoformat()

    try:
        response = (
            client.table("charging_stations")
            .select("latitude,longitude,owner_id,is_private,updated_at")
            .eq("verification_status", "verified")
            .gte("updated_at", cutoff)
            .gte("latitude", latitude - lat_offset)
            .lte("latitude", latitude + lat_offset)
            .gte("longitude", longitude - lng_offset)
            .lte("longitude", longitude + lng_offset)
            .limit(HERE_CACHE_MAX_RESULTS)
            .execute()
        )
    except Exception as exc:
        logger.info("Legacy public coverage lookup unavailable: %s", exc)
        return False

    fresh_public_count = 0
    for row in response.data or []:
        if bool(row.get("is_private") or False):
            continue
        if row.get("owner_id") is not None:
            continue

        lat = _safe_float(row.get("latitude"))
        lng = _safe_float(row.get("longitude"))
        if lat is None or lng is None:
            continue
        if _distance_m(latitude, longitude, lat, lng) <= radius_km * 1000:
            fresh_public_count += 1

    required_count = max(3, min(8, int(radius_km * 2)))
    return fresh_public_count >= required_count


async def _fetch_cached_source_records_nearby(
    source_name: str,
    latitude: float,
    longitude: float,
    radius_km: float,
    freshness_window: timedelta,
) -> list[NormalizedCharger]:
    client = service_supabase or supabase
    if not client:
        return []

    lat_offset = radius_km / 111.0
    lng_offset = radius_km / max(
        1.0,
        111.0 * abs(math.cos(math.radians(latitude))),
    )
    cutoff = (datetime.now(timezone.utc) - freshness_window).isoformat()

    try:
        response = (
            client.table("charger_source_records")
            .select(
                "canonical_charger_id,source_name,source_station_id,name,address,"
                "latitude,longitude,provider,connector_types,power_kw,status,"
                "availability_status,amenities,access_type,access_instructions,"
                "is_private,freshness_score,last_verified_at,raw_payload,last_seen_at"
            )
            .eq("source_name", source_name)
            .gte("last_seen_at", cutoff)
            .gte("latitude", latitude - lat_offset)
            .lte("latitude", latitude + lat_offset)
            .gte("longitude", longitude - lng_offset)
            .lte("longitude", longitude + lng_offset)
            .limit(HERE_CACHE_MAX_RESULTS)
            .execute()
        )
    except Exception as exc:
        logger.info("Cached charger source lookup unavailable for %s: %s", source_name, exc)
        return []

    chargers: list[NormalizedCharger] = []
    for row in response.data or []:
        lat = _safe_float(row.get("latitude"))
        lng = _safe_float(row.get("longitude"))
        if lat is None or lng is None:
            continue

        distance_m = _distance_m(latitude, longitude, lat, lng)
        if distance_m > radius_km * 1000:
            continue

        chargers.append(
            NormalizedCharger(
                source_name=str(row.get("source_name") or source_name),
                source_station_id=str(row.get("source_station_id") or f"{lat}:{lng}:{row.get('name', '')}"),
                canonical_id=str(row.get("canonical_charger_id")) if row.get("canonical_charger_id") else None,
                name=row.get("name") or "Charging Station",
                latitude=lat,
                longitude=lng,
                address=row.get("address"),
                provider=row.get("provider"),
                connector_types=list(row.get("connector_types") or []),
                power_kw=_safe_float(row.get("power_kw")),
                status=row.get("status") or "Operational",
                availability_status=row.get("availability_status") or "Unknown",
                amenities=list(row.get("amenities") or []),
                access_type=row.get("access_type") or "Public",
                access_instructions=row.get("access_instructions"),
                is_private=bool(row.get("is_private") or False),
                verified_by="HERE EV (cached)" if source_name == "here_ev" else str(row.get("source_name") or source_name),
                freshness_score=row.get("freshness_score"),
                last_verified=_as_iso(row.get("last_verified_at") or row.get("last_seen_at")),
                distance_m=distance_m,
                raw_payload=row.get("raw_payload") if isinstance(row.get("raw_payload"), dict) else row,
            )
        )

    chargers.sort(key=lambda charger: charger.distance_m or math.inf)
    return chargers


async def _fetch_open_charge_map_nearby(
    latitude: float,
    longitude: float,
    radius_km: float,
) -> list[NormalizedCharger]:
    api_key = _clean_optional_env(getattr(settings, "OPENCHARGEMAP_API_KEY", ""))
    if not api_key:
        return []

    params = {
        "output": "json",
        "compact": "true",
        "verbose": "false",
        "latitude": str(latitude),
        "longitude": str(longitude),
        "distance": str(radius_km),
        "distanceunit": "KM",
        "maxresults": "50",
    }
    headers = {"X-API-Key": api_key}

    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.get(
                "https://api.openchargemap.io/v3/poi/",
                params=params,
                headers=headers,
            )
            response.raise_for_status()
            track_external_api("openchargemap", success=True)
        except httpx.HTTPError:
            track_external_api("openchargemap", success=False)
            raise
        rows = response.json()

    chargers: list[NormalizedCharger] = []
    for row in rows:
        address_info = row.get("AddressInfo") or {}
        lat = _safe_float(address_info.get("Latitude"))
        lng = _safe_float(address_info.get("Longitude"))
        if lat is None or lng is None:
            continue

        chargers.append(
            NormalizedCharger(
                source_name="open_charge_map",
                source_station_id=str(row.get("ID") or f"{lat}:{lng}:{address_info.get('Title', '')}"),
                name=address_info.get("Title") or "Charging Station",
                latitude=lat,
                longitude=lng,
                address=_join_address_parts(
                    [
                        address_info.get("AddressLine1"),
                        address_info.get("Town"),
                        address_info.get("StateOrProvince"),
                        address_info.get("Postcode"),
                    ]
                ),
                provider=(row.get("OperatorInfo") or {}).get("Title"),
                connector_types=_extract_ocm_connectors(row.get("Connections") or []),
                power_kw=_extract_ocm_power(row.get("Connections") or []),
                status=_map_ocm_status(row.get("StatusType")),
                availability_status=_map_ocm_availability(row.get("StatusType")),
                verified_by="Open Charge Map",
                distance_m=_distance_m(latitude, longitude, lat, lng),
                raw_payload=row,
            )
        )
    return chargers


def _merge_deduped_chargers(chargers: list[NormalizedCharger]) -> list[NormalizedCharger]:
    merged: list[NormalizedCharger] = []
    for charger in sorted(chargers, key=lambda item: (-item.source_priority, item.distance_m or math.inf)):
        match = next((existing for existing in merged if _same_station(existing, charger)), None)
        if match is None:
            merged.append(charger)
            continue
        _merge_into(match, charger)
    return merged


def _same_station(left: NormalizedCharger, right: NormalizedCharger) -> bool:
    if left.canonical_id and right.canonical_id and left.canonical_id == right.canonical_id:
        return True
    if left.source_name == right.source_name and left.source_station_id == right.source_station_id:
        return True

    distance_m = _distance_m(left.latitude, left.longitude, right.latitude, right.longitude)
    if distance_m > 60:
        return False

    if left.normalized_name and right.normalized_name:
        if left.normalized_name == right.normalized_name:
            return True
        if distance_m <= 35 and _token_overlap(left.normalized_name, right.normalized_name) >= 0.65:
            return True

    if left.normalized_address and right.normalized_address:
        if left.normalized_address == right.normalized_address:
            return True
        if distance_m <= 35 and _token_overlap(left.normalized_address, right.normalized_address) >= 0.7:
            return True

    return distance_m <= 25


def _merge_into(target: NormalizedCharger, incoming: NormalizedCharger) -> None:
    if incoming.source_priority > target.source_priority:
        preserved_sources = sorted(set(target.data_sources + incoming.data_sources))
        canonical_id = target.canonical_id or incoming.canonical_id
        target_fields = incoming.__dict__.copy()
        target_fields["canonical_id"] = canonical_id
        target_fields["data_sources"] = preserved_sources
        target.__dict__.update(target_fields)
    else:
        target.canonical_id = target.canonical_id or incoming.canonical_id
        target.data_sources = sorted(set(target.data_sources + incoming.data_sources))

    target.connector_types = _unique_strings(target.connector_types + incoming.connector_types)
    target.amenities = _unique_strings(target.amenities + incoming.amenities)
    target.provider = _pick_preferred_text(target.provider, incoming.provider, target.source_priority, incoming.source_priority)
    target.address = _pick_preferred_text(target.address, incoming.address, target.source_priority, incoming.source_priority)
    target.station_record_id = target.station_record_id or incoming.station_record_id
    target.host_name = _pick_preferred_text(target.host_name, incoming.host_name, target.source_priority, incoming.source_priority)
    target.host_phone = _pick_preferred_text(target.host_phone, incoming.host_phone, target.source_priority, incoming.source_priority)
    target.host_upi_id = _pick_preferred_text(target.host_upi_id, incoming.host_upi_id, target.source_priority, incoming.source_priority)
    target.power_kw = _pick_preferred_number(target.power_kw, incoming.power_kw)
    target.price_per_kwh = _pick_preferred_number(target.price_per_kwh, incoming.price_per_kwh)
    target.price_per_session = _pick_preferred_number(target.price_per_session, incoming.price_per_session)
    target.available_from = _pick_preferred_text(target.available_from, incoming.available_from, target.source_priority, incoming.source_priority)
    target.available_to = _pick_preferred_text(target.available_to, incoming.available_to, target.source_priority, incoming.source_priority)
    target.available_days = _unique_strings(target.available_days + incoming.available_days)
    target.is_accepting_requests = target.is_accepting_requests or incoming.is_accepting_requests
    target.parking_notes = _pick_preferred_text(target.parking_notes, incoming.parking_notes, target.source_priority, incoming.source_priority)
    target.house_rules = _pick_preferred_text(target.house_rules, incoming.house_rules, target.source_priority, incoming.source_priority)
    target.freshness_score = _pick_preferred_int(target.freshness_score, incoming.freshness_score)
    target.last_verified = _pick_latest_iso(target.last_verified, incoming.last_verified)
    target.rating = _pick_preferred_number(target.rating, incoming.rating)
    target.average_rating = _pick_preferred_number(target.average_rating, incoming.average_rating)
    target.user_rating_count = max(target.user_rating_count or 0, incoming.user_rating_count or 0) or None
    target.total_reviews = max(target.total_reviews, incoming.total_reviews)
    target.total_checkins = max(target.total_checkins, incoming.total_checkins)
    target.distance_m = min(
        value for value in [target.distance_m, incoming.distance_m] if value is not None
    ) if any(value is not None for value in [target.distance_m, incoming.distance_m]) else None
    if target.availability_status == "Unknown" and incoming.availability_status != "Unknown":
        target.availability_status = incoming.availability_status
    if target.status in {"Unknown", "Operational"} and incoming.status not in {"Unknown", "Operational"}:
        target.status = incoming.status


async def _persist_canonical_results(chargers: list[NormalizedCharger]) -> None:
    client = service_supabase
    if not client or not chargers:
        return

    if not _canonical_tables_available(client):
        _persist_legacy_results(chargers, client)
        return

    for charger in chargers:
        try:
            if not charger.canonical_id:
                insert_payload = charger.to_canonical_upsert()
                insert_payload.pop("id", None)
                insert_result = client.table("canonical_chargers").insert(insert_payload).execute()
                if insert_result.data:
                    charger.canonical_id = str(insert_result.data[0]["id"])
            else:
                update_payload = charger.to_canonical_upsert()
                update_payload.pop("id", None)
                client.table("canonical_chargers").update(update_payload).eq(
                    "id",
                    charger.canonical_id,
                ).execute()

            if not charger.canonical_id:
                continue

            client.table("charger_source_records").upsert(
                {
                    "canonical_charger_id": charger.canonical_id,
                    "source_name": charger.source_name,
                    "source_station_id": charger.source_station_id,
                    "name": charger.name,
                    "normalized_name": charger.normalized_name,
                    "address": charger.address,
                    "latitude": charger.latitude,
                    "longitude": charger.longitude,
                    "provider": charger.provider,
                    "connector_types": charger.connector_types,
                    "power_kw": charger.power_kw,
                    "status": charger.status,
                    "availability_status": charger.availability_status,
                    "amenities": charger.amenities,
                    "access_type": charger.access_type,
                    "access_instructions": charger.access_instructions,
                    "is_private": charger.is_private,
                    "freshness_score": charger.freshness_score,
                    "last_verified_at": charger.last_verified,
                    "raw_payload": charger.raw_payload,
                    "distance_m": charger.distance_m,
                    "confidence_score": round(charger.source_priority / 100.0, 2),
                    "last_seen_at": datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="source_name,source_station_id",
            ).execute()
        except Exception as exc:
            logger.info("Skipping canonical charger writeback for %s: %s", charger.name, exc)


def _canonical_tables_available(client: Any) -> bool:
    try:
        client.table("canonical_chargers").select("id").limit(1).execute()
        client.table("charger_source_records").select("id").limit(1).execute()
        return True
    except Exception as exc:
        logger.info("Canonical charger tables unavailable, using legacy fallback: %s", exc)
        return False


def _persist_legacy_results(chargers: list[NormalizedCharger], client: Any) -> None:
    for charger in chargers:
        if charger.is_private:
            continue
        try:
            existing_row = _find_matching_legacy_station(client, charger)
            payload = _build_legacy_station_payload(charger)
            if existing_row is None:
                client.table("charging_stations").insert(payload).execute()
            else:
                client.table("charging_stations").update(payload).eq(
                    "id",
                    existing_row["id"],
                ).execute()
        except Exception as exc:
            logger.info("Skipping legacy charger writeback for %s: %s", charger.name, exc)


def _find_matching_legacy_station(
    client: Any,
    charger: NormalizedCharger,
) -> Optional[dict[str, Any]]:
    radius_km = 0.12
    lat_offset = radius_km / 111.0
    lng_offset = radius_km / max(
        1.0,
        111.0 * abs(math.cos(math.radians(charger.latitude))),
    )
    response = (
        client.table("charging_stations")
        .select("*")
        .eq("verification_status", "verified")
        .gte("latitude", charger.latitude - lat_offset)
        .lte("latitude", charger.latitude + lat_offset)
        .gte("longitude", charger.longitude - lng_offset)
        .lte("longitude", charger.longitude + lng_offset)
        .limit(25)
        .execute()
    )

    for row in response.data or []:
        if bool(row.get("is_private") or False):
            continue
        if row.get("owner_id"):
            continue
        normalized = _legacy_row_to_normalized_charger(row, charger.latitude, charger.longitude)
        if normalized and _same_station(normalized, charger):
            return row
    return None


def _build_legacy_station_payload(charger: NormalizedCharger) -> dict[str, Any]:
    return {
        "name": charger.name,
        "address": charger.address,
        "latitude": charger.latitude,
        "longitude": charger.longitude,
        "provider": charger.provider,
        "connector_types": charger.connector_types,
        "power_kw": charger.power_kw,
        "status": charger.status,
        "availability_status": charger.availability_status,
        "amenities": charger.amenities,
        "is_24_7": charger.access_type.lower() == "public",
        "image_urls": [],
        "is_private": False,
        "owner_id": None,
        "access_type": charger.access_type,
        "access_instructions": charger.access_instructions,
        "submitted_by": None,
        "verification_status": "verified",
        "average_rating": charger.average_rating if charger.average_rating is not None else charger.rating,
        "total_reviews": charger.total_reviews or charger.user_rating_count or 0,
        "total_checkins": charger.total_checkins,
        "host_name": None,
        "host_phone": None,
        "host_upi_id": None,
        "price_per_kwh": charger.price_per_kwh,
        "price_per_session": charger.price_per_session,
        "available_from": charger.available_from,
        "available_to": charger.available_to,
        "available_days": charger.available_days,
        "is_accepting_requests": False,
        "parking_notes": charger.parking_notes,
        "house_rules": charger.house_rules,
        "charger_photos": [],
    }


def _legacy_row_to_normalized_charger(
    row: dict[str, Any],
    request_latitude: float,
    request_longitude: float,
) -> Optional[NormalizedCharger]:
    lat = _safe_float(row.get("latitude"))
    lng = _safe_float(row.get("longitude"))
    if lat is None or lng is None:
        return None

    return NormalizedCharger(
        source_name="evraahein_db",
        source_station_id=str(row.get("id") or f"{lat}:{lng}:{row.get('name', '')}"),
        name=row.get("name") or "Charging Station",
        latitude=lat,
        longitude=lng,
        address=row.get("address"),
        provider=row.get("provider"),
        connector_types=list(row.get("connector_types") or row.get("connectors") or []),
        power_kw=_safe_float(row.get("power_kw")),
        status=_map_legacy_status(row.get("status")),
        availability_status=row.get("availability_status") or "Unknown",
        amenities=list(row.get("amenities") or []),
        access_type=row.get("access_type") or "Public",
        access_instructions=row.get("access_instructions"),
        is_private=bool(row.get("is_private") or False),
        station_record_id=str(row.get("id")) if row.get("id") is not None else None,
        host_name=row.get("host_name"),
        host_phone=row.get("host_phone"),
        host_upi_id=row.get("host_upi_id"),
        price_per_kwh=_safe_float(row.get("price_per_kwh")),
        price_per_session=_safe_float(row.get("price_per_session")),
        available_from=str(row.get("available_from")) if row.get("available_from") else None,
        available_to=str(row.get("available_to")) if row.get("available_to") else None,
        available_days=list(row.get("available_days") or []),
        is_accepting_requests=bool(row.get("is_accepting_requests") or False),
        parking_notes=row.get("parking_notes"),
        house_rules=row.get("house_rules"),
        verified_by="EVraahein Community",
        freshness_score=_build_freshness_score(row.get("updated_at"), row.get("created_at")),
        last_verified=_as_iso(row.get("updated_at") or row.get("created_at")),
        average_rating=_safe_float(row.get("average_rating")),
        total_reviews=int(row.get("total_reviews") or 0),
        total_checkins=int(row.get("total_checkins") or 0),
        distance_m=_distance_m(request_latitude, request_longitude, lat, lng),
        raw_payload=row,
    )


def _extract_google_connectors(ev_options: dict[str, Any]) -> tuple[list[str], str, str]:
    connectors: list[str] = []
    status = "Operational"
    availability = "Unknown"
    for item in ev_options.get("connectorAggregation") or []:
        raw_type = item.get("type")
        if raw_type:
            connectors.append(_format_connector(raw_type))
        raw_availability = item.get("availability")
        if raw_availability == "AVAILABLE":
            availability = "Available"
            status = "Operational"
        elif raw_availability == "OCCUPIED" and availability == "Unknown":
            availability = "Busy"
            status = "Busy"
        elif raw_availability == "OUT_OF_SERVICE" and availability == "Unknown":
            availability = "Out of service"
            status = "Broken"
    return _unique_strings(connectors), status, availability


def _extract_here_connectors(item: dict[str, Any]) -> list[str]:
    connectors: list[str] = []
    for connector in (((item.get("extended") or {}).get("evStation") or {}).get("connectors") or []):
        connector_type = ((connector.get("connectorType") or {}).get("name") or "").strip()
        if connector_type:
            connectors.append(_format_connector(connector_type))
    return _unique_strings(connectors)


def _extract_here_provider(item: dict[str, Any]) -> Optional[str]:
    connectors = (((item.get("extended") or {}).get("evStation") or {}).get("connectors") or [])
    for connector in connectors:
        supplier_name = str(connector.get("supplierName") or "").strip()
        if supplier_name:
            return supplier_name

    service_providers = (((item.get("extended") or {}).get("eMobilityServiceProviders") or {}).get("providers") or [])
    for provider in service_providers:
        name = str(provider.get("name") or "").strip()
        if name:
            return name

    return None


def _extract_here_power(item: dict[str, Any]) -> Optional[float]:
    powers = [
        _safe_float(connector.get("maxPowerLevel"))
        for connector in (((item.get("extended") or {}).get("evStation") or {}).get("connectors") or [])
        if _safe_float(connector.get("maxPowerLevel")) is not None
    ]
    return max(powers) if powers else None


def _extract_here_status(item: dict[str, Any]) -> tuple[str, str]:
    states: list[str] = []
    for station in (((item.get("extended") or {}).get("evAvailability") or {}).get("stations") or []):
        for evse in station.get("evses") or []:
            state = str(evse.get("state") or "").strip()
            if state:
                states.append(state.upper().replace("-", "_").replace(" ", "_"))

    if not states:
        return "Operational", "Unknown"

    if any(state in {"AVAILABLE", "FREE"} for state in states):
        return "Operational", "Available"
    if any(state in {"OCCUPIED", "CHARGING", "IN_USE", "BUSY"} for state in states):
        return "Busy", "Busy"
    if any(state in {"OUT_OF_SERVICE", "FAULTED", "UNAVAILABLE", "INOPERATIVE"} for state in states):
        return "Broken", "Out of service"
    return "Operational", "Unknown"


def _extract_here_last_verified(item: dict[str, Any]) -> Optional[str]:
    timestamps: list[str] = []
    connectors = (((item.get("extended") or {}).get("evStation") or {}).get("connectors") or [])
    for connector in connectors:
        charging_point = connector.get("chargingPoint") or {}
        timestamp = charging_point.get("lastUpdateTimestamp")
        if timestamp:
            timestamps.append(str(timestamp))

    for station in (((item.get("extended") or {}).get("evAvailability") or {}).get("stations") or []):
        for evse in station.get("evses") or []:
            timestamp = evse.get("last_updated")
            if timestamp:
                timestamps.append(str(timestamp))

    latest: Optional[str] = None
    for timestamp in timestamps:
        latest = _pick_latest_iso(latest, timestamp)
    return latest


def _extract_here_access(item: dict[str, Any]) -> str:
    access = str((((item.get("extended") or {}).get("evStation") or {}).get("access") or "")).strip().lower()
    if access:
        return access
    return "public"


def _extract_ocm_connectors(connections: list[dict[str, Any]]) -> list[str]:
    connectors: list[str] = []
    for connection in connections:
        title = ((connection.get("ConnectionType") or {}).get("Title") or "").strip()
        if title:
            connectors.append(_format_connector(title))
    return _unique_strings(connectors)


def _extract_ocm_power(connections: list[dict[str, Any]]) -> Optional[float]:
    powers = [
        _safe_float(connection.get("PowerKW"))
        for connection in connections
        if _safe_float(connection.get("PowerKW")) is not None
    ]
    return max(powers) if powers else None


def _map_legacy_status(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in {"working", "operational", "available"}:
        return "Operational"
    if normalized in {"busy", "occupied"}:
        return "Busy"
    if normalized in {"broken", "out_of_service", "out of service"}:
        return "Broken"
    return "Operational"


def _map_ocm_status(status_type: Any) -> str:
    title = ((status_type or {}).get("Title") or "").strip().lower()
    if "not operational" in title or "planned" in title:
        return "Broken"
    if "operational" in title:
        return "Operational"
    return "Operational"


def _map_ocm_availability(status_type: Any) -> str:
    title = ((status_type or {}).get("Title") or "").strip().lower()
    if "not operational" in title or "planned" in title:
        return "Out of service"
    if "operational" in title:
        return "Available"
    return "Unknown"


def _build_freshness_score(*values: Any) -> Optional[int]:
    timestamps = [_parse_datetime(value) for value in values if value]
    timestamps = [value for value in timestamps if value is not None]
    if not timestamps:
        return None
    age_days = max((datetime.now(timezone.utc) - max(timestamps)).days, 0)
    return max(0, 100 - age_days * 2)


def _format_connector(raw: str) -> str:
    formatted = (
        raw.replace("EV_CONNECTOR_TYPE_", "")
        .replace("EV_CONNECTOR_", "")
        .replace("_", " ")
        .strip()
    )
    type_map = {
        "CCS COMBO 1": "CCS1",
        "CCS COMBO 2": "CCS2",
        "CHADEMO": "CHAdeMO",
        "IEC 62196-2 TYPE 1 (SAE J1772)": "Type 1 (J1772)",
        "IEC 62196-2 TYPE 2 (MENNEKES)": "Type 2",
        "IEC 62196-3 COMBO 1": "CCS1",
        "IEC 62196-3 COMBO 1 (SAE J1772)": "CCS1",
        "IEC 62196-3 COMBO 2": "CCS2",
        "IEC 62196-3 COMBO 2 (CCS2)": "CCS2",
        "J1772": "Type 1 (J1772)",
        "TYPE 2": "Type 2",
        "TYPE 1": "Type 1",
        "TESLA": "Tesla",
        "GB/T (CHINESE) AC CONNECTOR": "GB/T AC",
        "GB/T (CHINESE) DC CONNECTOR": "GB/T DC",
        "GB T": "GB/T",
        "GBT": "GB/T",
        "UNSPECIFIED": "Standard",
        "OTHER": "Other",
    }
    return type_map.get(formatted.upper(), formatted.title() or "Unknown")


def _normalize_station_name(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", " ", value.lower())
    tokens = [
        token
        for token in normalized.split()
        if token not in {"ev", "charging", "charger", "station", "fast", "dc", "ac"}
    ]
    return " ".join(tokens)


def _normalize_address(value: Optional[str]) -> str:
    if not value:
        return ""
    normalized = re.sub(r"[^a-z0-9]+", " ", value.lower())
    return " ".join(normalized.split())


def _token_overlap(left: str, right: str) -> float:
    left_tokens = set(left.split())
    right_tokens = set(right.split())
    if not left_tokens or not right_tokens:
        return 0.0
    return len(left_tokens & right_tokens) / max(len(left_tokens), len(right_tokens))


def _distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    lat1_r, lng1_r, lat2_r, lng2_r = map(math.radians, [lat1, lng1, lat2, lng2])
    dlat = lat2_r - lat1_r
    dlng = lng2_r - lng1_r
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_r) * math.cos(lat2_r) * math.sin(dlng / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    return 6371000 * c


def _unique_strings(values: Iterable[Any]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for value in values:
        text = str(value).strip()
        if not text:
            continue
        lowered = text.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        unique.append(text)
    return unique


def _pick_preferred_text(
    current: Optional[str],
    incoming: Optional[str],
    current_priority: int,
    incoming_priority: int,
) -> Optional[str]:
    if not incoming:
        return current
    if not current or incoming_priority >= current_priority:
        return incoming
    return current


def _pick_preferred_number(current: Optional[float], incoming: Optional[float]) -> Optional[float]:
    return incoming if incoming is not None else current


def _pick_preferred_int(current: Optional[int], incoming: Optional[int]) -> Optional[int]:
    return incoming if incoming is not None else current


def _pick_latest_iso(current: Optional[str], incoming: Optional[str]) -> Optional[str]:
    current_dt = _parse_datetime(current)
    incoming_dt = _parse_datetime(incoming)
    if incoming_dt and (not current_dt or incoming_dt > current_dt):
        return incoming
    return current


def _parse_datetime(value: Any) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def _as_iso(value: Any) -> Optional[str]:
    parsed = _parse_datetime(value)
    return parsed.isoformat() if parsed else None


def _safe_float(value: Any) -> Optional[float]:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _join_address_parts(parts: list[Optional[str]]) -> Optional[str]:
    filtered = [part.strip() for part in parts if part and part.strip()]
    return ", ".join(filtered) if filtered else None


def _clean_optional_env(value: str) -> str:
    return value.strip().strip('"').strip("'")
