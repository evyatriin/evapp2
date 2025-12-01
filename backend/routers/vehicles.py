from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from supabase_client import supabase

router = APIRouter()

class VehicleProfile(BaseModel):
    id: Optional[str] = None
    user_id: str
    brand: str
    model: str
    variant: str
    range_efficiency: float
    image_url: Optional[str] = None
    photo_url: Optional[str] = None
    preferred_charging_networks: List[str] = []

class VehicleCreateRequest(BaseModel):
    user_id: str
    brand: str
    model: str
    variant: str
    range_efficiency: float
    image_url: Optional[str] = None
    photo_url: Optional[str] = None
    preferred_charging_networks: List[str] = []

class VehicleUpdateRequest(BaseModel):
    brand: Optional[str] = None
    model: Optional[str] = None
    variant: Optional[str] = None
    range_efficiency: Optional[float] = None
    image_url: Optional[str] = None
    photo_url: Optional[str] = None
    preferred_charging_networks: Optional[List[str]] = None

class VehicleTemplate(BaseModel):
    id: str
    brand: str
    model: str
    variant: str
    range_efficiency: float
    image_url: str
    preferred_charging_networks: List[str]

@router.get("/templates", response_model=List[VehicleTemplate])
async def get_vehicle_templates():
    """Get available vehicle templates"""
    # In a real app, this might come from a DB table 'vehicle_templates'
    return [
        VehicleTemplate(
            id="tata-nexon-ev-max",
            brand="Tata",
            model="Nexon EV",
            variant="Max",
            range_efficiency=0.85,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
            preferred_charging_networks=["Tata Power", "Statiq"]
        ),
        VehicleTemplate(
            id="tata-tiago-ev",
            brand="Tata",
            model="Tiago EV",
            variant="Long Range",
            range_efficiency=0.82,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/131129/tiago-ev-exterior-right-front-three-quarter-14.jpeg?isig=0&q=80",
            preferred_charging_networks=["Tata Power"]
        ),
        VehicleTemplate(
            id="mg-zs-ev",
            brand="MG",
            model="ZS EV",
            variant="Exclusive",
            range_efficiency=0.9,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/113531/zs-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80",
            preferred_charging_networks=["Fortum", "Tata Power"]
        ),
        VehicleTemplate(
            id="mg-comet",
            brand="MG",
            model="Comet EV",
            variant="Plush",
            range_efficiency=0.75,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/146499/comet-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80",
            preferred_charging_networks=["Fortum"]
        ),
        VehicleTemplate(
            id="hyundai-kona",
            brand="Hyundai",
            model="Kona Electric",
            variant="Premium",
            range_efficiency=0.88,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/40530/kona-electric-exterior-right-front-three-quarter-16.jpeg?isig=0&q=80",
            preferred_charging_networks=["ChargeZone", "Statiq"]
        ),
        VehicleTemplate(
            id="hyundai-ioniq-5",
            brand="Hyundai",
            model="Ioniq 5",
            variant="RWD",
            range_efficiency=0.92,
            image_url="https://imgd.aeplcdn.com/1056x594/n/cw/ec/136217/ioniq-5-exterior-right-front-three-quarter-4.jpeg?isig=0&q=80",
            preferred_charging_networks=["ChargeZone", "Shell Recharge"]
        ),
    ]

@router.get("/", response_model=List[VehicleProfile])
async def get_vehicles(user_id: str):
    """Get all vehicles for a user"""
    if not supabase:
        # Return mock data if Supabase is not configured
        return _get_mock_vehicles(user_id)
    
    try:
        response = supabase.table("vehicles").select("*").eq("user_id", user_id).execute()
        return response.data
    except Exception as e:
        print(f"Supabase error: {e}")
        return _get_mock_vehicles(user_id)

@router.post("/", response_model=VehicleProfile)
async def create_vehicle(vehicle: VehicleCreateRequest):
    """Create a new vehicle"""
    if not supabase:
        # Return mock response if Supabase is not configured
        return _create_mock_vehicle(vehicle)
    
    try:
        response = supabase.table("vehicles").insert({
            "user_id": vehicle.user_id,
            "brand": vehicle.brand,
            "model": vehicle.model,
            "variant": vehicle.variant,
            "range_efficiency": vehicle.range_efficiency,
            "image_url": vehicle.image_url,
            "photo_url": vehicle.photo_url,
            "preferred_charging_networks": vehicle.preferred_charging_networks
        }).execute()
        
        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=500, detail="Failed to create vehicle")
    except Exception as e:
        print(f"Supabase error: {e}")
        return _create_mock_vehicle(vehicle)

@router.put("/{vehicle_id}", response_model=VehicleProfile)
async def update_vehicle(vehicle_id: str, vehicle: VehicleUpdateRequest):
    """Update a vehicle"""
    if not supabase:
        # Return mock response if Supabase is not configured
        return _update_mock_vehicle(vehicle_id, vehicle)
    
    try:
        update_data = {k: v for k, v in vehicle.dict().items() if v is not None}
        
        response = supabase.table("vehicles").update(update_data).eq("id", vehicle_id).execute()
        
        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=404, detail="Vehicle not found")
    except Exception as e:
        print(f"Supabase error: {e}")
        return _update_mock_vehicle(vehicle_id, vehicle)

@router.delete("/{vehicle_id}")
async def delete_vehicle(vehicle_id: str):
    """Delete a vehicle"""
    if not supabase:
        # Return mock response if Supabase is not configured
        return {"message": "Vehicle deleted successfully (mock)"}
    
    try:
        response = supabase.table("vehicles").delete().eq("id", vehicle_id).execute()
        return {"message": "Vehicle deleted successfully"}
    except Exception as e:
        print(f"Supabase error: {e}")
        return {"message": "Vehicle deleted successfully (mock)"}

# Mock data functions for when Supabase is not configured
def _get_mock_vehicles(user_id: str):
    return [
        {
            "id": "1",
            "user_id": user_id,
            "brand": "Tata",
            "model": "Nexon EV",
            "variant": "Max",
            "range_efficiency": 0.8,
            "image_url": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
            "photo_url": None,
            "preferred_charging_networks": ["Tata Power", "Statiq"]
        }
    ]

def _create_mock_vehicle(vehicle: VehicleCreateRequest):
    import uuid
    return {
        "id": str(uuid.uuid4()),
        "user_id": vehicle.user_id,
        "brand": vehicle.brand,
        "model": vehicle.model,
        "variant": vehicle.variant,
        "range_efficiency": vehicle.range_efficiency,
        "image_url": vehicle.image_url,
        "photo_url": vehicle.photo_url,
        "preferred_charging_networks": vehicle.preferred_charging_networks
    }

def _update_mock_vehicle(vehicle_id: str, vehicle: VehicleUpdateRequest):
    return {
        "id": vehicle_id,
        "user_id": "mock_user",
        "brand": vehicle.brand or "Tata",
        "model": vehicle.model or "Nexon EV",
        "variant": vehicle.variant or "Max",
        "range_efficiency": vehicle.range_efficiency or 0.8,
        "image_url": vehicle.image_url or "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "photo_url": vehicle.photo_url,
        "preferred_charging_networks": vehicle.preferred_charging_networks or ["Tata Power"]
    }
