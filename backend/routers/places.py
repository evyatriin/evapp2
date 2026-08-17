import asyncio

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
import httpx
from slowapi import Limiter
from slowapi.util import get_remote_address
from config import settings
from metrics_tracker import track_external_api
from auth_utils import require_auth

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)

class Location(BaseModel):
    latitude: float
    longitude: float

class PlacesRequest(BaseModel):
    center: Location
    radius_km: float


class FoodNearbyRequest(PlacesRequest):
    max_results: int = 5


def _require_google_maps_api_key() -> str:
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=500, detail="Google Maps API Key not configured")
    return settings.GOOGLE_MAPS_API_KEY

@router.post("/nearby")
@limiter.limit("60/minute")
async def get_nearby_places(
    request: Request,
    body: PlacesRequest,
    _auth=Depends(require_auth),
):
    api_key = _require_google_maps_api_key()

    url = "https://places.googleapis.com/v1/places:searchNearby"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.location,places.evChargeOptions,"
            "places.formattedAddress,places.rating,places.userRatingCount,"
            "places.nationalPhoneNumber"
        ),
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


@router.post("/food-nearby")
@limiter.limit("60/minute")
async def get_nearby_food_places(
    request: Request,
    body: FoodNearbyRequest,
    _auth=Depends(require_auth),
):
    api_key = _require_google_maps_api_key()

    url = "https://places.googleapis.com/v1/places:searchNearby"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.location,places.formattedAddress,"
            "places.rating,places.userRatingCount"
        ),
    }

    payload = {
        "includedTypes": ["restaurant", "cafe", "meal_takeaway"],
        "maxResultCount": min(max(body.max_results, 1), 5),
        "rankPreference": "POPULARITY",
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": body.center.latitude,
                    "longitude": body.center.longitude,
                },
                "radius": min(body.radius_km, 10) * 1000,
            }
        },
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            data = response.json()

            places = data.get("places", [])
            phone_numbers = await asyncio.gather(
                *[
                    _fetch_place_phone_number(
                        client=client,
                        api_key=api_key,
                        place_id=place.get("id"),
                    )
                    for place in places
                ]
            )

            normalized_places = []
            for place, phone_number in zip(places, phone_numbers):
                location = place.get("location") or {}
                normalized_places.append(
                    {
                        "id": place.get("id"),
                        "name": place.get("displayName", {}).get("text", "Food stop"),
                        "address": place.get("formattedAddress"),
                        "rating": place.get("rating"),
                        "user_rating_count": place.get("userRatingCount"),
                        "phone_number": phone_number,
                        "location": {
                            "latitude": location.get("latitude"),
                            "longitude": location.get("longitude"),
                        },
                    }
                )

            track_external_api("google_places_food_nearby", success=True)
            return {"places": normalized_places}
        except httpx.HTTPError as e:
            track_external_api("google_places_food_nearby", success=False)
            raise HTTPException(status_code=500, detail=str(e))


async def _fetch_place_phone_number(
    *,
    client: httpx.AsyncClient,
    api_key: str,
    place_id: str | None,
) -> str | None:
    if not place_id:
        return None

    url = f"https://places.googleapis.com/v1/places/{place_id}"
    headers = {
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "nationalPhoneNumber",
    }

    try:
        response = await client.get(url, headers=headers)
        response.raise_for_status()
        place = response.json()
        return place.get("nationalPhoneNumber")
    except httpx.HTTPError:
        return None

@router.get("/autocomplete")
@limiter.limit("60/minute")
async def autocomplete(
    request: Request,
    input: str,
    _auth=Depends(require_auth),
):
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
async def place_details(
    request: Request,
    place_id: str,
    _auth=Depends(require_auth),
):
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
