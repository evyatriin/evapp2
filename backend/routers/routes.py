import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from datetime import datetime
from supabase_client import supabase
from auth_utils import get_authenticated_user, ensure_same_user

router = APIRouter()
logger = logging.getLogger(__name__)

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


def _require_supabase():
    if not supabase:
        raise HTTPException(
            status_code=503,
            detail="Saved routes are temporarily unavailable because the database is not configured.",
        )


def _normalize_saved_route(row: Dict[str, Any]) -> Dict[str, Any]:
    normalized = dict(row)
    normalized.setdefault("charging_stops", 0)
    normalized.setdefault("is_favorite", False)
    return normalized


@router.get("/", response_model=List[SavedRoute])
async def get_saved_routes(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Get all saved routes for a user"""
    ensure_same_user(auth_user, user_id)
    _require_supabase()
    
    try:
        response = supabase.table("saved_routes").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        return [_normalize_saved_route(item) for item in response.data]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load saved routes: {e}")

@router.post("/", response_model=SavedRoute)
async def save_route(
    route: SavedRouteCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Save a new route"""
    ensure_same_user(auth_user, route.user_id)
    _require_supabase()
    
    try:
        data = route.dict()
        if not data.get("created_at"):
            data["created_at"] = datetime.now().isoformat()
            
        response = None
        missing_route_columns = ("charging_stops", "is_favorite")
        for _ in range(len(missing_route_columns) + 1):
            try:
                response = supabase.table("saved_routes").insert(data).execute()
                break
            except Exception as exc:
                message = str(exc)
                removed = False
                for column in missing_route_columns:
                    if f"Could not find the '{column}' column" in message:
                        data.pop(column, None)
                        removed = True
                        break
                if not removed:
                    raise
        
        if response.data:
            # Award points for planning/saving a route
            try:
                from utils.gamification_utils import award_points_internal
                await award_points_internal(route.user_id, 5, 'route')
            except Exception as e:
                logger.warning("Error awarding points for route save: %s", e)

            return _normalize_saved_route(response.data[0])
        else:
            raise HTTPException(status_code=500, detail="Failed to save route")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save route: {e}")

@router.delete("/{route_id}")
async def delete_route(
    route_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Delete a saved route"""
    _require_supabase()
    
    try:
        route_response = supabase.table("saved_routes").select("user_id").eq("id", route_id).maybe_single().execute()
        route = route_response.data if route_response else None
        if not route:
            raise HTTPException(status_code=404, detail="Route not found")
        ensure_same_user(auth_user, route["user_id"])
        supabase.table("saved_routes").delete().eq("id", route_id).execute()
        return {"message": "Route deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete route: {e}")

@router.post("/{route_id}/favorite")
async def toggle_favorite(
    route_id: str,
    update: FavoriteUpdate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Toggle favorite status"""
    _require_supabase()
    
    try:
        route_response = supabase.table("saved_routes").select("user_id").eq("id", route_id).maybe_single().execute()
        route = route_response.data if route_response else None
        if not route:
            raise HTTPException(status_code=404, detail="Route not found")
        ensure_same_user(auth_user, route["user_id"])
        try:
            supabase.table("saved_routes").update(
                {"is_favorite": update.is_favorite}
            ).eq("id", route_id).execute()
        except Exception as exc:
            if "Could not find the 'is_favorite' column" not in str(exc):
                raise
            logger.warning(
                "saved_routes.is_favorite is missing; favorite state was not persisted"
            )
        return {"message": "Favorite updated"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update favorite: {e}")
