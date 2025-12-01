from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import httpx
from config import settings
import random
from datetime import datetime, timedelta
import flexpolyline

router = APIRouter()

class LatLng(BaseModel):
    latitude: float
    longitude: float

class RouteRequest(BaseModel):
    origin: LatLng
    destination: LatLng
    current_soc: int
    target_soc: int
    soh: int = 100
    is_round_trip: bool = False
    short_stay_duration_min: int = 0

@router.post("/")
async def calculate_route(request: RouteRequest):
    if not settings.HERE_API_KEY:
        # Fallback to mock data if no key
        return _get_mock_routes(request)

    url = "https://router.hereapi.com/v8/routes"
    
    # Base parameters
    base_params = {
        "apiKey": settings.HERE_API_KEY,
        "transportMode": "car",
        "origin": f"{request.origin.latitude},{request.origin.longitude}",
        "destination": f"{request.destination.latitude},{request.destination.longitude}",
        "return": "polyline,summary,actions,instructions",
    }

    # EV Parameters (Attempt 1: With Charging Stops)
    ev_params = base_params.copy()
    ev_params.update({
        "ev[freeFlowSpeedTable]": "0,200,140,300", # Wh/km
        "ev[trafficSpeedTable]": "0,200,140,300", # Wh/km
        "ev[auxiliaryConsumption]": "0.1",
        "ev[makeReachable]": "true",
        "ev[initialCharge]": f"{request.current_soc}",
        "ev[maxCharge]": "100",
        "ev[connectorTypes]": "iec62196Type2Combo", 
        "ev[chargingCurve]": "0,30,80,30,100,5",
        "ev[maxChargeAfterChargingStation]": "80",
        "ev[minChargeAtDestination]": "10",
    })

    async with httpx.AsyncClient() as client:
        try:
            # Attempt 1: Full EV Routing
            print(f"Attempt 1 - EV Routing Request: {url}")
            print(f"Params: {ev_params}")
            response = await client.get(url, params=ev_params)
            if response.status_code == 200:
                data = response.json()
                if data.get("routes"):
                    return _parse_here_response(data, request)
            
            print(f"EV Routing failed (Status {response.status_code} or no routes). Retrying without charging stops...")
            
            # Attempt 2: Basic Navigation (No Charging Stops)
            # Remove strict EV constraints that might block routing
            basic_params = base_params.copy()
            # We can still pass basic EV info for consumption calc, but disable makeReachable
            basic_params.update({
                 "ev[freeFlowSpeedTable]": "0,200,140,300",
                 "ev[trafficSpeedTable]": "0,200,140,300",
                 "ev[auxiliaryConsumption]": "0.1",
                 # "ev[makeReachable]": "false", # Default is false
            })
            
            print(f"Attempt 2 - Basic Routing Request: {url}")
            print(f"Params: {basic_params}")
            response = await client.get(url, params=basic_params)
            response.raise_for_status()
            data = response.json()
            return _parse_here_response(data, request)

        except httpx.HTTPError as e:
            print(f"HERE API Error: {e}")
            # Fallback to mock on error for robustness
            return _get_mock_routes(request)

def _parse_here_response(data, request):
    routes = []
    for i, route in enumerate(data.get("routes", [])):
        sections = route.get("sections", [])
        
        # Decode polyline (HERE v8 uses flexible polyline, but we'll assume simple line string or decode if needed)
        # For simplicity in this step, we'll just take the start/end of sections and draw straight lines 
        # OR if the frontend expects a list of lat/lng, we need to decode the `polyline` string from HERE.
        # HERE v8 returns `polyline` field in sections.
        
        # NOTE: Decoding flexible polyline is complex. For this MVP step, 
        # we will extract the `departure` and `arrival` of each section to form a rough path.
        # In a production app, use a proper flexible polyline decoder.
        
        points = []
        stops = []
        total_dist = 0
        total_dur = 0
        
        for section in sections:
            # Decode polyline
            if "polyline" in section:
                try:
                    decoded_coords = flexpolyline.decode(section["polyline"])
                    # flexpolyline returns list of (lat, lng, [elevation, ...]) tuples
                    for coord in decoded_coords:
                        points.append({"latitude": coord[0], "longitude": coord[1]})
                except Exception as e:
                    print(f"Error decoding polyline: {e}")
                    # Fallback to start/end points
                    dep = section["departure"]["place"]["location"]
                    points.append({"latitude": dep["lat"], "longitude": dep["lng"]})
                    arr = section["arrival"]["place"]["location"]
                    points.append({"latitude": arr["lat"], "longitude": arr["lng"]})
            else:
                # Fallback if no polyline
                dep = section["departure"]["place"]["location"]
                points.append({"latitude": dep["lat"], "longitude": dep["lng"]})
                arr = section["arrival"]["place"]["location"]
                points.append({"latitude": arr["lat"], "longitude": arr["lng"]})
            
            summary = section["summary"]
            total_dist += summary["length"] / 1000.0 # meters to km
            total_dur += summary["duration"] / 60.0 # seconds to min
            
            # Check for charging actions
            if "actions" in section:
                for action in section["actions"]:
                    if action["action"] == "chargingStation":
                        # This is a charging stop
                        stops.append({
                            "name": "Charging Station", # HERE doesn't always give name in actions
                            "location": {"latitude": action["place"]["location"]["lat"], "longitude": action["place"]["location"]["lng"]},
                            "type": "charging",
                            "arrivalTime": datetime.now().isoformat(), # Placeholder
                            "chargeDurationMin": action.get("duration", 0) / 60,
                            "targetSoc": 80, # Placeholder
                            "arrivalSoc": 10, # Placeholder
                            "departureSoc": 80, # Placeholder
                            "cost": 200 # Placeholder
                        })

        routes.append({
            "id": f"here_route_{i}",
            "name": f"Route {i+1}",
            "polyline": points,
            "totalDistanceKm": total_dist,
            "totalDurationMin": total_dur,
            "stops": stops,
            "estimatedCost": len(stops) * 200
        })
        
    if not routes:
        return _get_mock_routes(request)
        
    return routes

def _get_mock_routes(request):
    # Plan A: Fewest Long Stops (Maximize distance between stops, longer charge times)
    plan_a = _create_dummy_route(
        id="plan_a",
        name="Plan A (Fewest Long Stops)",
        origin=request.origin,
        destination=request.destination,
        distance_km=145.0,
        duration_min=180,
        stops=1,
        color_offset=0.0,
        strategy="long_stops"
    )
    
    # Plan B: More Short Stops (Hop between chargers, shorter charge times)
    plan_b = _create_dummy_route(
        id="plan_b",
        name="Plan B (Short Stops)",
        origin=request.origin,
        destination=request.destination,
        distance_km=160.0,
        duration_min=200,
        stops=3,
        color_offset=0.01,
        strategy="short_stops"
    )
    
    # Plan C: Balanced (Average)
    plan_c = _create_dummy_route(
        id="plan_c",
        name="Plan C (Balanced)",
        origin=request.origin,
        destination=request.destination,
        distance_km=150.0,
        duration_min=190,
        stops=2,
        color_offset=-0.01,
        strategy="balanced"
    )
    
    return [plan_a, plan_b, plan_c]

def _create_dummy_route(id, name, origin, destination, distance_km, duration_min, stops, color_offset, strategy):
    # Generate simple polyline
    polyline = []
    points = 20
    for i in range(points + 1):
        t = i / points
        lat = origin.latitude + (destination.latitude - origin.latitude) * t + (color_offset if i % 2 == 0 else -color_offset)
        lng = origin.longitude + (destination.longitude - origin.longitude) * t + (color_offset if i % 2 != 0 else -color_offset)
        polyline.append({"latitude": lat, "longitude": lng})
        
    route_stops = []
    # Origin
    route_stops.append({
        "name": "Start",
        "location": {"latitude": origin.latitude, "longitude": origin.longitude},
        "type": "origin",
        "arrivalTime": datetime.now().isoformat(),
        "arrivalSoc": 80, # Assuming start with request.current_soc in real app
        "departureSoc": 80
    })
    
    # Dummy stops
    for i in range(1, stops + 1):
        t = i / (stops + 1)
        lat = origin.latitude + (destination.latitude - origin.latitude) * t
        lng = origin.longitude + (destination.longitude - origin.longitude) * t
        
        charge_duration = 45 if strategy == "long_stops" else (15 if strategy == "short_stops" else 30)
        cost = 500 if strategy == "long_stops" else (150 if strategy == "short_stops" else 300)
        
        route_stops.append({
            "name": f"Charging Station {i}",
            "location": {"latitude": lat, "longitude": lng},
            "type": "charging",
            "arrivalTime": (datetime.now() + timedelta(minutes=int(duration_min * t))).isoformat(),
            "chargeDurationMin": charge_duration,
            "targetSoc": 80,
            "arrivalSoc": 20,
            "departureSoc": 80,
            "cost": cost
        })
        
    # Destination
    route_stops.append({
        "name": "Destination",
        "location": {"latitude": destination.latitude, "longitude": destination.longitude},
        "type": "destination",
        "arrivalTime": (datetime.now() + timedelta(minutes=duration_min)).isoformat(),
        "arrivalSoc": 30,
        "departureSoc": 30
    })

    return {
        "id": id,
        "name": name,
        "polyline": polyline,
        "totalDistanceKm": distance_km,
        "totalDurationMin": duration_min,
        "stops": route_stops,
        "estimatedCost": stops * (500 if strategy == "long_stops" else (150 if strategy == "short_stops" else 300))
    }
