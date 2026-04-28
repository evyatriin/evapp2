from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
import httpx
from slowapi import Limiter
from slowapi.util import get_remote_address
from config import settings
from metrics_tracker import track_external_api

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)

class Location(BaseModel):
    latitude: float
    longitude: float

class PlacesRequest(BaseModel):
    center: Location
    radius_km: float

@router.post("/nearby")
@limiter.limit("60/minute")
async def get_nearby_places(request: Request, body: PlacesRequest):
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=500, detail="Google Maps API Key not configured")

    url = "https://places.googleapis.com/v1/places:searchNearby"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.evChargeOptions,places.formattedAddress,places.rating,places.userRatingCount",
    }

    payload = {
        "includedTypes": ["electric_vehicle_charging_station"],
        "maxResultCount": 20,
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": body.center.latitude,
                    "longitude": body.center.longitude,
                },
                "radius": body.radius_km * 1000,
            }
        }
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            track_external_api("google_places_nearby", success=True)
            return response.json()
        except httpx.HTTPError as e:
            track_external_api("google_places_nearby", success=False)
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/autocomplete")
@limiter.limit("60/minute")
async def autocomplete(request: Request, input: str):
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Google Maps Places autocomplete is not configured",
        )

    url = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    params = {
        "input": input,
        "key": settings.GOOGLE_MAPS_API_KEY,
        "components": "country:in",
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
            track_external_api("google_autocomplete", success=True)
            return response.json()
        except httpx.HTTPError as e:
            track_external_api("google_autocomplete", success=False)
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/details")
@limiter.limit("60/minute")
async def place_details(request: Request, place_id: str):
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Google Maps place details are not configured",
        )

    url = "https://maps.googleapis.com/maps/api/place/details/json"
    params = {
        "place_id": place_id,
        "fields": "geometry",
        "key": settings.GOOGLE_MAPS_API_KEY,
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
            track_external_api("google_place_details", success=True)
            return response.json()
        except httpx.HTTPError as e:
            track_external_api("google_place_details", success=False)
            raise HTTPException(status_code=500, detail=str(e))
