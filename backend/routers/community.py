from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from supabase import Client
from supabase_client import supabase
import os

router = APIRouter()

# Supabase Setup
# Supabase Setup - using centralized client

# --- Models ---
class MicroCommunity(BaseModel):
    id: str
    name: str
    description: Optional[str]
    image_url: Optional[str]
    members_count: int = 0

class CommunityPost(BaseModel):
    id: str
    user_id: str
    community_id: Optional[str]
    title: Optional[str]
    content: str
    image_url: Optional[str]
    likes_count: int = 0
    comments_count: int = 0
    is_alert: bool = False
    is_official: bool = False
    created_at: datetime
    # Extra fields for UI
    user_name: Optional[str] = None
    user_avatar: Optional[str] = None

class CreatePostRequest(BaseModel):
    user_id: str
    community_id: Optional[str] = None
    title: Optional[str] = None
    content: str
    image_url: Optional[str] = None
    is_alert: bool = False

# --- Endpoints ---

@router.get("/groups", response_model=List[MicroCommunity])
async def get_micro_communities():
    try:
        response = supabase.table("micro_communities").select("*").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/feed", response_model=List[CommunityPost])
async def get_feed(community_id: Optional[str] = None, limit: int = 10, offset: int = 0):
    try:
        query = supabase.table("community_posts").select("*, profiles(full_name, avatar_url)").eq("is_hidden", False).order("created_at", desc=True)
        
        if community_id:
            query = query.eq("community_id", community_id)
            
        # Add pagination
        query = query.range(offset, offset + limit - 1)
            
        response = query.execute()
        
        posts = []
        for item in response.data:
            profile = item.get("profiles", {}) or {}
            post = CommunityPost(
                **item,
                user_name=profile.get("full_name", "Unknown User"),
                user_avatar=profile.get("avatar_url")
            )
            posts.append(post)
            
        return posts
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/posts", response_model=CommunityPost)
async def create_post(request: CreatePostRequest):
    try:
        data = request.dict()
        response = supabase.table("community_posts").insert(data).execute()
        return response.data[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/posts/{post_id}/like")
async def like_post(post_id: str, user_id: str):
    try:
        # Check if already liked
        existing = supabase.table("post_likes").select("*").eq("post_id", post_id).eq("user_id", user_id).execute()
        
        if existing.data:
            # Unlike
            supabase.table("post_likes").delete().eq("post_id", post_id).eq("user_id", user_id).execute()
            return {"status": "unliked"}
        else:
            # Like
            supabase.table("post_likes").insert({"post_id": post_id, "user_id": user_id}).execute()
            return {"status": "liked"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
