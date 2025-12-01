from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from supabase import create_client, Client
import os

router = APIRouter()

# Supabase Setup
url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

class BlockRequest(BaseModel):
    blocker_id: str
    blocked_id: str

class ReportRequest(BaseModel):
    reporter_id: str
    reported_user_id: str
    reason: str
    details: Optional[str] = None

class UpdateProfileRequest(BaseModel):
    user_id: str
    preferences: Dict[str, Any]

@router.post("/block")
async def block_user(request: BlockRequest):
    try:
        data = request.dict()
        supabase.table("user_blocks").insert(data).execute()
        return {"status": "success", "message": "User blocked"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/report")
async def report_user(request: ReportRequest):
    try:
        data = request.dict()
        supabase.table("user_reports").insert(data).execute()
        return {"status": "success", "message": "User reported"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/profile")
async def update_profile(request: UpdateProfileRequest):
    try:
        supabase.table("profiles").update({"preferences": request.preferences}).eq("id", request.user_id).execute()
        return {"status": "success", "message": "Profile updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
