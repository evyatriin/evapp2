import logging
from urllib.parse import urlparse

from fastapi import APIRouter, HTTPException, Depends, Header
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import httpx

from config import settings
from supabase_client import supabase, service_supabase
from auth_utils import get_authenticated_user, ensure_same_user

router = APIRouter()
logger = logging.getLogger(__name__)

# Supabase Setup
# Supabase Setup - using centralized client

class BlockRequest(BaseModel):
    blocker_id: str
    blocked_id: str

class ReportRequest(BaseModel):
    reporter_id: str
    reported_user_id: str
    reason: str
    details: Optional[str] = None

class UpdateProfileRequest(BaseModel):
    user_id: str
    preferences: Optional[Dict[str, Any]] = {}
    phone_number: Optional[str] = None
    is_phone_verified: Optional[bool] = None
    vehicle_details: Optional[Dict[str, Any]] = None

def _extract_storage_target(url: Optional[str]) -> Optional[tuple[str, str]]:
    if not url:
        return None

    parsed = urlparse(url)
    path = parsed.path or ""
    for marker in ("/storage/v1/object/public/", "/storage/v1/object/sign/"):
        if marker in path:
            relative = path.split(marker, 1)[1].strip("/")
            parts = relative.split("/", 1)
            if len(parts) == 2 and parts[0] and parts[1]:
                return parts[0], parts[1]
    return None


def _delete_storage_urls(admin_client, urls: list[str]) -> None:
    bucket_to_paths: Dict[str, set[str]] = {}
    for url in urls:
        target = _extract_storage_target(url)
        if target is None:
            continue
        bucket, path = target
        bucket_to_paths.setdefault(bucket, set()).add(path)

    for bucket, paths in bucket_to_paths.items():
        if not paths:
            continue
        try:
            admin_client.storage.from_(bucket).remove(list(paths))
        except Exception as exc:
            logger.warning("Failed to delete storage objects from %s: %s", bucket, exc)


def _cleanup_user_storage(user_id: str, admin_client) -> None:
    urls: list[str] = []

    sources = [
        ("vehicles", "user_id", ["photo_url"]),
        ("station_checkins", "user_id", ["image_url", "charging_slip_url"]),
        ("community_posts", "user_id", ["image_url"]),
        ("charging_stations", "owner_id", ["charger_photos"]),
    ]

    for table_name, filter_column, columns in sources:
        try:
            response = admin_client.table(table_name).select(",".join(columns)).eq(filter_column, user_id).execute()
        except Exception as exc:
            logger.info("Skipping storage cleanup lookup for %s: %s", table_name, exc)
            continue

        for row in response.data or []:
            for column in columns:
                value = row.get(column)
                if isinstance(value, str) and value.strip():
                    urls.append(value.strip())
                elif isinstance(value, list):
                    urls.extend(str(item).strip() for item in value if str(item).strip())

    _delete_storage_urls(admin_client, urls)


def _delete_user_rows(user_id: str):
    admin_client = service_supabase or supabase
    if not admin_client:
        raise HTTPException(status_code=503, detail="Database service not configured")

    _cleanup_user_storage(user_id, admin_client)

    user_id_tables = [
        "vehicles",
        "saved_routes",
        "saved_chargers",
        "charging_sessions",
        "station_checkins",
        "trip_logs",
        "user_badges",
        "user_stats",
        "community_posts",
        "post_likes",
        "sos_alerts",
    ]

    for table_name in user_id_tables:
        admin_client.table(table_name).delete().eq("user_id", user_id).execute()

    admin_client.table("charger_requests").delete().eq("requester_user_id", user_id).execute()
    admin_client.table("charger_requests").delete().eq("host_user_id", user_id).execute()
    admin_client.table("charging_stations").delete().eq("owner_id", user_id).execute()
    admin_client.table("user_blocks").delete().eq("blocker_id", user_id).execute()
    admin_client.table("user_blocks").delete().eq("blocked_id", user_id).execute()
    admin_client.table("user_reports").delete().eq("reporter_id", user_id).execute()
    admin_client.table("user_reports").delete().eq("reported_user_id", user_id).execute()
    admin_client.table("direct_messages").delete().eq("sender_id", user_id).execute()
    admin_client.table("direct_messages").delete().eq("receiver_id", user_id).execute()
    admin_client.table("profiles").delete().eq("id", user_id).execute()

async def _delete_supabase_auth_user(user_id: str):
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(
            status_code=503,
            detail="SUPABASE_SERVICE_ROLE_KEY is required for account deletion",
        )

    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    headers = {
        "apiKey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.delete(url, headers=headers)

    if response.status_code not in (200, 204):
        raise HTTPException(
            status_code=502,
            detail=f"Failed to delete auth user: {response.text}",
        )

@router.post("/block")
async def block_user(request: BlockRequest):
    try:
        data = request.dict()
        supabase.table("user_blocks").insert(data).execute()
        return {"status": "success", "message": "User blocked"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/report")
async def report_user(request: ReportRequest):
    try:
        data = request.dict()
        supabase.table("user_reports").insert(data).execute()
        return {"status": "success", "message": "User reported"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/profile")
async def update_profile(
    request: UpdateProfileRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.user_id)
        # Fetch existing profile to merge preferences
        current = supabase.table("profiles").select("preferences").eq("id", request.user_id).execute()
        current_prefs = current.data[0].get("preferences", {}) if current.data else {}
        
        # Update preferences with new data
        if request.preferences:
            current_prefs.update(request.preferences)
        if request.phone_number:
            current_prefs["phone_number"] = request.phone_number
        if request.is_phone_verified is not None:
            current_prefs["is_phone_verified"] = request.is_phone_verified
        if request.vehicle_details:
            current_prefs["vehicle_details"] = request.vehicle_details
            
        supabase.table("profiles").update({"preferences": current_prefs}).eq("id", request.user_id).execute()
        return {"status": "success", "message": "Profile updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/profile/{user_id}")
async def get_profile(user_id: str):
    """Get full user profile including stats and badges"""
    try:
        # 1. Get basic profile
        profile_response = supabase.table("profiles").select("*").eq("id", user_id).execute()
        profile = profile_response.data[0] if profile_response.data else {}
        
        # 2. Get stats
        stats_response = supabase.table("user_stats").select("*").eq("user_id", user_id).execute()
        stats = stats_response.data[0] if stats_response.data else {
            "total_points": 0,
            "current_streak": 0,
            "total_check_ins": 0,
            "total_routes_planned": 0
        }
        
        # 3. Get badges
        badges_response = supabase.table("user_badges").select("*, badge:badges(*)").eq("user_id", user_id).execute()
        badges = badges_response.data if badges_response.data else []
        
        return {
            "profile": profile,
            "stats": stats,
            "badges": badges
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching profile: {str(e)}")

@router.get("/{user_id}/statistics")
async def get_user_statistics(user_id: str):
    """Get user trip statistics with CO2 savings calculations"""
    try:
        # 1. Get check-ins count
        checkins_response = supabase.table("station_checkins").select("id", count="exact").eq("user_id", user_id).execute()
        total_check_ins = checkins_response.count or 0
        
        # 2. Get trip logs for distance
        trips_response = supabase.table("trip_logs").select("distance_km").eq("user_id", user_id).execute()
        trips = trips_response.data or []
        total_km = sum(t.get("distance_km", 0) or 0 for t in trips)
        total_trips = len(trips)
        
        # 3. Get charging sessions for kWh
        sessions_response = supabase.table("charging_sessions").select("kwh_charged").eq("user_id", user_id).execute()
        sessions = sessions_response.data or []
        total_kwh = sum(s.get("kwh_charged", 0) or 0 for s in sessions)
        
        # 4. Calculate CO2 saved vs petrol car
        # Average petrol car: 120g CO2/km
        # Average EV in India: ~50g CO2/km (including power generation)
        # Savings: 70g/km = 0.07 kg/km
        co2_saved_kg = total_km * 0.07
        
        # 5. Calculate money saved
        # Petrol cost: ~₹8/km for average car
        # EV cost: ~₹1.5/km
        # Savings: ₹6.5/km
        money_saved = total_km * 6.5
        
        return {
            "total_km": total_km,
            "total_kwh_charged": total_kwh,
            "co2_saved_kg": co2_saved_kg,
            "money_saved": money_saved,
            "total_check_ins": total_check_ins,
            "total_trips": total_trips
        }
    except Exception as e:
        logger.exception("Error fetching statistics for user %s", user_id)
        raise HTTPException(status_code=500, detail=f"Error fetching statistics: {e}")

@router.delete("/me")
async def delete_my_account(auth_user: Dict[str, Any] = Depends(get_authenticated_user)):

    try:
        _delete_user_rows(auth_user["user_id"])
        await _delete_supabase_auth_user(auth_user["user_id"])
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Account deletion failed: {e}")

    return {
        "status": "success",
        "message": "Account deleted successfully",
        "user_id": auth_user["user_id"],
    }
