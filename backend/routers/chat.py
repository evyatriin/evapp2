from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from supabase import create_client, Client
import os

router = APIRouter()

# Supabase Setup
url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

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
async def get_conversation(user_id: str, other_user_id: str):
    try:
        response = supabase.table("direct_messages").select("*").or_(
            f"and(sender_id.eq.{user_id},receiver_id.eq.{other_user_id}),"
            f"and(sender_id.eq.{other_user_id},receiver_id.eq.{user_id})"
        ).order("created_at", desc=False).execute()
        
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/send", response_model=DirectMessage)
async def send_message(request: SendMessageRequest):
    try:
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
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
