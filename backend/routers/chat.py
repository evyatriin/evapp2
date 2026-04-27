from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from datetime import datetime
from supabase_client import supabase
from auth_utils import ensure_same_user, get_authenticated_user

router = APIRouter()

# Supabase Setup
# Supabase Setup - using centralized client

class DirectMessage(BaseModel):
    id: Optional[str] = None
    sender_id: str
    receiver_id: str
    content: str
    is_read: bool = False
    created_at: Optional[datetime] = None

class SendMessageRequest(BaseModel):
    sender_id: str
    receiver_id: str
    content: str

@router.get("/messages/{user_id}/{other_user_id}", response_model=List[DirectMessage])
async def get_conversation(
    user_id: str,
    other_user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, user_id)
        response = supabase.table("direct_messages").select("*").or_(
            f"and(sender_id.eq.{user_id},receiver_id.eq.{other_user_id}),"
            f"and(sender_id.eq.{other_user_id},receiver_id.eq.{user_id})"
        ).order("created_at", desc=False).execute()
        
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/send", response_model=DirectMessage)
async def send_message(
    request: SendMessageRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_same_user(auth_user, request.sender_id)
        # Check for blocks (handled by RLS, but good to have explicit check or handle error)
        # We rely on RLS policy "User send message" which checks user_blocks
        
        data = {
            "sender_id": request.sender_id,
            "receiver_id": request.receiver_id,
            "content": request.content
        }
        
        response = supabase.table("direct_messages").insert(data).execute()
        
        if not response.data:
            raise HTTPException(status_code=403, detail="Message could not be sent. You might be blocked.")
            
        return response.data[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
