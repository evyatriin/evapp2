from datetime import datetime, timezone
import os

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, EmailStr
from typing import Any, Dict, Optional
from supabase_client import public_supabase, service_supabase
from metrics_tracker import track_user_event
from auth_utils import get_authenticated_user
from config import settings
from slowapi import Limiter
from slowapi.util import get_remote_address
import logging

logger = logging.getLogger(__name__)

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)

class SignUpRequest(BaseModel):
    email: EmailStr
    password: str
    name: str
    terms_accepted: bool

class SignInRequest(BaseModel):
    email: EmailStr
    password: str

class AuthResponse(BaseModel):
    user: dict
    session: dict

class ChangePasswordRequest(BaseModel):
    new_password: str

class ResetPasswordRequest(BaseModel):
    email: EmailStr

@router.post("/signup", response_model=AuthResponse)
@limiter.limit("3/minute")  # SECURITY FIX: Prevent signup spam
async def signup(request: Request, signup_req: SignUpRequest):
    """Register a new user"""
    if not signup_req.terms_accepted:
        raise HTTPException(
            status_code=400,
            detail="You must accept the Terms of Service and Privacy Policy.",
        )
    if not public_supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    try:
        # Sign up user with Supabase Auth
        response = public_supabase.auth.sign_up({
            "email": signup_req.email,
            "password": signup_req.password,
            "options": {
                "data": {
                    "name": signup_req.name,
                    "terms_accepted_at": datetime.now(timezone.utc).isoformat(),
                    "terms_version": "2026-06-12",
                }
            }
        })

        if response.user:
            track_user_event("signup")
            return {
                "user": {
                    "id": response.user.id,
                    "email": response.user.email,
                    "name": signup_req.name,
                },
                "session": {
                    "access_token": response.session.access_token if response.session else None,
                    "refresh_token": response.session.refresh_token if response.session else None,
                }
            }
        else:
            raise HTTPException(status_code=400, detail="Failed to create user")
    except HTTPException:
        raise
    except Exception as e:
        logger.warning("signup failed for %s: %s", signup_req.email, e)
        message = str(e).lower()
        if "already registered" in message or "already exists" in message:
            detail = "An account with this email already exists."
        elif "password" in message:
            detail = "Password does not meet the security requirements."
        else:
            detail = "Account creation failed. Please check your details and try again."
        raise HTTPException(status_code=400, detail=detail)

@router.post("/login", response_model=AuthResponse)
@limiter.limit("5/minute")  # SECURITY FIX: Prevent brute force attacks
async def login(request: Request, signin_req: SignInRequest):
    """Login user"""
    if not public_supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")

    try:
        # Sign in user with Supabase Auth
        response = public_supabase.auth.sign_in_with_password({
            "email": signin_req.email,
            "password": signin_req.password
        })
        
        if response.user and response.session:
            track_user_event("login")
            user_data = response.user.user_metadata or {}

            return {
                "user": {
                    "id": response.user.id,
                    "email": response.user.email,
                    "name": user_data.get("name", ""),
                },
                "session": {
                    "access_token": response.session.access_token,
                    "refresh_token": response.session.refresh_token,
                }
            }
        else:
            raise HTTPException(status_code=401, detail="Invalid credentials")
    except HTTPException:
        raise
    except Exception as e:
        logger.info("login failed for %s: %s", signin_req.email, e)
        if "email not confirmed" in str(e).lower():
            raise HTTPException(
                status_code=403,
                detail="Please confirm your email before logging in.",
            )
        raise HTTPException(status_code=401, detail="Invalid credentials")

@router.post("/logout")
async def logout(_auth_user: Dict[str, Any] = Depends(get_authenticated_user)):
    """JWT logout is completed by clearing the persisted device session."""
    return {"message": "Logged out successfully"}

@router.get("/user")
async def get_current_user(
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Get current authenticated user"""
    try:
        profile_response = (
            service_supabase.table("profiles")
            .select("name,profile_image_url,phone_number,preferences,points")
            .eq("id", auth_user["user_id"])
            .maybe_single()
            .execute()
        )
        profile = profile_response.data or {}
        preferences = profile.get("preferences") or {}
        stats_response = (
            service_supabase.table("user_stats")
            .select("current_streak")
            .eq("user_id", auth_user["user_id"])
            .maybe_single()
            .execute()
        )
        stats = stats_response.data or {}
        badges_response = (
            service_supabase.table("user_badges")
            .select("badge:badges(name)")
            .eq("user_id", auth_user["user_id"])
            .execute()
        )
        return {
            "id": auth_user["user_id"],
            "email": auth_user.get("email") or "",
            "name": profile.get("name") or auth_user.get("metadata", {}).get("name", ""),
            "profile_image_url": profile.get("profile_image_url"),
            "phone_number": profile.get("phone_number") or preferences.get("phone_number"),
            "is_phone_verified": bool(preferences.get("is_phone_verified")),
            "points": profile.get("points") or 0,
            "streak": stats.get("current_streak") or 0,
            "badges": [
                item["badge"]["name"]
                for item in (badges_response.data or [])
                if item.get("badge") and item["badge"].get("name")
            ],
        }
    except Exception as e:
        logger.warning("Profile enrichment failed for %s: %s", auth_user["user_id"], e)
        return {
            "id": auth_user["user_id"],
            "email": auth_user.get("email") or "",
            "name": auth_user.get("metadata", {}).get("name", ""),
        }


@router.post("/change-password")
@limiter.limit("5/minute")
async def change_password(
    request: Request,
    body: ChangePasswordRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    """Change password for the authenticated user using service role."""
    if not service_supabase:
        raise HTTPException(status_code=503, detail="Service role not configured")
    try:
        service_supabase.auth.admin.update_user_by_id(
            auth_user["user_id"],
            {"password": body.new_password},
        )
        return {"status": "success"}
    except Exception as e:
        logger.warning("change_password failed for %s: %s", auth_user.get("user_id"), e)
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/reset-password")
@limiter.limit("3/minute")
async def reset_password(request: Request, body: ResetPasswordRequest):
    """Send a password-reset email via Supabase. Always returns 200 to prevent enumeration."""
    try:
        public_supabase.auth.reset_password_for_email(
            body.email,
            options={"redirect_to": settings.PASSWORD_RESET_REDIRECT_URL},
        )
    except Exception as e:
        logger.warning("reset_password email error for %s: %s", body.email, e)
    return {"status": "success"}


@router.get("/reset-password", response_class=HTMLResponse)
async def password_reset_page():
    html_path = os.path.join(os.path.dirname(__file__), "..", "templates", "reset_password.html")
    try:
        with open(html_path, encoding="utf-8") as f:
            html = f.read()
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Password reset page not found")

    return HTMLResponse(
        html.replace("__SUPABASE_URL__", settings.SUPABASE_URL).replace(
            "__SUPABASE_ANON_KEY__",
            settings.SUPABASE_KEY,
        )
    )
