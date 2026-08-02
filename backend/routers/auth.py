from fastapi import APIRouter, Depends, HTTPException, Header, Request
from pydantic import BaseModel, EmailStr
from typing import Any, Dict, Optional
from datetime import datetime, timedelta, timezone
from supabase_client import supabase, service_supabase
from metrics_tracker import track_user_event
from auth_utils import get_authenticated_user
from slowapi import Limiter
from slowapi.util import get_remote_address
import hashlib
import logging
import os
import secrets

logger = logging.getLogger(__name__)

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)

class SignUpRequest(BaseModel):
    email: EmailStr
    password: str
    name: str

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
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    try:
        # Sign up user with Supabase Auth
        response = supabase.auth.sign_up({
            "email": signup_req.email,
            "password": signup_req.password,
            "options": {
                "data": {
                    "name": signup_req.name
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
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/login", response_model=AuthResponse)
@limiter.limit("5/minute")  # SECURITY FIX: Prevent brute force attacks
async def login(request: Request, signin_req: SignInRequest):
    """Login user"""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")

    try:
        # Sign in user with Supabase Auth
        response = supabase.auth.sign_in_with_password({
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
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))

@router.post("/logout")
async def logout(authorization: Optional[str] = Header(None)):
    """Logout user"""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    try:
        if authorization and authorization.startswith("Bearer "):
            token = authorization.replace("Bearer ", "")
            # Set the session for this request
            supabase.auth.set_session(token, "")
            supabase.auth.sign_out()
        
        return {"message": "Logged out successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/user")
async def get_current_user(authorization: Optional[str] = Header(None)):
    """Get current authenticated user"""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    
    try:
        token = authorization.replace("Bearer ", "")
        
        # Get user from token
        response = supabase.auth.get_user(token)
        
        if response.user:
            user_data = response.user.user_metadata or {}

            # Pull phone-verification state from the profile so the app can
            # reflect it (needed to gate community help features).
            phone_number = None
            phone_verified = False
            try:
                profile_response = (
                    supabase.table("profiles")
                    .select("preferences")
                    .eq("id", response.user.id)
                    .maybe_single()
                    .execute()
                )
                prefs = (
                    (profile_response.data or {}).get("preferences") or {}
                    if profile_response
                    else {}
                )
                phone_number = prefs.get("phone_number")
                phone_verified = bool(prefs.get("is_phone_verified", False))
            except Exception as profile_error:
                logger.info("Could not load profile prefs for user: %s", profile_error)

            return {
                "id": response.user.id,
                "email": response.user.email,
                "name": user_data.get("name", ""),
                "profile_image_url": user_data.get("profile_image_url"),
                "email_verified": bool(getattr(response.user, "email_confirmed_at", None)),
                "phone_number": phone_number,
                "is_phone_verified": phone_verified,
            }
        else:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))


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
        supabase.auth.reset_password_for_email(
            body.email,
            options={"redirect_to": "https://evraahein.app/reset.html"},
        )
    except Exception as e:
        logger.warning("reset_password email error for %s: %s", body.email, e)
    return {"status": "success"}


# ---------------------------------------------------------------------------
# Phone verification (OTP)
#
# SCAFFOLD: In dev/test mode (no SMS_PROVIDER env var) we skip sending an SMS
# and use a fixed TEST_OTP so the flow works end-to-end. Before launch, set
# SMS_PROVIDER and implement _send_sms_otp() against MSG91 / Twilio Verify with
# credentials supplied as Cloud Run env vars. Everything else stays the same.
# ---------------------------------------------------------------------------

TEST_OTP = os.getenv("TEST_OTP", "123456")
OTP_TTL_MINUTES = 10


class RequestPhoneVerification(BaseModel):
    phone_number: str


class VerifyPhoneOtp(BaseModel):
    phone_number: str
    otp: str


def _sms_provider_configured() -> bool:
    return bool(os.getenv("SMS_PROVIDER"))


def _hash_otp(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _send_sms_otp(phone_number: str, code: str) -> None:
    """Deliver the OTP via the configured SMS provider.

    Dev/test mode (no SMS_PROVIDER): log the code and rely on TEST_OTP.
    To go live, branch on the provider name and call it with env credentials.
    """
    provider = os.getenv("SMS_PROVIDER", "").strip().lower()
    if not provider:
        logger.info("[DEV] Phone OTP for %s is %s (set SMS_PROVIDER for real SMS)", phone_number, code)
        return
    # TODO(launch): implement real delivery, e.g.:
    #   if provider == "msg91": ...   (MSG91_AUTHKEY, MSG91_TEMPLATE_ID)
    #   if provider == "twilio": ...  (TWILIO_ACCOUNT_SID, TWILIO_VERIFY_SID)
    raise HTTPException(status_code=500, detail=f"SMS provider '{provider}' is not implemented yet")


def _load_prefs(user_id: str) -> Dict[str, Any]:
    current = (
        supabase.table("profiles").select("preferences").eq("id", user_id).maybe_single().execute()
    )
    return ((current.data or {}).get("preferences") or {}) if current else {}


@router.post("/request-phone-verification")
@limiter.limit("5/minute")
async def request_phone_verification(
    request: Request,
    body: RequestPhoneVerification,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    phone = (body.phone_number or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="Phone number is required")

    user_id = auth_user["user_id"]
    code = TEST_OTP if not _sms_provider_configured() else f"{secrets.randbelow(1000000):06d}"
    expires_at = (datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)).isoformat()

    try:
        prefs = _load_prefs(user_id)
        prefs["phone_pending"] = phone
        prefs["phone_otp_hash"] = _hash_otp(code)
        prefs["phone_otp_expires_at"] = expires_at
        supabase.table("profiles").update({"preferences": prefs}).eq("id", user_id).execute()
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
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    phone = (body.phone_number or "").strip()
    otp = (body.otp or "").strip()
    if not phone or not otp:
        raise HTTPException(status_code=400, detail="Phone number and code are required")

    user_id = auth_user["user_id"]
    try:
        prefs = _load_prefs(user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not verify phone: {e}")

    stored_hash = prefs.get("phone_otp_hash")
    pending = prefs.get("phone_pending")
    expires_at = prefs.get("phone_otp_expires_at")

    if not stored_hash or not pending:
        raise HTTPException(status_code=400, detail="Request a new code and try again.")
    if pending != phone:
        raise HTTPException(status_code=400, detail="This code was sent to a different number.")
    try:
        if expires_at and datetime.fromisoformat(expires_at) < datetime.now(timezone.utc):
            raise HTTPException(status_code=400, detail="That code has expired. Request a new one.")
    except HTTPException:
        raise
    except Exception:
        pass  # If the timestamp can't be parsed, fall through to the hash check.
    if _hash_otp(otp) != stored_hash:
        raise HTTPException(status_code=400, detail="Incorrect code. Please try again.")

    prefs["is_phone_verified"] = True
    prefs["phone_number"] = phone
    prefs.pop("phone_otp_hash", None)
    prefs.pop("phone_pending", None)
    prefs.pop("phone_otp_expires_at", None)
    try:
        supabase.table("profiles").update({"preferences": prefs}).eq("id", user_id).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not save verification: {e}")

    return {"status": "verified", "is_phone_verified": True}
