from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from supabase import Client
from supabase_client import supabase
import os
import uuid

router = APIRouter()

# Supabase Setup
# Supabase Setup - using centralized client

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

class CheckIn(BaseModel):
    id: Optional[str] = None
    user_id: str
    station_id: Optional[str]
    status: str # "Working", "Busy", "Broken"
    rating: Optional[int]
    comment: Optional[str]
    image_url: Optional[str]
    created_at: datetime = datetime.now()

class CreateCheckInRequest(BaseModel):
    user_id: str
    station_id: Optional[str]
    status: str
    rating: Optional[int]
    comment: Optional[str]
    image_url: Optional[str]
    # New charging detail fields
    battery_start_percent: Optional[int] = None
    battery_end_percent: Optional[int] = None
    time_taken_minutes: Optional[int] = None
    cost_paid: Optional[float] = None
    charging_slip_url: Optional[str] = None
    points_earned: Optional[int] = 10  # Default to 10 for backward compatibility

# --- Endpoints ---

@router.get("/", response_model=List[ChargingStation])
async def get_stations(lat: Optional[float] = None, lng: Optional[float] = None, radius: float = 5.0):
    """
    Get charging stations.
    If lat/lng are provided, returns stations within 'radius' km.
    Otherwise returns all verified public stations (limited to 100).
    """
    try:
        if lat is not None and lng is not None:
            # Use database-level geospatial filtering via RPC
            # Note: This requires the 'nearby_stations' function to be created in Supabase
            try:
                response = supabase.rpc("nearby_stations", {
                    "lat": lat, 
                    "long": lng, 
                    "radius_km": radius
                }).execute()
                return response.data
            except Exception as rpc_error:
                print(f"RPC Error (falling back to python filtering): {rpc_error}")
                # Fallback to fetching all and filtering (legacy behavior) if RPC fails
                query = supabase.table("charging_stations").select("*").eq("verification_status", "verified").eq("is_private", False)
                response = query.execute()
                stations = response.data
                
                # ... (Keep existing fallback logic if needed, or just return empty/error)
                # For now, let's keep the fallback logic but optimized
                return _filter_stations_python(stations, lat, lng, radius)

        # Default fetch if no location provided
        query = supabase.table("charging_stations").select("*").eq("verification_status", "verified").eq("is_private", False).limit(50)
        response = query.execute()
        return response.data
        
    except Exception as e:
        print(f"Error fetching stations: {e}")
        return []

def _filter_stations_python(stations, lat, lng, radius):
    from math import radians, cos, sin, asin, sqrt
    
    filtered = []
    for station in stations:
        # Haversine formula
        lon1, lat1, lon2, lat2 = map(radians, [lng, lat, station['longitude'], station['latitude']])
        dlon = lon2 - lon1 
        dlat = lat2 - lat1 
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a)) 
        r = 6371 
        dist = c * r
        
        if dist <= radius:
            station['distance'] = dist
            filtered.append(station)
            
    return filtered

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

@router.get("/checkins/{user_id}", response_model=List[CheckIn])
async def get_my_checkins(user_id: str):
    try:
        response = supabase.table("station_checkins").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        return response.data
    except Exception as e:
        # If table doesn't exist, return empty
        print(f"Error fetching checkins: {e}")
        return []

@router.get("/checkin/station/{station_id}/latest")
async def get_latest_station_checkin(station_id: str):
    """Get the latest check-in for a specific station"""
    try:
        response = supabase.table("station_checkins").select("*").eq("station_id", station_id).order("created_at", desc=True).limit(1).execute()
        if response.data and len(response.data) > 0:
            return response.data[0]
        return None
    except Exception as e:
        print(f"Error fetching latest checkin: {e}")
        return None

@router.post("/checkin", response_model=CheckIn)
async def create_checkin(checkin: CreateCheckInRequest):
    try:
        data = checkin.dict()
        data['created_at'] = datetime.now().isoformat()
        
        # Insert checkin
        response = supabase.table("station_checkins").insert(data).execute()
        
        # Reward points logic - use points from request (default 10)
        points_to_award = checkin.points_earned or 10
        try:
            from utils.gamification_utils import award_points_internal
            await award_points_internal(checkin.user_id, points_to_award, 'check_in')
        except Exception as e:
            print(f"Error updating points: {e}")

        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/upload-checkin-image")
async def upload_checkin_image(file: UploadFile = File(...)):
    """Upload an image for a check-in to Supabase Storage"""
    try:
        # Validate file type
        allowed_types = ["image/jpeg", "image/jpg", "image/png", "image/webp"]
        if file.content_type not in allowed_types:
            raise HTTPException(status_code=400, detail="Invalid file type. Only JPEG, PNG, and WebP are allowed.")
        
        # Generate unique filename
        file_ext = file.filename.split(".")[-1]
        unique_filename = f"checkin_{uuid.uuid4()}.{file_ext}"
        
        # Read file content
        file_content = await file.read()
        
        # Upload to Supabase Storage
        # Bucket name: 'checkin-images' (must be created in Supabase)
        storage_response = supabase.storage.from_("checkin-images").upload(
            unique_filename,
            file_content,
            {"content-type": file.content_type}
        )
        
        # Get public URL
        public_url = supabase.storage.from_("checkin-images").get_public_url(unique_filename)
        
        return {"image_url": public_url}
    except Exception as e:
        print(f"Error uploading image: {e}")
        raise HTTPException(status_code=500, detail=f"Error uploading image: {str(e)}")

# --- Saved Chargers Endpoints ---

class SaveChargerRequest(BaseModel):
    user_id: str
    station_id: str

@router.post("/save")
def save_charger(request: SaveChargerRequest):
    """Save/favorite a charging station"""
    try:
        result = supabase.table("saved_chargers").insert({
            "user_id": request.user_id,
            "station_id": request.station_id
        }).execute()
        return {"message": "Charger saved successfully", "data": result.data}
    except Exception as e:
        # Handle duplicate entries gracefully
        if "duplicate" in str(e).lower() or "unique" in str(e).lower():
            return {"message": "Charger already saved"}
        print(f"Error saving charger: {e}")
        raise HTTPException(status_code=500, detail=f"Error saving charger: {str(e)}")

@router.delete("/save/{user_id}/{station_id}")
def unsave_charger(user_id: str, station_id: str):
    """Unsave/unfavorite a charging station"""
    try:
        result = supabase.table("saved_chargers").delete().eq("user_id", user_id).eq("station_id", station_id).execute()
        return {"message": "Charger unsaved successfully"}
    except Exception as e:
        print(f"Error unsaving charger: {e}")
        raise HTTPException(status_code=500, detail=f"Error unsaving charger: {str(e)}")

@router.get("/saved/{user_id}")
def get_saved_chargers(user_id: str):
    """Get all saved chargers for a user with station details"""
    try:
        # Get saved charger IDs
        saved_result = supabase.table("saved_chargers").select("station_id, created_at").eq("user_id", user_id).execute()
        
        if not saved_result.data:
            return []
        
        station_ids = [item['station_id'] for item in saved_result.data]
        
        # Get station details
        stations_result = supabase.table("charging_stations").select("*").in_("id", station_ids).execute()
        
        # Merge saved_at timestamp with station data
        saved_map = {item['station_id']: item['created_at'] for item in saved_result.data}
        for station in stations_result.data:
            station['saved_at'] = saved_map.get(station['id'])
        
        return stations_result.data
    except Exception as e:
        print(f"Error fetching saved chargers: {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching saved chargers: {str(e)}")
