from typing import Any, Dict, Optional

from fastapi import Header, HTTPException

from supabase_client import supabase


async def get_authenticated_user(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")

    token = authorization.replace("Bearer ", "", 1).strip()

    try:
        response = supabase.auth.get_user(token)
    except Exception as error:
        raise HTTPException(status_code=401, detail=f"Invalid token: {error}") from error

    if not response or not response.user:
        raise HTTPException(status_code=401, detail="Invalid token")

    return {
        "token": token,
        "user_id": response.user.id,
        "email": response.user.email,
        "metadata": response.user.user_metadata or {},
    }


def ensure_same_user(auth_user: Dict[str, Any], user_id: str) -> None:
    if auth_user["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="You are not allowed to act on behalf of another user")


def ensure_admin_user(auth_user: Dict[str, Any]) -> None:
    metadata = auth_user.get("metadata", {})
    if metadata.get("role") == "admin" or metadata.get("is_admin") is True:
        return

    try:
        profile_response = supabase.table("profiles").select("role, preferences").eq("id", auth_user["user_id"]).maybe_single().execute()
        profile = profile_response.data if profile_response else None
    except Exception as error:
        raise HTTPException(status_code=500, detail=f"Failed to verify admin access: {error}") from error

    if not profile:
        raise HTTPException(status_code=403, detail="Admin access required")

    preferences = profile.get("preferences") or {}
    if profile.get("role") == "admin" or preferences.get("is_admin") is True:
        return

    raise HTTPException(status_code=403, detail="Admin access required")
