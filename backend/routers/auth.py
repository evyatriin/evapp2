from fastapi import APIRouter, HTTPException, Header, Request
from pydantic import BaseModel, EmailStr
from typing import Optional
from supabase_client import supabase
from metrics_tracker import track_user_event
from slowapi import Limiter
from slowapi.util import get_remote_address

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
            
            return {
                "id": response.user.id,
                "email": response.user.email,
                "name": user_data.get("name", ""),
                "profile_image_url": user_data.get("profile_image_url"),
            }
        else:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))
