import logging
from math import cos, radians
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from datetime import datetime
from supabase_client import supabase, service_supabase
import uuid
from auth_utils import ensure_same_user, get_authenticated_user, require_auth
from utils.charger_aggregation import aggregate_chargers_nearby

router = APIRouter()
logger = logging.getLogger(__name__)

PLATFORM_FEE_PERCENT = 5.0   # 5% of energy cost
PLATFORM_FEE_MINIMUM_INR = 2.0  # floor so micro-sessions aren't free for the platform
HOST_DECLARATION_VERSION = "private_charger_hosting_v1"

LOCATION_ACCESS_CHECK_KEYS = [
    "accessible_without_gated_approval",
    "parking_available_for_visiting_evs",
    "above_ground_and_well_ventilated",
    "reachable_by_standard_ev_cars",
    "cable_does_not_block_public_roads",
    "safe_access_after_sunset",
]

SAFETY_CHECK_KEYS = [
    "properly_earthed",
    "mcb_or_rccb_installed",
    "no_loose_extension_wiring",
    "protected_from_rain_or_water",
    "fire_extinguisher_available",
]

HOST_DECLARATION_KEYS = [
    "complies_with_local_rules_and_safe_for_temporary_access",
    "host_responsible_for_safety_access_and_electrical_compliance",
    "platform_only_facilitates_discovery_and_coordination",
]


def _normalize_checkbox_object(
    value: Optional[Dict[str, Any]],
    keys: List[str],
) -> Dict[str, bool]:
    source = value or {}
    return {key: bool(source.get(key)) for key in keys}


def _normalize_badges(value: Optional[Dict[str, Any]]) -> Dict[str, bool]:
    source = value or {}
    return {
        "phone_verified": bool(source.get("phone_verified")),
        "charger_photo_uploaded": bool(source.get("charger_photo_uploaded")),
        "parking_photo_uploaded": bool(source.get("parking_photo_uploaded")),
        "responsive_host": bool(source.get("responsive_host")),
        "repeat_host": bool(source.get("repeat_host")),
    }


def _normalize_text_list(value: Any) -> List[str]:
    return [str(item).strip() for item in list(value or []) if str(item).strip()]

# --- Models ---
class ChargingStation(BaseModel):
    id: Optional[str] = None
    name: str
    address: Optional[str]
    latitude: float
    longitude: float
    provider: Optional[str]
    connector_types: List[str] = []
    power_kw: Optional[float]
    status: str = "Operational"
    availability_status: str = "Unknown"
    amenities: List[str] = []
    is_24_7: bool = False
    image_urls: List[str] = []
    
    # Private / Crowdsourced
    is_private: bool = False
    owner_id: Optional[str] = None
    access_type: str = "Public"
    access_instructions: Optional[str] = None
    submitted_by: Optional[str] = None
    verification_status: str = "pending"
    host_name: Optional[str] = None
    host_phone: Optional[str] = None
    host_upi_id: Optional[str] = None
    price_per_kwh: Optional[float] = None
    price_per_session: Optional[float] = None
    available_from: Optional[str] = None
    available_to: Optional[str] = None
    available_days: List[str] = []
    is_accepting_requests: bool = False
    parking_notes: Optional[str] = None
    house_rules: Optional[str] = None
    charger_photos: List[str] = []
    parking_photos: List[str] = []
    property_type: Optional[str] = None
    visitor_access_type: Optional[str] = None
    available_hours: Optional[str] = None
    vehicle_size_support: List[str] = []
    location_access_checks: Dict[str, bool] = {}
    safety_checks: Dict[str, bool] = {}
    host_declarations: Dict[str, bool] = {}
    declaration_version: Optional[str] = None
    declarations_completed_at: Optional[datetime] = None
    moderation_flags: List[str] = []
    verification_badges: Dict[str, bool] = {}
    
    # Aggregates
    average_rating: float = 0.0
    total_reviews: int = 0
    total_checkins: int = 0

class ChargingSession(BaseModel):
    id: Optional[str] = None
    user_id: str
    station_id: Optional[str]
    start_time: datetime
    end_time: Optional[datetime]
    kwh_added: Optional[float]
    cost: Optional[float]

class CreateStationRequest(BaseModel):
    name: str
    latitude: float
    longitude: float
    provider: Optional[str] = "Unknown"
    is_private: bool = False
    owner_id: str # User ID submitting
    access_instructions: Optional[str] = None


class HostChargerRequest(BaseModel):
    station_id: Optional[str] = None
    owner_id: str
    name: str
    latitude: float
    longitude: float
    address: Optional[str] = None
    provider: Optional[str] = "Community Host"
    connector_types: List[str] = []
    power_kw: Optional[float] = None
    # Pricing — two paths:
    #   1. Structured: electricity_cost_per_kwh + host_margin_per_kwh → price_per_kwh computed
    #   2. Direct:     price_per_kwh set explicitly (backwards-compatible)
    electricity_cost_per_kwh: Optional[float] = None
    host_margin_per_kwh: Optional[float] = None
    price_per_kwh: Optional[float] = None
    price_per_session: Optional[float] = None
    host_name: str
    host_phone: str
    host_upi_id: Optional[str] = None
    access_instructions: Optional[str] = None
    available_from: Optional[str] = None
    available_to: Optional[str] = None
    available_days: List[str] = []
    parking_notes: Optional[str] = None
    house_rules: Optional[str] = None
    is_accepting_requests: bool = True
    amenities: List[str] = []
    charger_photos: List[str] = []
    parking_photos: List[str] = []
    property_type: Optional[str] = None
    visitor_access_type: Optional[str] = None
    available_hours: Optional[str] = None
    vehicle_size_support: List[str] = []
    location_access_checks: Dict[str, bool] = {}
    safety_checks: Dict[str, bool] = {}
    host_declarations: Dict[str, bool] = {}
    declaration_version: Optional[str] = HOST_DECLARATION_VERSION


class CreateChargerRequest(BaseModel):
    station_id: str
    requester_user_id: str
    requester_name: Optional[str] = None
    requester_phone: str
    vehicle_name: Optional[str] = None
    current_soc: Optional[int] = None
    message: Optional[str] = None
    requested_start_at: datetime
    requested_end_at: Optional[datetime] = None


class ChargerRequestDecisionRequest(BaseModel):
    host_user_id: str
    status: str
    host_response: Optional[str] = None


class ChargerRequestCompleteRequest(BaseModel):
    host_user_id: str


class ChargerRequestSettleRequest(BaseModel):
    host_user_id: str
    kwh_delivered: float  # actual kWh measured by host

class CreateSessionRequest(BaseModel):
    user_id: str
    station_id: Optional[str]
    start_time: datetime
    kwh_added: float
    cost: float

class CheckIn(BaseModel):
    id: Optional[str] = None
    user_id: str
    station_id: Optional[str]
    status: str # "Working", "Busy", "Broken"
    rating: Optional[int]
    comment: Optional[str]
    image_url: Optional[str]
    upvotes: int = 0
    downvotes: int = 0
    user_name: Optional[str] = None  # Will be anonymized when returned
    created_at: datetime = datetime.now()

class CreateCheckInRequest(BaseModel):
    user_id: str
    station_id: Optional[str]
    status: str
    rating: Optional[int]
    comment: Optional[str]
    image_url: Optional[str]
    # New charging detail fields
    battery_start_percent: Optional[int] = None
    battery_end_percent: Optional[int] = None
    time_taken_minutes: Optional[int] = None
    cost_paid: Optional[float] = None
    charging_slip_url: Optional[str] = None
    points_earned: Optional[int] = 10  # Default to 10 for backward compatibility
    user_name: Optional[str] = None  # User's name for display (will be anonymized)
    # Electric Talks insights - trip context fields
    weather: Optional[str] = None  # Hot, Rainy, Cold, Normal
    trip_type: Optional[str] = None  # Highway, City, Mixed
    passenger_count: Optional[int] = None  # 1-5+
    drive_mode: Optional[str] = None  # Eco, Normal, Sport

class VoteRequest(BaseModel):
    user_id: str
    checkin_id: str
    vote_type: str  # "upvote" or "downvote"


class AggregatedChargerLocation(BaseModel):
    lat: float
    lng: float


class AggregatedChargingStation(BaseModel):
    id: str
    name: str
    location: AggregatedChargerLocation
    provider: Optional[str] = None
    status: str = "Operational"
    last_verified: Optional[str] = None
    verified_by: str = "EVraahein"
    connectors: List[str] = []
    amenities: List[str] = []
    freshness_score: Optional[int] = None
    issue_type: Optional[str] = None
    rating: Optional[float] = None
    user_rating_count: Optional[int] = None
    address: Optional[str] = None
    cost: Optional[str] = None
    is_private: bool = False
    access_type: str = "Public"
    availability_status: Optional[str] = None
    data_sources: List[str] = []
    distance_m: Optional[float] = None
    source_count: int = 1
    station_record_id: Optional[str] = None
    host_name: Optional[str] = None
    host_phone: Optional[str] = None
    host_upi_id: Optional[str] = None
    price_per_kwh: Optional[float] = None
    price_per_session: Optional[float] = None
    available_from: Optional[str] = None
    available_to: Optional[str] = None
    available_days: List[str] = []
    is_accepting_requests: bool = False
    parking_notes: Optional[str] = None
    house_rules: Optional[str] = None
    charger_photos: List[str] = []
    parking_photos: List[str] = []
    property_type: Optional[str] = None
    visitor_access_type: Optional[str] = None
    available_hours: Optional[str] = None
    vehicle_size_support: List[str] = []
    location_access_checks: Dict[str, bool] = {}
    safety_checks: Dict[str, bool] = {}
    host_declarations: Dict[str, bool] = {}
    declaration_version: Optional[str] = None
    declarations_completed_at: Optional[str] = None
    moderation_flags: List[str] = []
    verification_badges: Dict[str, bool] = {}


def _station_is_publicly_visible(row: Dict[str, Any]) -> bool:
    if (row.get("verification_status") or "pending") != "verified":
        return False
    if not bool(row.get("is_private") or False):
        return True
    return bool(row.get("is_accepting_requests") or False)


def _normalize_station_row(row: Dict[str, Any]) -> Dict[str, Any]:
    normalized = dict(row)
    normalized["available_days"] = list(normalized.get("available_days") or [])
    normalized["charger_photos"] = list(normalized.get("charger_photos") or [])
    normalized["parking_photos"] = list(normalized.get("parking_photos") or [])
    normalized["connector_types"] = list(normalized.get("connector_types") or [])
    normalized["amenities"] = list(normalized.get("amenities") or [])
    normalized["vehicle_size_support"] = list(normalized.get("vehicle_size_support") or [])
    normalized["moderation_flags"] = list(normalized.get("moderation_flags") or [])
    normalized["location_access_checks"] = _normalize_checkbox_object(
        normalized.get("location_access_checks"),
        LOCATION_ACCESS_CHECK_KEYS,
    )
    normalized["safety_checks"] = _normalize_checkbox_object(
        normalized.get("safety_checks"),
        SAFETY_CHECK_KEYS,
    )
    normalized["host_declarations"] = _normalize_checkbox_object(
        normalized.get("host_declarations"),
        HOST_DECLARATION_KEYS,
    )
    normalized["verification_badges"] = _normalize_badges(
        normalized.get("verification_badges"),
    )
    if normalized.get("available_from") is not None:
        normalized["available_from"] = str(normalized["available_from"])
    if normalized.get("available_to") is not None:
        normalized["available_to"] = str(normalized["available_to"])
    if normalized.get("declarations_completed_at") is not None:
        normalized["declarations_completed_at"] = str(
            normalized["declarations_completed_at"]
        )
    return normalized


def _load_host_profile_flags(user_id: str) -> Dict[str, bool]:
    try:
        response = (
            supabase.table("profiles")
            .select("preferences")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        prefs = (response.data or {}).get("preferences") or {}
        return {
            "phone_verified": bool(prefs.get("is_phone_verified")),
        }
    except Exception as exc:
        logger.info("Could not load host profile flags for %s: %s", user_id, exc)
        return {"phone_verified": False}


def _build_host_verification_badges(
    *,
    owner_id: str,
    charger_photos: List[str],
    parking_photos: List[str],
) -> Dict[str, bool]:
    profile_flags = _load_host_profile_flags(owner_id)

    repeat_host = False
    responsive_host = False
    try:
        hosted = (
            supabase.table("charging_stations")
            .select("id", count="exact")
            .eq("owner_id", owner_id)
            .eq("is_private", True)
            .execute()
        )
        repeat_host = (hosted.count or 0) >= 2
    except Exception as exc:
        logger.info("Could not compute repeat_host for %s: %s", owner_id, exc)

    try:
        handled = (
            supabase.table("charger_requests")
            .select("id", count="exact")
            .eq("host_user_id", owner_id)
            .in_("status", ["accepted", "completed", "rejected"])
            .execute()
        )
        responsive_host = (handled.count or 0) >= 3
    except Exception as exc:
        logger.info("Could not compute responsive_host for %s: %s", owner_id, exc)

    return {
        "phone_verified": bool(profile_flags.get("phone_verified")),
        "charger_photo_uploaded": bool(charger_photos),
        "parking_photo_uploaded": bool(parking_photos),
        "responsive_host": responsive_host,
        "repeat_host": repeat_host,
    }


def _hydrate_request_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not rows:
        return []

    station_ids = list(
        {
            row.get("station_id")
            for row in rows
            if row.get("station_id") is not None
        }
    )
    station_map: Dict[str, Dict[str, Any]] = {}
    if station_ids:
        stations_result = (
            supabase.table("charging_stations")
            .select(
                "id, name, address, latitude, longitude, owner_id, host_name, "
                "host_phone, host_upi_id, price_per_kwh, price_per_session, "
                "electricity_cost_per_kwh, host_margin_per_kwh, "
                "available_from, available_to, available_days, "
                "available_hours, access_instructions, parking_notes, house_rules, "
                "property_type, visitor_access_type, vehicle_size_support, "
                "charger_photos, parking_photos, location_access_checks, "
                "safety_checks, host_declarations, declaration_version, "
                "declarations_completed_at, moderation_flags, verification_badges"
            )
            .in_("id", station_ids)
            .execute()
        )
        for station in stations_result.data or []:
            station_map[station["id"]] = _normalize_station_row(station)

    hydrated: List[Dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        station = station_map.get(item.get("station_id"))
        if station is not None:
            item["station"] = station
            if item.get("status") == "accepted":
                item["host_contact"] = {
                    "host_name": station.get("host_name"),
                    "host_phone": station.get("host_phone"),
                    "host_upi_id": station.get("host_upi_id"),
                }
        hydrated.append(item)
    return hydrated

# --- Endpoints ---

@router.get("/aggregate", response_model=List[AggregatedChargingStation])
async def get_aggregated_stations(
    lat: float,
    lng: float,
    radius: float = 10.0,
    _auth: Dict[str, Any] = Depends(require_auth),
):
    """
    Aggregate chargers from external APIs plus EVraahein-owned data sources,
    dedupe them on the backend, optionally persist canonical records, and return
    a single normalized station list for the map.
    """
    try:
        aggregated = await aggregate_chargers_nearby(lat, lng, radius)
        return [charger.to_response_json() for charger in aggregated]
    except Exception as e:
        logger.exception("Error aggregating chargers")
        raise HTTPException(status_code=500, detail=f"Error aggregating chargers: {e}")

@router.get("/", response_model=List[ChargingStation])
async def get_stations(lat: Optional[float] = None, lng: Optional[float] = None, radius: float = 5.0):
    """
    Get charging stations.
    If lat/lng are provided, returns stations within 'radius' km.
    Otherwise returns all verified public stations (limited to 100).
    """
    try:
        if lat is not None and lng is not None:
            # Use database-level geospatial filtering via RPC
            # Note: This requires the 'nearby_stations' function to be created in Supabase
            try:
                response = supabase.rpc("nearby_stations", {
                    "lat": lat, 
                    "long": lng, 
                    "radius_km": radius
                }).execute()
                rows = response.data or []
                visible_rows = [
                    _normalize_station_row(row)
                    for row in rows
                    if _station_is_publicly_visible(row)
                ]
                return visible_rows
            except Exception as rpc_error:
                logger.warning(
                    "nearby_stations RPC unavailable, using bounded SQL fallback: %s",
                    rpc_error,
                )
                lat_offset = radius / 111.0
                lng_offset = radius / max(1.0, 111.0 * abs(__import__("math").cos(__import__("math").radians(lat))))
                response = (
                    supabase.table("charging_stations")
                    .select("*")
                    .gte("latitude", lat - lat_offset)
                    .lte("latitude", lat + lat_offset)
                    .gte("longitude", lng - lng_offset)
                    .lte("longitude", lng + lng_offset)
                    .limit(250)
                    .execute()
                )
                stations = [
                    row
                    for row in (response.data or [])
                    if _station_is_publicly_visible(row)
                ]
                return _filter_stations_python(stations, lat, lng, radius)

        # Default fetch if no location provided
        query = supabase.table("charging_stations").select("*").eq("verification_status", "verified").limit(50)
        response = query.execute()
        return [
            _normalize_station_row(row)
            for row in (response.data or [])
            if _station_is_publicly_visible(row)
        ]
        
    except Exception as e:
        logger.exception("Error fetching stations")
        raise HTTPException(status_code=500, detail=f"Error fetching stations: {e}")

def _filter_stations_python(stations, lat, lng, radius):
    from math import radians, cos, sin, asin, sqrt
    
    filtered = []
    for station in stations:
        # Haversine formula
        lon1, lat1, lon2, lat2 = map(radians, [lng, lat, station['longitude'], station['latitude']])
        dlon = lon2 - lon1 
        dlat = lat2 - lat1 
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a)) 
        r = 6371 
        dist = c * r
        
        if dist <= radius:
            station['distance'] = dist
            filtered.append(_normalize_station_row(station))
            
    return filtered

@router.get("/my-stations/{user_id}", response_model=List[ChargingStation])
async def get_my_stations(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = supabase.table("charging_stations").select("*").eq("owner_id", user_id).execute()
        return [_normalize_station_row(row) for row in (response.data or [])]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/", response_model=ChargingStation)
async def create_station(
    station: CreateStationRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, station.owner_id)
        data = station.dict()
        data["submitted_by"] = station.owner_id
        if station.is_private:
            data["verification_status"] = "verified" 
        
        response = supabase.table("charging_stations").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/host")
async def create_or_update_host_station(
    request: HostChargerRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.owner_id)

        location_access_checks = _normalize_checkbox_object(
            request.location_access_checks,
            LOCATION_ACCESS_CHECK_KEYS,
        )
        safety_checks = _normalize_checkbox_object(
            request.safety_checks,
            SAFETY_CHECK_KEYS,
        )
        host_declarations = _normalize_checkbox_object(
            request.host_declarations,
            HOST_DECLARATION_KEYS,
        )
        if not all(host_declarations.values()):
            raise HTTPException(
                status_code=400,
                detail="All host declarations must be accepted before listing a private charger.",
            )

        charger_photos = _normalize_text_list(request.charger_photos)
        parking_photos = _normalize_text_list(request.parking_photos)
        moderation_flags = _normalize_text_list([])
        if not all(location_access_checks.values()):
            moderation_flags.append("location_access_incomplete")
        if not all(safety_checks.values()):
            moderation_flags.append("safety_check_incomplete")

        verification_badges = _build_host_verification_badges(
            owner_id=request.owner_id,
            charger_photos=charger_photos,
            parking_photos=parking_photos,
        )

        # Compute a suggested energy-based access amount when the host enters
        # recovery cost + convenience margin.
        computed_price_per_kwh = request.price_per_kwh
        if (
            request.electricity_cost_per_kwh is not None
            and request.host_margin_per_kwh is not None
        ):
            computed_price_per_kwh = round(
                request.electricity_cost_per_kwh + request.host_margin_per_kwh, 2
            )
        elif request.electricity_cost_per_kwh is not None and computed_price_per_kwh is None:
            computed_price_per_kwh = request.electricity_cost_per_kwh

        payload = {
            "name": request.name,
            "address": request.address,
            "latitude": request.latitude,
            "longitude": request.longitude,
            "provider": request.provider or "Community Host",
            "connector_types": request.connector_types,
            "power_kw": request.power_kw,
            "is_private": True,
            "owner_id": request.owner_id,
            "access_type": "Private",
            "access_instructions": request.access_instructions,
            "submitted_by": request.owner_id,
            "verification_status": "verified",
            "host_name": request.host_name,
            "host_phone": request.host_phone,
            "host_upi_id": request.host_upi_id,
            "electricity_cost_per_kwh": request.electricity_cost_per_kwh,
            "host_margin_per_kwh": request.host_margin_per_kwh,
            "price_per_kwh": computed_price_per_kwh,
            "price_per_session": request.price_per_session,
            "available_from": request.available_from,
            "available_to": request.available_to,
            "available_days": request.available_days,
            "available_hours": request.available_hours,
            "is_accepting_requests": request.is_accepting_requests,
            "parking_notes": request.parking_notes,
            "house_rules": request.house_rules,
            "amenities": request.amenities,
            "charger_photos": charger_photos,
            "parking_photos": parking_photos,
            "property_type": request.property_type,
            "visitor_access_type": request.visitor_access_type,
            "vehicle_size_support": request.vehicle_size_support,
            "location_access_checks": location_access_checks,
            "safety_checks": safety_checks,
            "host_declarations": host_declarations,
            "declaration_version": request.declaration_version or HOST_DECLARATION_VERSION,
            "declarations_completed_at": datetime.now().isoformat(),
            "moderation_flags": moderation_flags,
            "verification_badges": verification_badges,
        }

        if request.station_id:
            existing = (
                supabase.table("charging_stations")
                .select("*")
                .eq("id", request.station_id)
                .maybe_single()
                .execute()
            )
            if not existing.data:
                raise HTTPException(status_code=404, detail="Hosted charger not found")
            if existing.data.get("owner_id") != request.owner_id:
                raise HTTPException(status_code=403, detail="You can only update your own hosted charger")

            response = (
                supabase.table("charging_stations")
                .update(payload)
                .eq("id", request.station_id)
                .execute()
            )
            if not response.data:
                raise HTTPException(status_code=500, detail="Hosted charger could not be updated")
            return _normalize_station_row(response.data[0])

        response = supabase.table("charging_stations").insert(payload).execute()
        if not response.data:
            raise HTTPException(status_code=500, detail="Hosted charger could not be created")
        return _normalize_station_row(response.data[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error creating or updating hosted charger")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/hosted/{user_id}")
async def get_my_hosted_stations(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = (
            supabase.table("charging_stations")
            .select("*")
            .eq("owner_id", user_id)
            .eq("is_private", True)
            .execute()
        )
        rows = [_normalize_station_row(row) for row in (response.data or [])]
        rows.sort(
            key=lambda row: (
                row.get("updated_at") or row.get("created_at") or "",
                row.get("id") or "",
            ),
            reverse=True,
        )
        return rows
    except Exception as e:
        logger.exception("Error fetching hosted chargers for user %s", user_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/request")
async def create_charger_request(
    request: CreateChargerRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.requester_user_id)
        station_response = (
            supabase.table("charging_stations")
            .select("*")
            .eq("id", request.station_id)
            .maybe_single()
            .execute()
        )
        station = station_response.data
        if not station:
            raise HTTPException(status_code=404, detail="Hosted charger not found")
        if not bool(station.get("is_private") or False):
            raise HTTPException(status_code=400, detail="Charge requests are only available for hosted private chargers")
        if (station.get("verification_status") or "pending") != "verified":
            raise HTTPException(status_code=400, detail="This hosted charger is not live yet")
        if not bool(station.get("is_accepting_requests") or False):
            raise HTTPException(status_code=400, detail="This host is not currently accepting requests")
        if station.get("owner_id") == request.requester_user_id:
            raise HTTPException(status_code=400, detail="You cannot request charging from your own hosted charger")

        duplicate = (
            supabase.table("charger_requests")
            .select("id")
            .eq("station_id", request.station_id)
            .eq("requester_user_id", request.requester_user_id)
            .eq("status", "pending")
            .limit(1)
            .execute()
        )
        if duplicate.data:
            raise HTTPException(status_code=409, detail="You already have a pending request for this charger")

        estimated_amount = None
        if station.get("price_per_session") is not None:
            session_cost = float(station["price_per_session"])
            platform_fee = max(
                PLATFORM_FEE_MINIMUM_INR,
                session_cost * PLATFORM_FEE_PERCENT / 100,
            )
            estimated_amount = round(session_cost + platform_fee, 2)
        elif station.get("price_per_kwh") is not None:
            # Estimate using SOC gap and a 40 kWh reference battery.
            # This is rough; the final settlement uses the host-confirmed session amount.
            soc_gap = max(0, 100 - (request.current_soc or 50)) / 100
            estimated_kwh = round(soc_gap * 40.0, 1)
            energy_cost = round(estimated_kwh * float(station["price_per_kwh"]), 2)
            platform_fee = round(
                max(PLATFORM_FEE_MINIMUM_INR, energy_cost * PLATFORM_FEE_PERCENT / 100), 2
            )
            estimated_amount = round(energy_cost + platform_fee, 2)

        payload = {
            "station_id": request.station_id,
            "host_user_id": station.get("owner_id"),
            "requester_user_id": request.requester_user_id,
            "requester_name": request.requester_name or auth_user.get("metadata", {}).get("name") or auth_user.get("email"),
            "requester_phone": request.requester_phone,
            "vehicle_name": request.vehicle_name,
            "current_soc": request.current_soc,
            "message": request.message,
            "requested_start_at": request.requested_start_at.isoformat(),
            "requested_end_at": request.requested_end_at.isoformat() if request.requested_end_at else None,
            "estimated_amount": estimated_amount,
        }
        response = supabase.table("charger_requests").insert(payload).execute()
        if not response.data:
            raise HTTPException(status_code=500, detail="Charge request could not be created")
        return _hydrate_request_rows(response.data)[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error creating charger request")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/requests/incoming/{user_id}")
async def get_incoming_charger_requests(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = (
            supabase.table("charger_requests")
            .select("*")
            .eq("host_user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return _hydrate_request_rows(response.data or [])
    except Exception as e:
        logger.exception("Error fetching incoming charger requests for user %s", user_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/requests/outgoing/{user_id}")
async def get_outgoing_charger_requests(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = (
            supabase.table("charger_requests")
            .select("*")
            .eq("requester_user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return _hydrate_request_rows(response.data or [])
    except Exception as e:
        logger.exception("Error fetching outgoing charger requests for user %s", user_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/request/{request_id}/decision")
async def decide_charger_request(
    request_id: str,
    decision: ChargerRequestDecisionRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, decision.host_user_id)
        if decision.status not in {"accepted", "rejected"}:
            raise HTTPException(status_code=400, detail="Decision status must be accepted or rejected")

        existing = (
            supabase.table("charger_requests")
            .select("*")
            .eq("id", request_id)
            .maybe_single()
            .execute()
        )
        if not existing.data:
            raise HTTPException(status_code=404, detail="Charge request not found")
        if existing.data.get("host_user_id") != decision.host_user_id:
            raise HTTPException(status_code=403, detail="You can only manage requests for your own hosted chargers")
        if existing.data.get("status") != "pending":
            raise HTTPException(status_code=409, detail="Only pending requests can be accepted or rejected")

        response = (
            supabase.table("charger_requests")
            .update(
                {
                    "status": decision.status,
                    "host_response": decision.host_response,
                }
            )
            .eq("id", request_id)
            .execute()
        )
        if not response.data:
            raise HTTPException(status_code=500, detail="Charge request could not be updated")
        return _hydrate_request_rows(response.data)[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error deciding charger request %s", request_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/request/{request_id}/complete")
async def complete_charger_request(
    request_id: str,
    request: ChargerRequestCompleteRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.host_user_id)
        existing = (
            supabase.table("charger_requests")
            .select("*")
            .eq("id", request_id)
            .maybe_single()
            .execute()
        )
        if not existing.data:
            raise HTTPException(status_code=404, detail="Charge request not found")
        if existing.data.get("host_user_id") != request.host_user_id:
            raise HTTPException(status_code=403, detail="You can only complete requests for your own hosted chargers")
        if existing.data.get("status") != "accepted":
            raise HTTPException(status_code=409, detail="Only accepted requests can be marked completed")

        response = (
            supabase.table("charger_requests")
            .update(
                {
                    "status": "completed",
                    "completed_at": datetime.now().isoformat(),
                }
            )
            .eq("id", request_id)
            .execute()
        )
        if not response.data:
            raise HTTPException(status_code=500, detail="Charge request could not be completed")
        return _hydrate_request_rows(response.data)[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error completing charger request %s", request_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/request/{request_id}/settle")
async def settle_charger_request(
    request_id: str,
    body: ChargerRequestSettleRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """
    Host enters the actual kWh delivered. Backend computes:
      energy_cost   = kwh_delivered × price_per_kwh
      convenience_fee = max(₹2, 5% of energy_cost)
      final_amount  = energy_cost + convenience_fee
    Status is moved to 'completed' atomically with the settlement.
    """
    try:
        ensure_same_user(auth_user, body.host_user_id)

        if body.kwh_delivered <= 0:
            raise HTTPException(status_code=400, detail="kwh_delivered must be greater than 0")

        existing = (
            supabase.table("charger_requests")
            .select("*, charging_stations(price_per_kwh, price_per_session)")
            .eq("id", request_id)
            .maybe_single()
            .execute()
        )
        if not existing.data:
            raise HTTPException(status_code=404, detail="Charge request not found")

        row = existing.data
        if row.get("host_user_id") != body.host_user_id:
            raise HTTPException(status_code=403, detail="You can only settle requests for your own hosted chargers")
        if row.get("status") not in ("accepted", "completed"):
            raise HTTPException(status_code=409, detail="Only accepted or completed requests can be settled")

        station = row.get("charging_stations") or {}
        price_per_kwh = station.get("price_per_kwh")
        price_per_session = station.get("price_per_session")

        if price_per_kwh is not None:
            energy_cost = round(body.kwh_delivered * float(price_per_kwh), 2)
        elif price_per_session is not None:
            energy_cost = round(float(price_per_session), 2)
        else:
            raise HTTPException(
                status_code=400,
                detail="This charger has no access pricing set. Add an energy-based or session amount before settling.",
            )

        platform_fee = round(
            max(PLATFORM_FEE_MINIMUM_INR, energy_cost * PLATFORM_FEE_PERCENT / 100), 2
        )
        final_amount = round(energy_cost + platform_fee, 2)

        update_payload = {
            "status": "completed",
            "completed_at": datetime.now().isoformat(),
            "kwh_delivered": body.kwh_delivered,
            "energy_cost": energy_cost,
            "platform_fee": platform_fee,
            "final_amount": final_amount,
            "settled_at": datetime.now().isoformat(),
        }

        response = (
            supabase.table("charger_requests")
            .update(update_payload)
            .eq("id", request_id)
            .execute()
        )
        if not response.data:
            raise HTTPException(status_code=500, detail="Settlement could not be saved")

        result = _hydrate_request_rows(response.data)[0]
        result["settlement"] = {
            "kwh_delivered": body.kwh_delivered,
            "price_per_kwh": price_per_kwh,
            "energy_cost": energy_cost,
            "platform_fee": platform_fee,
            "final_amount": final_amount,
        }
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error settling charger request %s", request_id)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/history/{user_id}", response_model=List[ChargingSession])
async def get_charging_history(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = supabase.table("charging_sessions").select("*").eq("user_id", user_id).order("start_time", desc=True).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/session", response_model=ChargingSession)
async def log_session(
    session: CreateSessionRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, session.user_id)
        data = session.dict()
        response = supabase.table("charging_sessions").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/checkins/{user_id}", response_model=List[CheckIn])
async def get_my_checkins(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = supabase.table("station_checkins").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        return response.data
    except Exception as e:
        logger.exception("Error fetching checkins for user %s", user_id)
        raise HTTPException(status_code=500, detail=f"Error fetching checkins: {e}")

@router.get("/checkin/station/{station_id}/latest")
async def get_latest_station_checkin(station_id: str):
    """Get the latest check-in for a specific station"""
    try:
        response = supabase.table("station_checkins").select("*").eq("station_id", station_id).order("created_at", desc=True).limit(1).execute()
        if response.data and len(response.data) > 0:
            return response.data[0]
        return None
    except Exception as e:
        logger.exception("Error fetching latest checkin for station %s", station_id)
        raise HTTPException(status_code=500, detail=f"Error fetching latest checkin: {e}")

@router.post("/checkin", response_model=CheckIn)
async def create_checkin(
    checkin: CreateCheckInRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, checkin.user_id)

        # Exclude fields that are not DB columns
        _non_db = {"user_name", "points_earned"}
        data = {k: v for k, v in checkin.dict().items() if k not in _non_db and v is not None}
        data['created_at'] = datetime.now().isoformat()

        # Insert checkin — use service client to bypass RLS (user already verified above)
        response = service_supabase.table("station_checkins").insert(data).execute()

        # Reward points logic - use points from request (default 10)
        points_to_award = checkin.points_earned or 10
        try:
            from utils.gamification_utils import award_points_internal
            await award_points_internal(checkin.user_id, points_to_award, 'check_in')
        except Exception as e:
            logger.warning("Error updating points for checkin: %s", e)

        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def anonymize_name(name: str) -> str:
    """Anonymize name: show first and last char, star the rest"""
    if not name or len(name) < 2:
        return "A***r"
    parts = name.split()
    if len(parts) == 1:
        word = parts[0]
        if len(word) <= 2:
            return word
        return word[0] + '*' * (len(word) - 2) + word[-1]
    else:
        # For multi-word names, show first char of first word and last char of last word
        first_word = parts[0]
        last_word = parts[-1]
        return first_word[0] + '***' + last_word[-1]

@router.get("/checkins/public", response_model=List[CheckIn])
async def get_public_checkins(limit: int = 50):
    """Get recent public check-ins with anonymized user names"""
    try:
        response = supabase.table("station_checkins").select("*").order("created_at", desc=True).limit(limit).execute()
        checkins = response.data
        
        # Anonymize user names
        for checkin in checkins:
            if 'user_name' in checkin and checkin['user_name']:
                checkin['user_name'] = anonymize_name(checkin['user_name'])
            else:
                checkin['user_name'] = "A***r"  # Default anonymized name
        
        return checkins
    except Exception as e:
        logger.exception("Error fetching public checkins")
        raise HTTPException(status_code=500, detail=f"Error fetching public checkins: {e}")

@router.post("/checkin/vote")
async def vote_checkin(
    vote: VoteRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Upvote or downvote a check-in"""
    try:
        ensure_same_user(auth_user, vote.user_id)
        # Get current checkin
        checkin_response = supabase.table("station_checkins").select("upvotes, downvotes").eq("id", vote.checkin_id).single().execute()
        
        if not checkin_response.data:
            raise HTTPException(status_code=404, detail="Check-in not found")
        
        current = checkin_response.data
        
        if vote.vote_type == "upvote":
            new_upvotes = (current.get('upvotes') or 0) + 1
            supabase.table("station_checkins").update({"upvotes": new_upvotes}).eq("id", vote.checkin_id).execute()
            return {"upvotes": new_upvotes, "downvotes": current.get('downvotes') or 0}
        elif vote.vote_type == "downvote":
            new_downvotes = (current.get('downvotes') or 0) + 1
            supabase.table("station_checkins").update({"downvotes": new_downvotes}).eq("id", vote.checkin_id).execute()
            return {"upvotes": current.get('upvotes') or 0, "downvotes": new_downvotes}
        else:
            raise HTTPException(status_code=400, detail="Invalid vote type. Use 'upvote' or 'downvote'")
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error voting checkin")
        raise HTTPException(status_code=500, detail=f"Error voting checkin: {str(e)}")

@router.post("/upload-checkin-image")
async def upload_checkin_image(file: UploadFile = File(...)):
    """Upload an image for a check-in to Supabase Storage"""
    try:
        # Validate file type
        allowed_types = ["image/jpeg", "image/jpg", "image/png", "image/webp"]
        if file.content_type not in allowed_types:
            raise HTTPException(status_code=400, detail="Invalid file type. Only JPEG, PNG, and WebP are allowed.")
        
        # Generate unique filename
        file_ext = file.filename.split(".")[-1]
        unique_filename = f"checkin_{uuid.uuid4()}.{file_ext}"
        
        # Read file content
        file_content = await file.read()
        
        # Upload to Supabase Storage
        # Bucket name: 'checkin-images' (must be created in Supabase)
        storage_response = supabase.storage.from_("checkin-images").upload(
            unique_filename,
            file_content,
            {"content-type": file.content_type}
        )
        
        # Get public URL
        public_url = supabase.storage.from_("checkin-images").get_public_url(unique_filename)
        
        return {"image_url": public_url}
    except Exception as e:
        logger.exception("Error uploading checkin image")
        raise HTTPException(status_code=500, detail=f"Error uploading image: {str(e)}")


@router.post("/upload-hosted-charger-image")
async def upload_hosted_charger_image(file: UploadFile = File(...)):
    """Upload a hosted charger or parking/access image to Supabase Storage."""
    try:
        allowed_types = ["image/jpeg", "image/jpg", "image/png", "image/webp"]
        if file.content_type not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail="Invalid file type. Only JPEG, PNG, and WebP are allowed.",
            )

        file_ext = file.filename.split(".")[-1]
        unique_filename = f"hosted_charger_{uuid.uuid4()}.{file_ext}"
        file_content = await file.read()

        supabase.storage.from_("hosted-charger-images").upload(
            unique_filename,
            file_content,
            {"content-type": file.content_type},
        )

        public_url = supabase.storage.from_("hosted-charger-images").get_public_url(
            unique_filename
        )
        return {"image_url": public_url}
    except Exception as e:
        logger.exception("Error uploading hosted charger image")
        raise HTTPException(status_code=500, detail=f"Error uploading image: {str(e)}")

# --- Saved Chargers Endpoints ---

class ChargerAlongRoute(BaseModel):
    """Charger with distance information along a route"""
    id: str
    name: str
    latitude: float
    longitude: float
    address: Optional[str]
    provider: Optional[str]
    connector_types: List[str]
    power_kw: Optional[float]
    distance_from_origin_km: float
    is_optimal: bool  # True if on optimal route, False if alternative nearby
    charger_type: str  # "optimal", "alternative", or "far"


class ChargerOnRouteRequest(BaseModel):
    origin_lat: float
    origin_lng: float
    destination_lat: float
    destination_lng: float
    polyline: Optional[List[dict]] = None  # List of {latitude, longitude}
    radius_km: float = 20.0  # Search radius around route


class SaveChargerRequest(BaseModel):
    user_id: str
    station_id: str

@router.post("/along-route", response_model=List[ChargerAlongRoute])
async def get_chargers_along_route(request_data: ChargerOnRouteRequest):
    """
    Get chargers along a route corridor.
    - Creates a 4-5km buffer zone around the actual route
    - Only returns chargers within 5km perpendicular distance to the route
    - Searches along the full route direction (not just from origin)
    """
    try:
        from math import radians, cos, sin, asin, sqrt, atan2, degrees

        def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
            """Calculate distance between two points in km"""
            lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
            dlon = lon2 - lon1
            dlat = lat2 - lat1
            a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
            c = 2 * asin(sqrt(a))
            r = 6371
            return c * r

        def get_route_bounds(polyline: List[dict], buffer_km: float = 5.0) -> tuple:
            """Get bounding box that encompasses route with buffer"""
            if not polyline:
                return None

            lats = [p['latitude'] for p in polyline]
            lngs = [p['longitude'] for p in polyline]

            min_lat, max_lat = min(lats), max(lats)
            min_lng, max_lng = min(lngs), max(lngs)

            # Add buffer (roughly 5km = 0.045 degrees)
            lat_buffer = buffer_km / 111.0
            lng_buffer = buffer_km / (111.0 * cos(radians((min_lat + max_lat) / 2)) if (min_lat + max_lat) / 2 != 0 else 111.0)

            return (min_lat - lat_buffer, max_lat + lat_buffer,
                    min_lng - lng_buffer, max_lng + lng_buffer)

        def sample_polyline(polyline: List[dict], max_samples: int = 100) -> List[dict]:
            """Sample polyline to reduce computation. Always includes start and end."""
            if len(polyline) <= max_samples:
                return polyline

            sampled = [polyline[0]]  # Always include start
            step = len(polyline) / max_samples
            for i in range(1, max_samples - 1):
                sampled.append(polyline[int(i * step)])
            sampled.append(polyline[-1])  # Always include end
            return sampled

        def perpendicular_distance_to_polyline(lat: float, lng: float, polyline: List[dict]) -> float:
            """Calculate perpendicular distance from point to nearest segment in polyline (sampled)"""
            if not polyline or len(polyline) < 2:
                return float('inf')

            # Sample polyline to reduce computation (100 points max instead of potentially 1000+)
            sampled = sample_polyline(polyline, max_samples=100)
            min_dist = float('inf')

            for i in range(len(sampled) - 1):
                p1 = sampled[i]
                p2 = sampled[i + 1]

                lat1, lng1 = p1['latitude'], p1['longitude']
                lat2, lng2 = p2['latitude'], p2['longitude']

                # Calculate segment length
                segment_dist = haversine_distance(lat1, lng1, lat2, lng2)

                if segment_dist < 0.01:  # Points too close, use direct distance
                    dist = haversine_distance(lat, lng, lat1, lng1)
                    min_dist = min(min_dist, dist)
                    continue

                # Distance from point to endpoints
                dist_to_p1 = haversine_distance(lat, lng, lat1, lng1)
                dist_to_p2 = haversine_distance(lat, lng, lat2, lng2)

                # Use perpendicular distance approximation via cross product
                # This is faster than full cross-track distance formula
                cross_dist = abs((lng2 - lng1) * (lat1 - lat) - (lat2 - lat1) * (lng1 - lng))
                perp_dist = cross_dist / max(0.001, segment_dist * 111.0)  # Convert to km

                min_dist = min(min_dist, perp_dist, dist_to_p1, dist_to_p2)

            return min_dist

        # Use polyline if provided, otherwise create one from origin/destination
        if request_data.polyline and len(request_data.polyline) > 0:
            route_polyline = request_data.polyline
        else:
            route_polyline = [
                {"latitude": request_data.origin_lat, "longitude": request_data.origin_lng},
                {"latitude": request_data.destination_lat, "longitude": request_data.destination_lng},
            ]

        # Get bounding box of route with 5km buffer
        bounds = get_route_bounds(route_polyline, buffer_km=5.0)
        if not bounds:
            return []

        min_lat, max_lat, min_lng, max_lng = bounds

        # Query chargers within the route corridor bounds
        response = supabase.table("charging_stations").select("*").eq("verification_status", "verified") \
            .gte("latitude", min_lat) \
            .lte("latitude", max_lat) \
            .gte("longitude", min_lng) \
            .lte("longitude", max_lng) \
            .limit(500) \
            .execute()

        all_stations = [row for row in (response.data or []) if _station_is_publicly_visible(row)]

        # Process each charger - ONLY include if within 5km of route
        chargers_along_route: List[ChargerAlongRoute] = []
        ROUTE_BUFFER_KM = 5.0  # Only chargers within 5km of the route corridor

        for station in all_stations:
            lat, lng = station.get('latitude'), station.get('longitude')
            if lat is None or lng is None:
                continue

            # Calculate perpendicular distance to route
            dist_to_route = perpendicular_distance_to_polyline(lat, lng, route_polyline)

            # SKIP if too far from the actual route
            if dist_to_route > ROUTE_BUFFER_KM:
                continue

            # Distance from origin (for sorting)
            dist_from_origin = haversine_distance(
                request_data.origin_lat,
                request_data.origin_lng,
                lat,
                lng
            )

            # Determine if optimal (very close to route, <2km)
            is_optimal = dist_to_route <= 2.0

            charger_type = "optimal" if is_optimal else "alternative"

            chargers_along_route.append(ChargerAlongRoute(
                id=station.get('id'),
                name=station.get('name'),
                latitude=lat,
                longitude=lng,
                address=station.get('address'),
                provider=station.get('provider'),
                connector_types=station.get('connector_types', []),
                power_kw=station.get('power_kw'),
                distance_from_origin_km=round(dist_from_origin, 1),
                is_optimal=is_optimal,
                charger_type=charger_type
            ))

        # Sort by distance from origin
        chargers_along_route.sort(key=lambda c: c.distance_from_origin_km)

        logger.info(f"Found {len(chargers_along_route)} chargers within 5km of route")
        return chargers_along_route

    except Exception as e:
        logger.exception("Error fetching chargers along route")
        raise HTTPException(status_code=500, detail=f"Error fetching chargers: {str(e)}")


@router.post("/save")
def save_charger(
    request: SaveChargerRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Save/favorite a charging station"""
    try:
        ensure_same_user(auth_user, request.user_id)
        result = supabase.table("saved_chargers").insert({
            "user_id": request.user_id,
            "station_id": request.station_id
        }).execute()
        return {"message": "Charger saved successfully", "data": result.data}
    except Exception as e:
        # Handle duplicate entries gracefully
        if "duplicate" in str(e).lower() or "unique" in str(e).lower():
            return {"message": "Charger already saved"}
        logger.exception("Error saving charger")
        raise HTTPException(status_code=500, detail=f"Error saving charger: {str(e)}")

@router.delete("/save/{user_id}/{station_id}")
def unsave_charger(
    user_id: str,
    station_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Unsave/unfavorite a charging station"""
    try:
        ensure_same_user(auth_user, user_id)
        result = supabase.table("saved_chargers").delete().eq("user_id", user_id).eq("station_id", station_id).execute()
        return {"message": "Charger unsaved successfully"}
    except Exception as e:
        logger.exception("Error unsaving charger")
        raise HTTPException(status_code=500, detail=f"Error unsaving charger: {str(e)}")

@router.get("/saved/{user_id}")
def get_saved_chargers(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Get all saved chargers for a user with station details"""
    try:
        ensure_same_user(auth_user, user_id)
        # Get saved charger IDs
        saved_result = supabase.table("saved_chargers").select("station_id, created_at").eq("user_id", user_id).execute()
        
        if not saved_result.data:
            return []
        
        station_ids = [item['station_id'] for item in saved_result.data]
        
        # Get station details
        stations_result = supabase.table("charging_stations").select("*").in_("id", station_ids).execute()
        
        # Merge saved_at timestamp with station data
        saved_map = {item['station_id']: item['created_at'] for item in saved_result.data}
        for station in stations_result.data:
            station['saved_at'] = saved_map.get(station['id'])
        
        return stations_result.data
    except Exception as e:
        logger.exception("Error fetching saved chargers for user %s", user_id)
        raise HTTPException(status_code=500, detail=f"Error fetching saved chargers: {str(e)}")
