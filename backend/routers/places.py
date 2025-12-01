from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import httpx
from config import settings

router = APIRouter()

class Location(BaseModel):
    latitude: float
    longitude: float

class PlacesRequest(BaseModel):
    center: Location
    radius_km: float

@router.post("/nearby")
async def get_nearby_places(request: PlacesRequest):
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=500, detail="Google Maps API Key not configured")

    url = "https://places.googleapis.com/v1/places:searchNearby"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.evChargeOptions,places.formattedAddress,places.rating,places.userRatingCount",
    }
    
    body = {
        "includedTypes": ["electric_vehicle_charging_station"],
        "maxResultCount": 20,
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": request.center.latitude,
                    "longitude": request.center.longitude,
                },
                "radius": request.radius_km * 1000,
            }
        }
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(url, headers=headers, json=body)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/autocomplete")
async def autocomplete(input: str):
    if not settings.GOOGLE_MAPS_API_KEY:
        # Return mock data if no key
        return {
            "predictions": [
                {"description": "Hyderabad, Telangana", "place_id": "ChIJx9L8AAq3yzsR_r_yq2k9j90"},
                {"description": "Warangal, Telangana", "place_id": "ChIJ_w7s1_m3yzsR_r_yq2k9j90"},
                {"description": "Vijayawada, Andhra Pradesh", "place_id": "ChIJ_w7s1_m3yzsR_r_yq2k9j90"},
                {"description": "Visakhapatnam, Andhra Pradesh", "place_id": "ChIJ_w7s1_m3yzsR_r_yq2k9j90"},
            ]
        }

    url = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    params = {
        "input": input,
        "key": settings.GOOGLE_MAPS_API_KEY,
        "components": "country:in", # Restrict to India for this app
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/details")
async def place_details(place_id: str):
    if not settings.GOOGLE_MAPS_API_KEY:
        # Return mock data if no key
        # Mock coordinates for the mock places in autocomplete
        mock_coords = {
            "ChIJx9L8AAq3yzsR_r_yq2k9j90": {"lat": 17.3850, "lng": 78.4867}, # Hyderabad
            "ChIJ_w7s1_m3yzsR_r_yq2k9j90": {"lat": 17.9689, "lng": 79.5941}, # Warangal
        }
        coords = mock_coords.get(place_id, {"lat": 17.3850, "lng": 78.4867})
        return {
            "result": {
                "geometry": {
                    "location": coords
                }
            }
        }

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
            return response.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=500, detail=str(e))
