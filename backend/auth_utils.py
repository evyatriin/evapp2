import asyncio
from typing import Any, Dict, Optional

from fastapi import Header, HTTPException

from supabase_client import supabase


async def _verify_token(token: str) -> Dict[str, Any]:
    """Verify a Supabase JWT in a thread so we don't block the event loop."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    try:
        response = await asyncio.to_thread(lambda: supabase.auth.get_user(token))
    except Exception as error:
        raise HTTPException(status_code=401, detail=f"Invalid token: {error}") from error
    if not response or not response.user:
        raise HTTPException(status_code=401, detail="Invalid token")
    return {
        "token": token,
        "user_id": response.user.id,
        "email": response.user.email,
        "email_verified": bool(getattr(response.user, "email_confirmed_at", None)),
        "metadata": response.user.user_metadata or {},
    }


async def get_authenticated_user(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    return await _verify_token(authorization.replace("Bearer ", "", 1).strip())


async def require_auth(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    """Same as get_authenticated_user — explicit alias used on public-facing endpoints
    to make the security intent clear at the call site."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    return await _verify_token(authorization.replace("Bearer ", "", 1).strip())


def ensure_same_user(auth_user: Dict[str, Any], user_id: str) -> None:
    if auth_user["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="You are not allowed to act on behalf of another user")


def is_phone_verified(user_id: str) -> bool:
    """Read the phone-verification flag from the user's profile preferences."""
    try:
        profile_response = (
            supabase.table("profiles")
            .select("preferences")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile = profile_response.data if profile_response else None
    except Exception as error:
        raise HTTPException(
            status_code=500, detail=f"Could not verify your account: {error}"
        ) from error
    preferences = (profile or {}).get("preferences") or {}
    return bool(preferences.get("is_phone_verified", False))


def require_double_verified(auth_user: Dict[str, Any]) -> None:
    """Gate community help features (SOS, community charging) behind BOTH a
    confirmed email and a verified phone number. Raises 403 otherwise.

    Distinct messages let the client show which step is missing; the app also
    surfaces its own verification sheet before the request is even sent.
    """
    if not auth_user.get("email_verified"):
        raise HTTPException(
            status_code=403,
            detail="Please verify your email address to use community help features.",
        )
    if not is_phone_verified(auth_user["user_id"]):
        raise HTTPException(
            status_code=403,
            detail="Please verify your phone number to use community help features.",
        )


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
