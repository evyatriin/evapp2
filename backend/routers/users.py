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
