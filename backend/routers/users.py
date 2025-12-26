from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from supabase import Client
from supabase_client import supabase
import os

router = APIRouter()

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
async def update_profile(request: UpdateProfileRequest):
    try:
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
        # Return zeros on error rather than failing
        print(f"Error fetching statistics: {e}")
        return {
            "total_km": 0,
            "total_kwh_charged": 0,
            "co2_saved_kg": 0,
            "money_saved": 0,
            "total_check_ins": 0,
            "total_trips": 0
        }

