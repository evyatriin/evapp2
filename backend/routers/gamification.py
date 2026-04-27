import logging

from fastapi import APIRouter, HTTPException, Depends, Query
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, date
from supabase_client import get_supabase

router = APIRouter(prefix="/gamification", tags=["Gamification"])
supabase = get_supabase()
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

class AwardPointsRequest(BaseModel):
    user_id: str
    points: int
    action_type: str # 'check_in', 'route', 'referral', etc.

class UpdateStreakRequest(BaseModel):
    user_id: str

# --- Endpoints ---

@router.get("/stats/{user_id}", response_model=UserStats)
async def get_user_stats(user_id: str):
    """Get gamification stats for a specific user."""
    try:
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
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching user stats: {str(e)}")

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

from utils.gamification_utils import award_points_internal

@router.post("/points/award")
async def award_points(request: AwardPointsRequest):
    """
    Award points to a user. 
    This should be called internally by other services or secured endpoints.
    """
    try:
        new_total = await award_points_internal(request.user_id, request.points, request.action_type)
        if new_total is None:
             raise HTTPException(status_code=500, detail="Failed to award points")
        
        return {"message": "Points awarded successfully", "new_total": new_total}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error awarding points: {str(e)}")

@router.post("/streak/update")
async def update_streak(request: UpdateStreakRequest):
    """Update user's daily streak."""
    try:
        stats_response = supabase.table("user_stats").select("*").eq("user_id", request.user_id).execute()
        
        if not stats_response.data:
            # Initialize
            supabase.table("user_stats").insert({"user_id": request.user_id, "current_streak": 1, "last_active_date": datetime.now().date().isoformat()}).execute()
            return {"message": "Streak started", "current_streak": 1}
            
        stats = stats_response.data[0]
        last_active = datetime.strptime(stats["last_active_date"], "%Y-%m-%d").date() if stats["last_active_date"] else None
        today = datetime.now().date()
        
        if last_active == today:
            return {"message": "Already active today", "current_streak": stats["current_streak"]}
            
        if last_active and (today - last_active).days == 1:
            # Consecutive day
            new_streak = stats["current_streak"] + 1
            longest = max(stats["longest_streak"], new_streak)
            supabase.table("user_stats").update({
                "current_streak": new_streak,
                "longest_streak": longest,
                "last_active_date": today.isoformat()
            }).eq("user_id", request.user_id).execute()
            
            # Check streak badge
            await _check_streak_badge(request.user_id, new_streak)
            
            return {"message": "Streak updated", "current_streak": new_streak}
        else:
            # Streak broken
            supabase.table("user_stats").update({
                "current_streak": 1,
                "last_active_date": today.isoformat()
            }).eq("user_id", request.user_id).execute()
            return {"message": "Streak reset", "current_streak": 1}
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating streak: {str(e)}")



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
