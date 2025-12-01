from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from supabase import create_client, Client
import os

router = APIRouter()

# Supabase Setup
url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

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
async def create_sos_alert(request: CreateAlertRequest):
    try:
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
