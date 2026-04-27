from __future__ import annotations

from datetime import datetime, timedelta
import math
from typing import Any, Optional

import flexpolyline
import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.util import get_remote_address

from config import settings

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)


class LatLng(BaseModel):
    latitude: float
    longitude: float


class VehicleRoutingProfile(BaseModel):
    brand: Optional[str] = None
    model: Optional[str] = None
    variant: Optional[str] = None
    range_efficiency: float = Field(default=0.8, ge=0.5, le=1.2)
    preferred_charging_networks: list[str] = Field(default_factory=list)
    estimated_range_km: Optional[float] = Field(default=None, gt=0)
    battery_capacity_kwh: Optional[float] = Field(default=None, gt=0)
    max_dc_charge_kw: Optional[float] = Field(default=None, gt=0)
    connector_types: Optional[list[str]] = None


class RouteRequest(BaseModel):
    origin: LatLng
    destination: LatLng
    current_soc: int = Field(ge=1, le=100)
    target_soc: int = Field(ge=1, le=100)
    soh: int = Field(default=100, ge=50, le=100)
    is_round_trip: bool = False
    short_stay_duration_min: int = Field(default=0, ge=0, le=1440)
    vehicle: Optional[VehicleRoutingProfile] = None


VEHICLE_LIBRARY: dict[tuple[str, str, str], dict[str, Any]] = {
    ("tata", "nexon ev", "max"): {
        "battery_capacity_kwh": 40.5,
        "usable_range_km": 320.0,
        "max_dc_charge_kw": 50.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 50, 20, 50, 30, 44, 36, 24, 40.5, 9],
    },
    ("tata", "tiago ev", "long range"): {
        "battery_capacity_kwh": 24.0,
        "usable_range_km": 220.0,
        "max_dc_charge_kw": 25.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 25, 10, 25, 16, 22, 20, 16, 24, 8],
    },
    ("mg", "zs ev", "exclusive"): {
        "battery_capacity_kwh": 50.3,
        "usable_range_km": 360.0,
        "max_dc_charge_kw": 50.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 50, 20, 50, 35, 46, 42, 32, 50.3, 10],
    },
    ("hyundai", "kona electric", "premium"): {
        "battery_capacity_kwh": 39.2,
        "usable_range_km": 320.0,
        "max_dc_charge_kw": 50.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 50, 16, 50, 26, 46, 32, 28, 39.2, 10],
    },
    ("mahindra", "xuv400", "el"): {
        "battery_capacity_kwh": 39.4,
        "usable_range_km": 300.0,
        "max_dc_charge_kw": 50.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 50, 15, 50, 26, 42, 31, 24, 39.4, 9],
    },
    ("mg", "comet ev", "plush"): {
        "battery_capacity_kwh": 17.3,
        "usable_range_km": 180.0,
        "max_dc_charge_kw": 7.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 7, 7, 7, 12, 7, 15, 5, 17.3, 3],
    },
}


CHARGE_OPERATOR_IDS: dict[str, str] = {
    # Placeholder mapping. HERE expects operator IDs, not display names.
}


async def _fetch_here_route(params: dict[str, str]) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.get("https://router.hereapi.com/v8/routes", params=params)
        response.raise_for_status()
        return response.json()


@router.post("/")
@limiter.limit("20/minute")
async def calculate_route(request: Request, route_req: RouteRequest):
    if not settings.HERE_API_KEY:
        raise HTTPException(status_code=503, detail="HERE routing is not configured")

    vehicle_profile = _resolve_vehicle_profile(route_req)
    base_params = _build_base_here_params(route_req)
    ev_params = _build_ev_here_params(base_params, route_req, vehicle_profile)

    try:
        ev_data = await _fetch_here_route(ev_params)
        if ev_data.get("routes"):
            parsed_routes = _parse_here_routes(
                ev_data,
                route_req,
                vehicle_profile,
                route_source="here_ev",
            )
            return _label_routes(parsed_routes)

        basic_data = await _fetch_here_route(_build_basic_here_params(base_params, route_req))
        if not basic_data.get("routes"):
            notices = ev_data.get("notices") or basic_data.get("notices") or []
            message = notices[0].get("title") if notices else "No reachable route was found"
            raise HTTPException(status_code=422, detail=message)

        parsed_routes = _parse_here_routes(
            basic_data,
            route_req,
            vehicle_profile,
            route_source="here_basic",
        )

        for route in parsed_routes:
            if _needs_charging_support(route, route_req):
                suggested_stops = await _suggest_charging_stops(route, route_req, vehicle_profile)
                _apply_suggested_stops(route, suggested_stops, route_req)
            _append_route_guidance(route, route_req)

        return _label_routes(parsed_routes)

    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"HERE routing failed: {exc}") from exc


def _build_base_here_params(request: RouteRequest) -> dict[str, str]:
    return {
        "apiKey": settings.HERE_API_KEY,
        "transportMode": "car",
        "routingMode": "fast",
        "origin": f"{request.origin.latitude},{request.origin.longitude}",
        "destination": f"{request.destination.latitude},{request.destination.longitude}",
        "alternatives": "3",
        "return": "polyline,summary,actions,instructions",
    }


def _build_basic_here_params(base_params: dict[str, str], request: RouteRequest) -> dict[str, str]:
    params = dict(base_params)
    params.update(
        {
            "ev[freeFlowSpeedTable]": "0,120,80,180",
            "ev[trafficSpeedTable]": "0,160,80,230",
            "ev[auxiliaryConsumption]": "1.8",
            "ev[initialCharge]": f"{max(4.0, request.current_soc / 100 * 40.0):.1f}",
            "ev[maxCharge]": "40.0",
        }
    )
    return params


def _build_ev_here_params(
    base_params: dict[str, str],
    request: RouteRequest,
    vehicle_profile: dict[str, Any],
) -> dict[str, str]:
    params = dict(base_params)
    max_charge = vehicle_profile["battery_capacity_kwh"]
    current_soc = request.current_soc / 100.0
    target_soc = max(request.target_soc, 10) / 100.0

    params.update(
        {
            "ev[freeFlowSpeedTable]": vehicle_profile["free_flow_speed_table"],
            "ev[trafficSpeedTable]": vehicle_profile["traffic_speed_table"],
            "ev[auxiliaryConsumption]": f"{vehicle_profile['auxiliary_consumption_kwh_per_h']:.2f}",
            "ev[makeReachable]": "true",
            "ev[initialCharge]": f"{max_charge * current_soc:.1f}",
            "ev[maxCharge]": f"{max_charge:.1f}",
            "ev[connectorTypes]": ",".join(vehicle_profile["connector_types"]),
            "ev[chargingCurve]": ",".join(
                _format_number(value) for value in vehicle_profile["charging_curve"]
            ),
            "ev[maxChargeAfterChargingStation]": f"{max_charge * vehicle_profile['max_charge_after_stop_ratio']:.1f}",
            "ev[minChargeAtDestination]": f"{max_charge * target_soc:.1f}",
            "ev[minChargeAtChargingStation]": f"{max_charge * vehicle_profile['min_charge_at_station_ratio']:.1f}",
            "ev[chargingSetupDuration]": str(vehicle_profile["charging_setup_duration_seconds"]),
        }
    )

    operator_ids = [
        CHARGE_OPERATOR_IDS[name.lower()]
        for name in vehicle_profile["preferred_charging_networks"]
        if name.lower() in CHARGE_OPERATOR_IDS
    ]
    if operator_ids:
        params["ev[preferredChargePointOperators]"] = ",".join(operator_ids)

    return params


def _resolve_vehicle_profile(request: RouteRequest) -> dict[str, Any]:
    vehicle = request.vehicle
    profile: dict[str, Any] = {
        "battery_capacity_kwh": 40.0,
        "usable_range_km": 280.0,
        "max_dc_charge_kw": 45.0,
        "connector_types": ["iec62196Type2Combo"],
        "charging_curve": [0, 45, 18, 45, 28, 38, 34, 24, 40, 10],
        "preferred_charging_networks": [],
        "auxiliary_consumption_kwh_per_h": 1.8,
        "free_flow_speed_table": "0,120,80,180",
        "traffic_speed_table": "0,160,80,230",
        "max_charge_after_stop_ratio": 0.85,
        "min_charge_at_station_ratio": 0.10,
        "charging_setup_duration_seconds": 600,
    }

    if vehicle:
        key = (
            (vehicle.brand or "").strip().lower(),
            (vehicle.model or "").strip().lower(),
            (vehicle.variant or "").strip().lower(),
        )
        profile.update(VEHICLE_LIBRARY.get(key, {}))
        if vehicle.estimated_range_km:
            profile["usable_range_km"] = vehicle.estimated_range_km
        if vehicle.battery_capacity_kwh:
            profile["battery_capacity_kwh"] = vehicle.battery_capacity_kwh
        if vehicle.max_dc_charge_kw:
            profile["max_dc_charge_kw"] = vehicle.max_dc_charge_kw
        if vehicle.connector_types:
            profile["connector_types"] = vehicle.connector_types
        profile["preferred_charging_networks"] = vehicle.preferred_charging_networks

        adjusted_range = (
            profile["usable_range_km"]
            * vehicle.range_efficiency
            * (request.soh / 100.0)
        )
        profile["usable_range_km"] = max(140.0, adjusted_range)
    else:
        profile["usable_range_km"] *= request.soh / 100.0

    return profile


def _parse_here_routes(
    data: dict[str, Any],
    request: RouteRequest,
    vehicle_profile: dict[str, Any],
    *,
    route_source: str,
) -> list[dict[str, Any]]:
    parsed_routes: list[dict[str, Any]] = []

    for index, route in enumerate(data.get("routes", [])):
        sections = route.get("sections", [])
        points: list[dict[str, float]] = []
        stops: list[dict[str, Any]] = [
            {
                "name": "Start",
                "location": {
                    "latitude": request.origin.latitude,
                    "longitude": request.origin.longitude,
                },
                "type": "origin",
                "arrivalTime": datetime.now().isoformat(),
                "arrivalSoc": request.current_soc,
                "departureSoc": request.current_soc,
                "advice": "Begin the trip with your current state of charge.",
            }
        ]
        total_distance_km = 0.0
        total_duration_min = 0.0
        route_guidance: list[str] = []
        last_soc = request.current_soc

        for section in sections:
            points.extend(_decode_section_polyline(section))
            summary = section.get("summary", {})
            total_distance_km += float(summary.get("length", 0)) / 1000.0
            total_duration_min += float(summary.get("duration", 0)) / 60.0

            charging_stop = _extract_here_charging_stop(
                section,
                vehicle_profile,
                fallback_arrival_soc=max(request.target_soc, min(last_soc, 25)),
                fallback_departure_soc=min(85, max(request.target_soc + 35, 60)),
            )
            if charging_stop:
                stops.append(charging_stop)
                route_guidance.append(
                    f"Stop at {charging_stop['name']} for about "
                    f"{charging_stop['chargeDurationMin']} minutes and continue at roughly "
                    f"{charging_stop['departureSoc']}% charge."
                )
                last_soc = charging_stop["departureSoc"] or last_soc

        destination_soc = _estimate_destination_soc(
            total_distance_km, request, vehicle_profile, len(stops) - 2
        )
        stops.append(
            {
                "name": "Destination",
                "location": {
                    "latitude": request.destination.latitude,
                    "longitude": request.destination.longitude,
                },
                "type": "destination",
                "arrivalTime": (
                    datetime.now() + timedelta(minutes=int(total_duration_min))
                ).isoformat(),
                "arrivalSoc": destination_soc,
                "departureSoc": destination_soc,
                "advice": "You should arrive with a comfortable charge buffer.",
            }
        )

        parsed_routes.append(
            {
                "id": f"{route_source}_{index}",
                "name": f"Route {index + 1}",
                "polyline": points,
                "totalDistanceKm": round(total_distance_km, 1),
                "totalDurationMin": round(total_duration_min, 1),
                "stops": stops,
                "estimatedCost": round(
                    sum(stop.get("cost", 0) or 0 for stop in stops if stop["type"] == "charging"),
                    0,
                ),
                "guidance": route_guidance,
            }
        )

    return parsed_routes


def _decode_section_polyline(section: dict[str, Any]) -> list[dict[str, float]]:
    polyline = section.get("polyline")
    if polyline:
        try:
            decoded = flexpolyline.decode(polyline)
            return [
                {"latitude": coord[0], "longitude": coord[1]}
                for coord in decoded
            ]
        except Exception:
            pass

    decoded_points: list[dict[str, float]] = []
    departure = section.get("departure", {}).get("place", {}).get("location")
    arrival = section.get("arrival", {}).get("place", {}).get("location")
    if departure:
        decoded_points.append(
            {"latitude": departure["lat"], "longitude": departure["lng"]}
        )
    if arrival:
        decoded_points.append({"latitude": arrival["lat"], "longitude": arrival["lng"]})
    return decoded_points


def _extract_here_charging_stop(
    section: dict[str, Any],
    vehicle_profile: dict[str, Any],
    *,
    fallback_arrival_soc: int,
    fallback_departure_soc: int,
) -> Optional[dict[str, Any]]:
    actions = []
    actions.extend(section.get("postActions", []))
    actions.extend(section.get("actions", []))

    for action in actions:
        action_name = str(action.get("action", "")).lower()
        if "charging" not in action_name:
            continue

        location = (
            action.get("place", {}).get("location")
            or section.get("arrival", {}).get("place", {}).get("location")
        )
        if not location:
            continue

        duration_min = int(round(float(action.get("duration", 0)) / 60.0)) or 25
        departure_soc = _extract_soc_percentage(
            action.get("targetCharge"), vehicle_profile["battery_capacity_kwh"]
        ) or fallback_departure_soc
        arrival_soc = _extract_soc_percentage(
            action.get("arrivalCharge"), vehicle_profile["battery_capacity_kwh"]
        ) or fallback_arrival_soc

        return {
            "name": action.get("place", {}).get("name")
            or action.get("station", {}).get("name")
            or "Recommended charging stop",
            "location": {
                "latitude": location["lat"],
                "longitude": location["lng"],
            },
            "type": "charging",
            "arrivalTime": section.get("arrival", {}).get("time") or datetime.now().isoformat(),
            "chargeDurationMin": duration_min,
            "targetSoc": departure_soc,
            "arrivalSoc": arrival_soc,
            "departureSoc": departure_soc,
            "cost": round(duration_min * 7.0, 0),
            "advice": "Follow this stop to keep enough battery buffer for the next leg.",
        }

    return None


def _extract_soc_percentage(value: Any, battery_capacity_kwh: float) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        numeric = float(value)
    elif isinstance(value, dict):
        for key in ("value", "amount", "charge", "remainingCharge"):
            if key in value and isinstance(value[key], (int, float)):
                numeric = float(value[key])
                break
        else:
            return None
    else:
        return None

    if numeric <= 100:
        return int(round(numeric))
    if battery_capacity_kwh <= 0:
        return None
    return int(round((numeric / battery_capacity_kwh) * 100))


def _estimate_destination_soc(
    total_distance_km: float,
    request: RouteRequest,
    vehicle_profile: dict[str, Any],
    charging_stops: int,
) -> int:
    usable_range = vehicle_profile["usable_range_km"]
    reserve_soc = max(request.target_soc, 10)
    recovered_soc = charging_stops * 55
    estimated = request.current_soc + recovered_soc - (total_distance_km / usable_range) * 100
    return max(reserve_soc, min(90, int(round(estimated))))


def _needs_charging_support(route: dict[str, Any], request: RouteRequest) -> bool:
    charging_stops = [stop for stop in route["stops"] if stop["type"] == "charging"]
    if charging_stops:
        return False

    destination = route["stops"][-1]
    arrival_soc = destination.get("arrivalSoc")
    return arrival_soc is None or arrival_soc <= request.target_soc + 5


async def _suggest_charging_stops(
    route: dict[str, Any],
    request: RouteRequest,
    vehicle_profile: dict[str, Any],
) -> list[dict[str, Any]]:
    if not settings.GOOGLE_MAPS_API_KEY or len(route["polyline"]) < 2:
        return []

    usable_range_km = vehicle_profile["usable_range_km"]
    reserve_soc = max(request.target_soc, 12)
    reserve_km = usable_range_km * reserve_soc / 100.0
    current_soc = request.current_soc
    current_distance_km = 0.0
    total_distance_km = route["totalDistanceKm"]
    suggestions: list[dict[str, Any]] = []
    used_place_ids: set[str] = set()
    attempt = 0

    while attempt < 4:
        remaining_distance_km = total_distance_km - current_distance_km
        available_leg_km = max(
            usable_range_km * current_soc / 100.0 - reserve_km,
            usable_range_km * 0.25,
        )
        if remaining_distance_km <= available_leg_km:
            break

        target_distance_km = min(
            total_distance_km - reserve_km,
            current_distance_km + available_leg_km * 0.85,
        )
        target_point = _point_along_polyline(route["polyline"], target_distance_km)
        chargers = await _search_nearby_ev_chargers(
            target_point["latitude"],
            target_point["longitude"],
        )
        charger = next(
            (item for item in chargers if item["place_id"] not in used_place_ids),
            None,
        )
        if charger is None:
            break

        used_place_ids.add(charger["place_id"])
        remaining_after_stop_km = total_distance_km - target_distance_km
        required_departure_soc = min(
            85,
            max(
                55,
                int(math.ceil((remaining_after_stop_km / usable_range_km) * 100 + reserve_soc + 8)),
            ),
        )
        arrival_soc = max(
            reserve_soc,
            int(round(current_soc - (target_distance_km - current_distance_km) / usable_range_km * 100)),
        )
        charge_minutes = _estimate_charge_minutes(
            arrival_soc=arrival_soc,
            departure_soc=required_departure_soc,
            vehicle_profile=vehicle_profile,
        )

        suggestions.append(
            {
                "name": charger["name"],
                "location": {
                    "latitude": charger["latitude"],
                    "longitude": charger["longitude"],
                },
                "type": "charging",
                "arrivalTime": (
                    datetime.now()
                    + timedelta(
                        minutes=int(
                            route["totalDurationMin"] * (target_distance_km / max(total_distance_km, 1))
                        )
                    )
                ).isoformat(),
                "chargeDurationMin": charge_minutes,
                "targetSoc": required_departure_soc,
                "arrivalSoc": arrival_soc,
                "departureSoc": required_departure_soc,
                "cost": round(charge_minutes * 7.0, 0),
                "advice": (
                    f"Reach this stop with about {arrival_soc}% battery, charge to "
                    f"{required_departure_soc}%, and continue with a healthy buffer."
                ),
            }
        )

        current_soc = required_departure_soc
        current_distance_km = target_distance_km
        attempt += 1

    return suggestions


async def _search_nearby_ev_chargers(latitude: float, longitude: float) -> list[dict[str, Any]]:
    url = "https://places.googleapis.com/v1/places:searchNearby"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.location,places.formattedAddress,"
            "places.evChargeOptions"
        ),
    }
    body = {
        "includedTypes": ["electric_vehicle_charging_station"],
        "maxResultCount": 8,
        "rankPreference": "DISTANCE",
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": latitude,
                    "longitude": longitude,
                },
                "radius": 25000.0,
            }
        },
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(url, headers=headers, json=body)
        response.raise_for_status()
        data = response.json()

    places: list[dict[str, Any]] = []
    for place in data.get("places", []):
        location = place.get("location")
        if not location:
            continue
        places.append(
            {
                "place_id": place.get("id"),
                "name": place.get("displayName", {}).get("text", "Charging station"),
                "latitude": location["latitude"],
                "longitude": location["longitude"],
                "address": place.get("formattedAddress", ""),
            }
        )
    return places


def _apply_suggested_stops(route: dict[str, Any], suggestions: list[dict[str, Any]], request: RouteRequest) -> None:
    if not suggestions:
        route["guidance"].append(
            "A direct charging plan was not available, so you should start with a higher state of charge for this trip."
        )
        return

    destination = route["stops"][-1]
    route["stops"] = [route["stops"][0], *suggestions, destination]
    route["estimatedCost"] = round(
        sum(stop.get("cost", 0) or 0 for stop in suggestions),
        0,
    )


def _append_route_guidance(route: dict[str, Any], request: RouteRequest) -> None:
    charging_stops = [stop for stop in route["stops"] if stop["type"] == "charging"]
    if charging_stops:
        route["guidance"].insert(
            0,
            f"Follow {len(charging_stops)} planned charging stop(s) to finish the trip with at least {request.target_soc}% battery.",
        )
        for index, stop in enumerate(charging_stops, start=1):
            route["guidance"].append(
                f"Stop {index}: {stop['name']} for {stop['chargeDurationMin']} minutes, from "
                f"{stop['arrivalSoc']}% to {stop['departureSoc']}%."
            )
    else:
        route["guidance"].append(
            "This route should be drivable without a charging stop if you begin with the selected state of charge."
        )

    destination = route["stops"][-1]
    route["guidance"].append(
        f"Expected arrival charge is about {destination.get('arrivalSoc', request.target_soc)}%."
    )


def _label_routes(routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not routes:
        return routes

    def charging_count(item: dict[str, Any]) -> int:
        return len([stop for stop in item["stops"] if stop["type"] == "charging"])

    fastest = min(routes, key=lambda item: item["totalDurationMin"])["id"]
    fewest_stops = min(routes, key=lambda item: (charging_count(item), item["totalDurationMin"]))["id"]
    balanced = min(
        routes,
        key=lambda item: (
            abs(charging_count(item) - 1),
            item["totalDurationMin"],
        ),
    )["id"]

    for route in routes:
        if route["id"] == fastest:
            route["name"] = "Fastest arrival"
        elif route["id"] == fewest_stops:
            route["name"] = "Fewest charging stops"
        elif route["id"] == balanced:
            route["name"] = "Balanced charging plan"

    return routes


def _estimate_charge_minutes(
    *,
    arrival_soc: int,
    departure_soc: int,
    vehicle_profile: dict[str, Any],
) -> int:
    delta_soc = max(0, departure_soc - arrival_soc)
    if delta_soc <= 0:
        return 10
    added_kwh = vehicle_profile["battery_capacity_kwh"] * (delta_soc / 100.0)
    effective_kw = max(vehicle_profile["max_dc_charge_kw"] * 0.75, 12.0)
    return max(12, int(round((added_kwh / effective_kw) * 60.0 + 8)))


def _point_along_polyline(polyline: list[dict[str, float]], target_distance_km: float) -> dict[str, float]:
    if not polyline:
        raise ValueError("Route polyline is empty")

    traversed = 0.0
    for start, end in zip(polyline, polyline[1:]):
        segment = _distance_km(
            start["latitude"],
            start["longitude"],
            end["latitude"],
            end["longitude"],
        )
        if traversed + segment >= target_distance_km:
            ratio = 0 if segment == 0 else (target_distance_km - traversed) / segment
            return {
                "latitude": start["latitude"] + (end["latitude"] - start["latitude"]) * ratio,
                "longitude": start["longitude"] + (end["longitude"] - start["longitude"]) * ratio,
            }
        traversed += segment

    return polyline[-1]


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_km = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lon / 2) ** 2
    )
    return 2 * radius_km * math.asin(math.sqrt(a))


def _format_number(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.1f}"
