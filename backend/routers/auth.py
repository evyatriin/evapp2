from datetime import datetime, timedelta, timezone
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
import hashlib
import secrets

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


TEST_OTP = os.getenv("TEST_OTP", "123456")
OTP_TTL_MINUTES = 10


class RequestPhoneVerification(BaseModel):
    phone_number: str


class VerifyPhoneOtp(BaseModel):
    phone_number: str
    otp: str

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


def _sms_provider_configured() -> bool:
    return bool(os.getenv("SMS_PROVIDER"))


def _hash_otp(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _send_sms_otp(phone_number: str, code: str) -> None:
    provider = os.getenv("SMS_PROVIDER", "").strip().lower()
    if not provider:
        logger.info(
            "[DEV] Phone OTP for %s is %s (set SMS_PROVIDER for real SMS)",
            phone_number,
            code,
        )
        return
    raise HTTPException(
        status_code=500,
        detail=f"SMS provider '{provider}' is not implemented yet",
    )


def _load_profile_preferences(user_id: str) -> Dict[str, Any]:
    if not service_supabase:
        raise HTTPException(status_code=503, detail="Service role not configured")
    current = (
        service_supabase.table("profiles")
        .select("preferences")
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )
    return ((current.data or {}).get("preferences") or {}) if current else {}


@router.post("/request-phone-verification")
@limiter.limit("5/minute")
async def request_phone_verification(
    request: Request,
    body: RequestPhoneVerification,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    phone = (body.phone_number or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="Phone number is required")

    user_id = auth_user["user_id"]
    code = TEST_OTP if not _sms_provider_configured() else f"{secrets.randbelow(1000000):06d}"
    expires_at = (datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)).isoformat()

    try:
        preferences = _load_profile_preferences(user_id)
        preferences["phone_pending"] = phone
        preferences["phone_otp_hash"] = _hash_otp(code)
        preferences["phone_otp_expires_at"] = expires_at
        service_supabase.table("profiles").update({"preferences": preferences}).eq(
            "id", user_id
        ).execute()
        _send_sms_otp(phone, code)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not start phone verification: {e}")

    return {"status": "sent", "dev_mode": not _sms_provider_configured()}


@router.post("/verify-phone-otp")
@limiter.limit("5/minute")
async def verify_phone_otp(
    request: Request,
    body: VerifyPhoneOtp,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    phone = (body.phone_number or "").strip()
    otp = (body.otp or "").strip()
    if not phone or not otp:
        raise HTTPException(status_code=400, detail="Phone number and code are required")

    user_id = auth_user["user_id"]
    try:
        preferences = _load_profile_preferences(user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not verify phone: {e}")

    stored_hash = preferences.get("phone_otp_hash")
    pending_phone = preferences.get("phone_pending")
    expires_at = preferences.get("phone_otp_expires_at")

    if not stored_hash or not pending_phone:
        raise HTTPException(status_code=400, detail="Request a new code and try again.")
    if pending_phone != phone:
        raise HTTPException(status_code=400, detail="This code was sent to a different number.")

    try:
        if expires_at and datetime.fromisoformat(expires_at) < datetime.now(timezone.utc):
            raise HTTPException(status_code=400, detail="That code has expired. Request a new one.")
    except HTTPException:
        raise
    except Exception:
        pass

    if _hash_otp(otp) != stored_hash:
        raise HTTPException(status_code=400, detail="Incorrect code. Please try again.")

    preferences["is_phone_verified"] = True
    preferences["phone_number"] = phone
    preferences.pop("phone_otp_hash", None)
    preferences.pop("phone_pending", None)
    preferences.pop("phone_otp_expires_at", None)
    try:
        service_supabase.table("profiles").update({"preferences": preferences}).eq(
            "id", user_id
        ).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not save verification: {e}")

    return {"status": "verified", "is_phone_verified": True}
