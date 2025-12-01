from fastapi import APIRouter, HTTPException, Depends
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

# --- Models ---
class ChargingStation(BaseModel):
    id: Optional[str] = None
    name: str
    address: Optional[str]
    latitude: float
    longitude: float
    provider: Optional[str]
    connector_types: List[str] = []
    power_kw: Optional[float]
    status: str = "Operational"
    availability_status: str = "Unknown"
    price_per_kwh: Optional[float]
    amenities: List[str] = []
    is_24_7: bool = False
    image_urls: List[str] = []
    
    # Private / Crowdsourced
    is_private: bool = False
    owner_id: Optional[str] = None
    access_type: str = "Public"
    access_instructions: Optional[str] = None
    submitted_by: Optional[str] = None
    verification_status: str = "pending"
    
    # Aggregates
    average_rating: float = 0.0
    total_reviews: int = 0
    total_checkins: int = 0

class ChargingSession(BaseModel):
    id: Optional[str] = None
    user_id: str
    station_id: Optional[str]
    start_time: datetime
    end_time: Optional[datetime]
    kwh_added: Optional[float]
    cost: Optional[float]

class CreateStationRequest(BaseModel):
    name: str
    latitude: float
    longitude: float
    provider: Optional[str] = "Unknown"
    is_private: bool = False
    owner_id: str # User ID submitting
    access_instructions: Optional[str] = None

class CreateSessionRequest(BaseModel):
    user_id: str
    station_id: Optional[str]
    start_time: datetime
    kwh_added: float
    cost: float

# --- Endpoints ---

@router.get("/", response_model=List[ChargingStation])
async def get_stations(lat: Optional[float] = None, lng: Optional[float] = None, user_id: Optional[str] = None):
    try:
        # Fetch verified public stations OR private stations owned by user
        # This logic is complex for simple REST, ideally handled by RLS if we pass auth token.
        # Since we are using service role key in backend (usually), we simulate RLS logic here or just fetch all and filter.
        # BUT, for this MVP, let's assume we fetch all "visible" stations.
        
        query = supabase.table("charging_stations").select("*")
        
        # If we have a user_id, we can try to filter for their private ones too.
        # For now, let's just get all verified public ones + any private ones if we implement that logic.
        # Simplified: Get all Verified Public stations.
        
        query = query.eq("verification_status", "verified").eq("is_private", False)
        
        response = query.execute()
        return response.data
    except Exception as e:
        # Fallback to empty list or error
        print(f"Error fetching stations: {e}")
        return []

@router.get("/my-stations/{user_id}", response_model=List[ChargingStation])
async def get_my_stations(user_id: str):
    try:
        response = supabase.table("charging_stations").select("*").eq("owner_id", user_id).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/", response_model=ChargingStation)
async def create_station(station: CreateStationRequest):
    try:
        data = station.dict()
        data["submitted_by"] = station.owner_id
        # If private, auto-verify? Or keep pending? Let's say private are auto-verified for owner.
        if station.is_private:
            data["verification_status"] = "verified" 
        
        response = supabase.table("charging_stations").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/history/{user_id}", response_model=List[ChargingSession])
async def get_charging_history(user_id: str):
    try:
        response = supabase.table("charging_sessions").select("*").eq("user_id", user_id).order("start_time", desc=True).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/session", response_model=ChargingSession)
async def log_session(session: CreateSessionRequest):
    try:
        data = session.dict()
        response = supabase.table("charging_sessions").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
