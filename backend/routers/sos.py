from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from supabase import Client
from supabase_client import supabase
from auth_utils import get_authenticated_user, ensure_same_user
import os

router = APIRouter()

# Supabase Setup
# Supabase Setup - using centralized client from supabase_client.py

class SOSAlert(BaseModel):
    id: Optional[str] = None
    user_id: str
    latitude: float
    longitude: float
    message: Optional[str] = None
    car_model: Optional[str] = None
    phone_number: Optional[str] = None
    status: str = "Active"
    created_at: Optional[datetime] = None

class CreateAlertRequest(BaseModel):
    user_id: str
    latitude: float
    longitude: float
    message: Optional[str] = None
    car_model: str
    phone_number: str

@router.post("/alert", response_model=SOSAlert)
async def create_sos_alert(
    request: CreateAlertRequest,
    auth_user=Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.user_id)
        # Check if user has verified phone number
        profile = supabase.table("profiles").select("preferences").eq("id", request.user_id).execute()
        if not profile.data:
             raise HTTPException(status_code=404, detail="User profile not found")
             
        prefs = profile.data[0].get("preferences", {})
        if not prefs.get("is_phone_verified", False):
             raise HTTPException(status_code=403, detail="Phone number not verified. Please verify your phone number to send SOS alerts.")

        data = request.dict()
        response = supabase.table("sos_alerts").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/nearby", response_model=List[SOSAlert])
async def get_nearby_alerts(lat: float, long: float, radius_km: float = 15.0):
    try:
        # Ideally use a PostGIS RPC function here. 
        # For MVP without custom RPC, we can filter by bounding box or fetch active and filter in code.
        # Fetching all ACTIVE alerts is reasonable if volume is low.
        
        response = supabase.table("sos_alerts").select("*").eq("status", "Active").execute()
        
        # Simple client-side distance filter for MVP
        # In production, use: supabase.rpc('nearby_alerts', {lat, long, radius})
        nearby = []
        for alert in response.data:
            # Haversine approximation or simple Euclidean for small distances
            if abs(alert['latitude'] - lat) < 0.2 and abs(alert['longitude'] - long) < 0.2:
                nearby.append(alert)
                
        return nearby
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
