import logging
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, HttpUrl
from typing import Any, Dict, Optional, List
from datetime import datetime
from uuid import UUID
from supabase_client import supabase
from auth_utils import ensure_admin_user, get_authenticated_user

router = APIRouter()
logger = logging.getLogger(__name__)


class NewsCreate(BaseModel):
    title: str
    summary: Optional[str] = None
    source_url: HttpUrl
    source_name: str
    published_at: datetime
    image_url: Optional[HttpUrl] = None
    category: str  # 'policy', 'vehicles', 'charging', 'industry'
    is_featured: bool = False


class NewsResponse(BaseModel):
    id: str
    title: str
    summary: Optional[str]
    source_url: str
    source_name: str
    published_at: datetime
    image_url: Optional[str]
    category: str
    is_featured: bool
    created_at: datetime
    updated_at: datetime


@router.get("/", response_model=List[NewsResponse])
async def get_news(
    limit: int = Query(20, ge=1, le=100),
    category: Optional[str] = Query(None, pattern="^(policy|vehicles|charging|industry)$"),
    featured_only: bool = False,
):
    """
    Get latest EV news articles.
    
    - **limit**: Number of articles to return (1-100)
    - **category**: Filter by category (policy, vehicles, charging, industry)
    - **featured_only**: Return only featured articles
    """
    if not supabase:
        return []

    try:
        query = supabase.table("ev_news").select("*").order("published_at", desc=True).limit(limit)
        
        if category:
            query = query.eq("category", category)
        
        if featured_only:
            query = query.eq("is_featured", True)
        
        response = query.execute()
        return response.data
    except Exception as e:
        logger.warning("Error fetching news feed: %s", e)
        return []


@router.get("/{news_id}", response_model=NewsResponse)
async def get_news_by_id(news_id: str):
    """Get a specific news article by ID."""
    try:
        UUID(news_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="News article not found")

    try:
        response = supabase.table("ev_news").select("*").eq("id", news_id).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="News article not found")
        
        return response.data[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching news: {str(e)}")


@router.post("/", response_model=NewsResponse)
async def create_news(
    news: NewsCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """
    Create a new news article.
    
    This endpoint is intended for the AI news fetching batch job.
    """
    try:
        ensure_admin_user(auth_user)
        data = news.dict()
        data['published_at'] = news.published_at.isoformat()
        
        response = supabase.table("ev_news").insert(data).execute()
        return response.data[0]
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Error creating news")
        raise HTTPException(status_code=500, detail="Error creating news") from e


@router.put("/{news_id}", response_model=NewsResponse)
async def update_news(
    news_id: str,
    news: NewsCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Update an existing news article."""
    try:
        ensure_admin_user(auth_user)
        data = news.dict()
        data['published_at'] = news.published_at.isoformat()
        
        response = supabase.table("ev_news").update(data).eq("id", news_id).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="News article not found")
        
        return response.data[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating news: {str(e)}")


@router.delete("/{news_id}")
async def delete_news(
    news_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Delete a news article."""
    try:
        ensure_admin_user(auth_user)
        response = supabase.table("ev_news").delete().eq("id", news_id).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="News article not found")
        
        return {"message": "News article deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting news: {str(e)}")
