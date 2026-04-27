from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from supabase_client import supabase
from auth_utils import ensure_admin_user, get_authenticated_user

router = APIRouter()

# Supabase Setup
# Supabase Setup - using centralized client

class ModerationRequest(BaseModel):
    admin_id: str
    content_type: str # 'post', 'comment', 'review'
    content_id: str
    action: str # 'hide', 'unhide'

class BanRequest(BaseModel):
    admin_id: str
    user_id: str
    reason: str

@router.get("/reports")
async def get_reports(auth_user: Dict[str, Any] = Depends(get_authenticated_user)):
    try:
        ensure_admin_user(auth_user)
        response = supabase.table("user_reports").select("*").eq("status", "Open").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/moderate/content")
async def moderate_content(
    request: ModerationRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_admin_user(auth_user)
        request.admin_id = auth_user["user_id"]
        table_map = {
            "post": "community_posts",
            "comment": "community_comments",
            "review": "station_reviews"
        }
        table = table_map.get(request.content_type)
        if not table:
            raise HTTPException(400, "Invalid content type")
            
        is_hidden = True if request.action == 'hide' else False
        
        supabase.table(table).update({"is_hidden": is_hidden}).eq("id", request.content_id).execute()
        
        # Log action
        supabase.table("admin_audit_logs").insert({
            "admin_id": request.admin_id,
            "action": f"{request.action}_{request.content_type}",
            "target_id": request.content_id
        }).execute()
        
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/ban")
async def ban_user(
    request: BanRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_admin_user(auth_user)
        request.admin_id = auth_user["user_id"]
        supabase.table("profiles").update({"is_banned": True}).eq("id", request.user_id).execute()
        
        supabase.table("admin_audit_logs").insert({
            "admin_id": request.admin_id,
            "action": "ban_user",
            "target_id": request.user_id,
            "details": {"reason": request.reason}
        }).execute()
        
        return {"status": "success", "message": "User banned"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
