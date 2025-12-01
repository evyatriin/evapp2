from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from supabase_client import supabase

router = APIRouter()

class SavedRoute(BaseModel):
    id: Optional[str] = None
    user_id: str
    name: str
    start_location: Dict[str, Any]
    end_location: Dict[str, Any]
    vehicle_id: Optional[str] = None
    route_data: Dict[str, Any]
    distance_km: float
    duration_min: int
    charging_stops: int
    is_favorite: bool = False
    created_at: Optional[datetime] = None

class SavedRouteCreate(BaseModel):
    user_id: str
    name: str
    start_location: Dict[str, Any]
    end_location: Dict[str, Any]
    vehicle_id: Optional[str] = None
    route_data: Dict[str, Any]
    distance_km: float
    duration_min: int
    charging_stops: int
    is_favorite: bool = False
    created_at: Optional[str] = None # Allow string for simplicity

class FavoriteUpdate(BaseModel):
    is_favorite: bool

@router.get("/", response_model=List[SavedRoute])
async def get_saved_routes(user_id: str):
    """Get all saved routes for a user"""
    if not supabase:
        return _get_mock_routes(user_id)
    
    try:
        response = supabase.table("saved_routes").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        return response.data
    except Exception as e:
        print(f"Supabase error: {e}")
        return _get_mock_routes(user_id)

@router.post("/", response_model=SavedRoute)
async def save_route(route: SavedRouteCreate):
    """Save a new route"""
    if not supabase:
        return _create_mock_route(route)
    
    try:
        data = route.dict()
        if not data.get("created_at"):
            data["created_at"] = datetime.now().isoformat()
            
        response = supabase.table("saved_routes").insert(data).execute()
        
        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=500, detail="Failed to save route")
    except Exception as e:
        print(f"Supabase error: {e}")
        return _create_mock_route(route)

@router.delete("/{route_id}")
async def delete_route(route_id: str):
    """Delete a saved route"""
    if not supabase:
        return {"message": "Route deleted successfully (mock)"}
    
    try:
        response = supabase.table("saved_routes").delete().eq("id", route_id).execute()
        return {"message": "Route deleted successfully"}
    except Exception as e:
        print(f"Supabase error: {e}")
        return {"message": "Route deleted successfully (mock)"}

# Support for GET delete for compatibility if needed, but DELETE is preferred
@router.get("/{route_id}/delete")
async def delete_route_get(route_id: str):
    return await delete_route(route_id)

@router.post("/{route_id}/favorite")
async def toggle_favorite(route_id: str, update: FavoriteUpdate):
    """Toggle favorite status"""
    if not supabase:
        return {"message": "Favorite updated (mock)"}
    
    try:
        response = supabase.table("saved_routes").update({"is_favorite": update.is_favorite}).eq("id", route_id).execute()
        return {"message": "Favorite updated"}
    except Exception as e:
        print(f"Supabase error: {e}")
        return {"message": "Favorite updated (mock)"}

# Mock data
def _get_mock_routes(user_id: str):
    return [
        {
            "id": "1",
            "user_id": user_id,
            "name": "Home to Office",
            "start_location": {"lat": 17.385, "lng": 78.486, "address": "Hyderabad"},
            "end_location": {"lat": 12.971, "lng": 77.594, "address": "Bangalore"},
            "vehicle_id": "1",
            "route_data": {}, # Simplified for mock
            "distance_km": 570.0,
            "duration_min": 600,
            "charging_stops": 2,
            "is_favorite": True,
            "created_at": datetime.now().isoformat()
        }
    ]

def _create_mock_route(route: SavedRouteCreate):
    import uuid
    data = route.dict()
    data["id"] = str(uuid.uuid4())
    if not data.get("created_at"):
        data["created_at"] = datetime.now().isoformat()
    return data
