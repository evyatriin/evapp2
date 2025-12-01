from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, EmailStr
from typing import Optional
from supabase_client import supabase

router = APIRouter()

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
async def signup(request: SignUpRequest):
    """Register a new user"""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    try:
        # Sign up user with Supabase Auth
        response = supabase.auth.sign_up({
            "email": request.email,
            "password": request.password,
            "options": {
                "data": {
                    "name": request.name
                }
            }
        })
        
        if response.user:
            return {
                "user": {
                    "id": response.user.id,
                    "email": response.user.email,
                    "name": request.name,
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
async def login(request: SignInRequest):
    """Login user"""
    if not supabase:
        raise HTTPException(status_code=503, detail="Authentication service not configured")
    
    try:
        # Sign in user with Supabase Auth
        response = supabase.auth.sign_in_with_password({
            "email": request.email,
            "password": request.password
        })
        
        if response.user and response.session:
            # Get user metadata
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
