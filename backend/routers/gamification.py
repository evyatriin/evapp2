import logging

from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel
from typing import Any, Dict, List, Optional
from datetime import datetime, date
from supabase_client import supabase
from auth_utils import ensure_same_user, get_authenticated_user

router = APIRouter()
logger = logging.getLogger(__name__)

# --- Models ---

class UserStats(BaseModel):
    user_id: str
    total_points: int
    current_streak: int
    longest_streak: int
    last_active_date: Optional[date]
    total_check_ins: int
    total_routes_planned: int
    created_at: datetime
    updated_at: datetime

class Badge(BaseModel):
    id: str
    name: str
    description: str
    icon: str
    requirement_type: str
    requirement_value: int
    created_at: datetime

class UserBadge(BaseModel):
    id: str
    user_id: str
    badge_id: str
    earned_at: datetime
    badge: Optional[Badge] = None

class LeaderboardEntry(BaseModel):
    user_id: str
    name: str
    profile_image_url: Optional[str]
    total_points: int
    current_streak: int
    badge_count: int
    rank: int

# --- Endpoints ---

@router.get("/stats/{user_id}", response_model=UserStats)
async def get_user_stats(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Get gamification stats for a specific user."""
    try:
        ensure_same_user(auth_user, user_id)
        response = supabase.table("user_stats").select("*").eq("user_id", user_id).execute()
        
        if not response.data:
            # Initialize stats if not exists
            new_stats = {
                "user_id": user_id,
                "total_points": 0,
                "current_streak": 0,
                "longest_streak": 0,
                "total_check_ins": 0,
                "total_routes_planned": 0
            }
            insert_response = supabase.table("user_stats").insert(new_stats).execute()
            if insert_response.data:
                return insert_response.data[0]
            raise HTTPException(status_code=404, detail="User stats not found and could not be created")
            
        return response.data[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error fetching user stats")
        raise HTTPException(status_code=500, detail="Error fetching user stats") from e

@router.get("/leaderboard", response_model=List[LeaderboardEntry])
async def get_leaderboard():
    """Get the weekly leaderboard (top 10 users)."""
    try:
        response = supabase.table("weekly_leaderboard").select("*").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching leaderboard: {str(e)}")

@router.get("/badges", response_model=List[Badge])
async def get_badges():
    """Get all available badges."""
    try:
        response = supabase.table("badges").select("*").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching badges: {str(e)}")

@router.get("/badges/user/{user_id}", response_model=List[UserBadge])
async def get_user_badges(user_id: str):
    """Get badges earned by a specific user."""
    try:
        # Fetch user badges with badge details
        response = supabase.table("user_badges").select("*, badge:badges(*)").eq("user_id", user_id).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching user badges: {str(e)}")

async def _check_streak_badge(user_id: str, streak: int):
    """Check specifically for streak badges."""
    try:
        badges_response = supabase.table("badges").select("*").eq("requirement_type", "streak").execute()
        badges = badges_response.data
        
        earned_response = supabase.table("user_badges").select("badge_id").eq("user_id", user_id).execute()
        earned_ids = [b["badge_id"] for b in earned_response.data]
        
        for badge in badges:
            if badge["id"] in earned_ids:
                continue
                
            if streak >= badge["requirement_value"]:
                supabase.table("user_badges").insert({
                    "user_id": user_id,
                    "badge_id": badge["id"]
                }).execute()
    except Exception as e:
        logger.warning("Error checking streak badges: %s", e)
