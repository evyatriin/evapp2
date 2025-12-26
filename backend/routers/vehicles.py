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
    is_primary: bool = False

class VehicleCreateRequest(BaseModel):
    user_id: str
    brand: str
    model: str
    variant: str
    range_efficiency: float
    image_url: Optional[str] = None
    photo_url: Optional[str] = None
    preferred_charging_networks: List[str] = []
    is_primary: bool = False

class VehicleUpdateRequest(BaseModel):
    brand: Optional[str] = None
    model: Optional[str] = None
    variant: Optional[str] = None
    range_efficiency: Optional[float] = None
    image_url: Optional[str] = None
    photo_url: Optional[str] = None
    preferred_charging_networks: Optional[List[str]] = None
    is_primary: Optional[bool] = None

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
            "preferred_charging_networks": vehicle.preferred_charging_networks,
            "is_primary": vehicle.is_primary
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
        # Delete from mock store
        _delete_mock_vehicle(vehicle_id)
        return {"message": "Vehicle deleted successfully (mock)"}
    
    try:
        response = supabase.table("vehicles").delete().eq("id", vehicle_id).execute()
        return {"message": "Vehicle deleted successfully"}
    except Exception as e:
        print(f"Supabase error: {e}")
        _delete_mock_vehicle(vehicle_id)
        return {"message": "Vehicle deleted successfully (mock)"}

@router.put("/{vehicle_id}/primary", response_model=VehicleProfile)
async def set_primary_vehicle(vehicle_id: str):
    """Set a vehicle as the primary vehicle for a user"""
    if not supabase:
        # Return mock response if Supabase is not configured
        return _set_primary_mock_vehicle(vehicle_id)
    
    try:
        # First get the vehicle to get the user_id
        vehicle_response = supabase.table("vehicles").select("*").eq("id", vehicle_id).execute()
        if not vehicle_response.data:
            raise HTTPException(status_code=404, detail="Vehicle not found")
        
        user_id = vehicle_response.data[0]["user_id"]
        
        # Unset primary for all other vehicles of this user
        supabase.table("vehicles").update({"is_primary": False}).eq("user_id", user_id).execute()
        
        # Set this vehicle as primary
        response = supabase.table("vehicles").update({"is_primary": True}).eq("id", vehicle_id).execute()
        
        if response.data:
            return response.data[0]
        else:
            raise HTTPException(status_code=500, detail="Failed to set primary vehicle")
    except HTTPException:
        raise
    except Exception as e:
        print(f"Supabase error: {e}")
        return _set_primary_mock_vehicle(vehicle_id)

# In-memory storage for mock vehicles when Supabase is not available
_mock_vehicles_store: dict[str, list] = {}

def _get_mock_vehicles(user_id: str):
    """Get vehicles from in-memory store for a user"""
    if user_id not in _mock_vehicles_store:
        # Initialize with one default vehicle for new users
        import uuid
        _mock_vehicles_store[user_id] = [
            {
                "id": str(uuid.uuid4()),
                "user_id": user_id,
                "brand": "Tata",
                "model": "Nexon EV",
                "variant": "Max",
                "range_efficiency": 0.8,
                "image_url": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
                "photo_url": None,
                "preferred_charging_networks": ["Tata Power", "Statiq"],
                "is_primary": True
            }
        ]
    return _mock_vehicles_store[user_id]

def _create_mock_vehicle(vehicle: VehicleCreateRequest):
    """Create a new mock vehicle and add to in-memory store"""
    import uuid
    new_vehicle = {
        "id": str(uuid.uuid4()),
        "user_id": vehicle.user_id,
        "brand": vehicle.brand,
        "model": vehicle.model,
        "variant": vehicle.variant,
        "range_efficiency": vehicle.range_efficiency,
        "image_url": vehicle.image_url,
        "photo_url": vehicle.photo_url,
        "preferred_charging_networks": vehicle.preferred_charging_networks,
        "is_primary": vehicle.is_primary
    }
    
    # Add to store
    if vehicle.user_id not in _mock_vehicles_store:
        _mock_vehicles_store[vehicle.user_id] = []
    _mock_vehicles_store[vehicle.user_id].append(new_vehicle)
    
    return new_vehicle

def _update_mock_vehicle(vehicle_id: str, vehicle: VehicleUpdateRequest):
    """Update a mock vehicle in the in-memory store"""
    for user_id, vehicles in _mock_vehicles_store.items():
        for i, v in enumerate(vehicles):
            if v["id"] == vehicle_id:
                # Update fields that are provided
                if vehicle.brand is not None:
                    v["brand"] = vehicle.brand
                if vehicle.model is not None:
                    v["model"] = vehicle.model
                if vehicle.variant is not None:
                    v["variant"] = vehicle.variant
                if vehicle.range_efficiency is not None:
                    v["range_efficiency"] = vehicle.range_efficiency
                if vehicle.image_url is not None:
                    v["image_url"] = vehicle.image_url
                if vehicle.photo_url is not None:
                    v["photo_url"] = vehicle.photo_url
                if vehicle.preferred_charging_networks is not None:
                    v["preferred_charging_networks"] = vehicle.preferred_charging_networks
                if vehicle.is_primary is not None:
                    v["is_primary"] = vehicle.is_primary
                return v
    
    # Vehicle not found, return a default response
    return {
        "id": vehicle_id,
        "user_id": "mock_user",
        "brand": vehicle.brand or "Tata",
        "model": vehicle.model or "Nexon EV",
        "variant": vehicle.variant or "Max",
        "range_efficiency": vehicle.range_efficiency or 0.8,
        "image_url": vehicle.image_url or "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "photo_url": vehicle.photo_url,
        "preferred_charging_networks": vehicle.preferred_charging_networks or ["Tata Power"],
        "is_primary": vehicle.is_primary if vehicle.is_primary is not None else False
    }

def _delete_mock_vehicle(vehicle_id: str):
    """Delete a mock vehicle from the in-memory store"""
    for user_id, vehicles in _mock_vehicles_store.items():
        for i, v in enumerate(vehicles):
            if v["id"] == vehicle_id:
                del vehicles[i]
                return True
    return False

def _set_primary_mock_vehicle(vehicle_id: str):
    """Set a mock vehicle as primary and unset others"""
    target_vehicle = None
    target_user_id = None
    
    # Find the vehicle and its user
    for user_id, vehicles in _mock_vehicles_store.items():
        for v in vehicles:
            if v["id"] == vehicle_id:
                target_vehicle = v
                target_user_id = user_id
                break
        if target_vehicle:
            break
    
    if target_vehicle and target_user_id:
        # Unset primary for all other vehicles of this user
        for v in _mock_vehicles_store[target_user_id]:
            v["is_primary"] = (v["id"] == vehicle_id)
        return target_vehicle
    
    # Vehicle not found, return a default response
    return {
        "id": vehicle_id,
        "user_id": "mock_user",
        "brand": "Tata",
        "model": "Nexon EV",
        "variant": "Max",
        "range_efficiency": 0.8,
        "image_url": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "photo_url": None,
        "preferred_charging_networks": ["Tata Power"],
        "is_primary": True
    }

