import logging
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth_utils import ensure_same_user, get_authenticated_user
from supabase_client import service_supabase, supabase

router = APIRouter()
logger = logging.getLogger(__name__)


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


def _range_to_efficiency(range_km: float) -> float:
    return max(0.55, min(1.2, range_km / 400.0))


def _coerce_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _vehicle_image_url(brand: str, model: str) -> str:
    key = f"{brand}|{model}".lower()
    images = {
        "tata|nexon ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "tata|tigor ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/115777/tigor-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "tata|punch ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/163701/punch-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80",
        "tata|tiago ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/131129/tiago-ev-exterior-right-front-three-quarter-14.jpeg?isig=0&q=80",
        "tata|curvv ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/139651/curvv-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "tata|harrier ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/139187/harrier-ev-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "tata|sierra ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/187421/sierra-ev-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "mg|comet ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/146499/comet-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80",
        "mg|zs ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/113531/zs-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80",
        "mg|cyberster": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/139949/cyberster-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "mahindra|be 6": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/181095/be-6e-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "mahindra|xev 9e": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/181097/xev-9e-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "mahindra|xuv400": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/143867/xuv400-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80",
        "hyundai|kona electric": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/40530/kona-electric-exterior-right-front-three-quarter-16.jpeg?isig=0&q=80",
        "hyundai|ioniq 5": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/136217/ioniq-5-exterior-right-front-three-quarter-4.jpeg?isig=0&q=80",
        "hyundai|creta ev": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/171213/creta-electric-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "byd|atto 3": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/51940/atto-3-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
        "byd|sealion 7": "https://imgd.aeplcdn.com/1056x594/n/cw/ec/175893/sealion-7-exterior-right-front-three-quarter.jpeg?isig=0&q=80",
    }
    return images.get(key, "")


def _default_networks(brand: str) -> List[str]:
    brand_key = brand.lower()
    if brand_key == "tata":
        return ["Tata Power", "Statiq"]
    if brand_key == "mg":
        return ["Fortum", "Tata Power"]
    if brand_key == "mahindra":
        return ["ChargeZone", "Jio-bp"]
    if brand_key == "hyundai":
        return ["ChargeZone", "Shell Recharge"]
    if brand_key == "byd":
        return ["ChargeZone", "Statiq"]
    if brand_key == "citroen":
        return ["ChargeZone", "Jio-bp"]
    if brand_key in {
        "bmw",
        "mercedes-benz",
        "audi",
        "volvo",
        "kia",
        "porsche",
        "rolls-royce",
        "lexus",
        "jaguar",
    }:
        return ["Shell Recharge", "ChargeZone"]
    if brand_key == "vinfast":
        return ["ChargeZone", "Statiq"]
    if brand_key == "mini":
        return ["ChargeZone", "Shell Recharge"]
    if brand_key == "tesla":
        return ["Supercharger"]
    if brand_key == "nissan":
        return ["ChargeZone"]
    if brand_key in {"maruti suzuki", "toyota"}:
        return ["Tata Power", "ChargeZone"]
    return []


def _normalized_template_id(brand: str, model: str, variant: str, explicit_id: Any) -> str:
    if isinstance(explicit_id, str) and explicit_id.strip():
        return explicit_id.strip()

    raw_id = f"{brand}-{model}-{variant}".lower()
    normalized_id = "".join(ch if ch.isalnum() else "-" for ch in raw_id).strip("-")
    while "--" in normalized_id:
        normalized_id = normalized_id.replace("--", "-")
    return normalized_id


def _coerce_template(item: Dict[str, Any]) -> VehicleTemplate:
    brand = str(item.get("brand") or "").strip()
    model = str(item.get("model") or "").strip()
    variant = str(item.get("variant") or "").strip()
    if not brand or not model or not variant:
        raise ValueError("Vehicle template is missing brand/model/variant")

    range_efficiency = _coerce_float(item.get("range_efficiency"))
    if range_efficiency is None:
        derived_range_km = _coerce_float(item.get("real_world_range_km"))
        if derived_range_km is None:
            derived_range_km = _coerce_float(item.get("range_wltp_km"))
        range_efficiency = _range_to_efficiency(derived_range_km or 250.0)

    image_url = str(item.get("image_url") or "").strip() or _vehicle_image_url(brand, model)

    networks = item.get("preferred_charging_networks")
    if not isinstance(networks, list) or not networks:
        networks = _default_networks(brand)

    return VehicleTemplate(
        id=_normalized_template_id(brand, model, variant, item.get("id")),
        brand=brand,
        model=model,
        variant=variant,
        range_efficiency=range_efficiency,
        image_url=image_url,
        preferred_charging_networks=[str(network).strip() for network in networks if str(network).strip()],
    )


def _extract_vehicle_photo_path(photo_url: Optional[str]) -> Optional[str]:
    if not photo_url:
        return None
    path = urlparse(photo_url).path
    marker = "/storage/v1/object/public/vehicle-photos/"
    if marker not in path:
        return None
    relative_path = path.split(marker, 1)[1].strip("/")
    return relative_path or None


def _delete_vehicle_photo(photo_url: Optional[str]) -> None:
    photo_path = _extract_vehicle_photo_path(photo_url)
    if not photo_path:
        return
    client = service_supabase or supabase
    if not client:
        return
    try:
        client.storage.from_("vehicle-photos").remove([photo_path])
    except Exception as exc:
        logger.warning("Failed to delete vehicle photo %s: %s", photo_path, exc)


def _template(
    *,
    brand: str,
    model: str,
    variant: str,
    range_km: float,
) -> VehicleTemplate:
    raw_id = f"{brand}-{model}-{variant}".lower()
    normalized_id = "".join(
        ch if ch.isalnum() else "-" for ch in raw_id
    ).strip("-")
    while "--" in normalized_id:
        normalized_id = normalized_id.replace("--", "-")

    return VehicleTemplate(
        id=normalized_id,
        brand=brand,
        model=model,
        variant=variant,
        range_efficiency=_range_to_efficiency(range_km),
        image_url=_vehicle_image_url(brand, model),
        preferred_charging_networks=_default_networks(brand),
    )


_FALLBACK_TEMPLATES = [
    _template(brand="Tata", model="Nexon EV", variant="Creative MR", range_km=325),
    _template(brand="Tata", model="Nexon EV", variant="Creative LR", range_km=465),
    _template(brand="Tata", model="Nexon EV", variant="Fearless MR", range_km=325),
    _template(brand="Tata", model="Nexon EV", variant="Fearless LR", range_km=465),
    _template(brand="Tata", model="Punch EV", variant="Smart MR", range_km=315),
    _template(brand="Tata", model="Punch EV", variant="Empowered LR", range_km=421),
    _template(brand="Tata", model="Tiago EV", variant="XE MR", range_km=250),
    _template(brand="Tata", model="Tiago EV", variant="XZ+ LR", range_km=315),
    _template(brand="Tata", model="Tigor EV", variant="XE", range_km=306),
    _template(brand="Tata", model="Tigor EV", variant="XZ+", range_km=306),
    _template(brand="Tata", model="Curvv EV", variant="Creative", range_km=450),
    _template(brand="Tata", model="Curvv EV", variant="Accomplished LR", range_km=500),
    _template(brand="Tata", model="Harrier EV", variant="Adventure", range_km=500),
    _template(brand="Tata", model="Harrier EV", variant="Empowered AWD", range_km=550),
    _template(brand="Tata", model="Sierra EV", variant="Smart", range_km=450),
    _template(brand="Tata", model="Sierra EV", variant="Adventure", range_km=480),
    _template(brand="Tata", model="Sierra EV", variant="Accomplished AWD", range_km=500),
    _template(brand="MG", model="Comet EV", variant="Executive", range_km=230),
    _template(brand="MG", model="Comet EV", variant="Excite", range_km=230),
    _template(brand="MG", model="Comet EV", variant="Exclusive", range_km=230),
    _template(brand="MG", model="ZS EV", variant="Executive", range_km=461),
    _template(brand="MG", model="ZS EV", variant="Exclusive", range_km=461),
    _template(brand="MG", model="Cyberster", variant="RWD", range_km=500),
    _template(brand="MG", model="Cyberster", variant="AWD Performance", range_km=580),
    _template(brand="Mahindra", model="XUV400", variant="EC", range_km=375),
    _template(brand="Mahindra", model="XUV400", variant="EL", range_km=456),
    _template(brand="Mahindra", model="BE 6", variant="Pack One", range_km=557),
    _template(brand="Mahindra", model="BE 6", variant="Pack Three", range_km=683),
    _template(brand="Mahindra", model="XEV 9e", variant="Pack One", range_km=542),
    _template(brand="Mahindra", model="XEV 9e", variant="Pack Three AWD", range_km=656),
    _template(brand="Hyundai", model="IONIQ 5", variant="Long Range", range_km=631),
    _template(brand="Hyundai", model="Kona Electric", variant="Premium", range_km=452),
    _template(brand="Hyundai", model="Creta EV", variant="Base", range_km=450),
    _template(brand="BYD", model="Atto 3", variant="Dynamic", range_km=521),
    _template(brand="BYD", model="Atto 3", variant="Superior", range_km=521),
    _template(brand="BYD", model="Sealion 7", variant="Premium", range_km=567),
    _template(brand="BYD", model="Sealion 7", variant="Performance AWD", range_km=542),
    _template(brand="Citroen", model="eC3", variant="Feel", range_km=320),
    _template(brand="BMW", model="i4", variant="eDrive35", range_km=483),
    _template(brand="BMW", model="iX", variant="xDrive50", range_km=635),
    _template(brand="Mercedes-Benz", model="EQA", variant="250+", range_km=560),
    _template(brand="Mercedes-Benz", model="EQB", variant="300 4MATIC", range_km=423),
    _template(brand="Mercedes-Benz", model="EQS", variant="580", range_km=857),
    _template(brand="Audi", model="Q8 e-tron", variant="55 quattro", range_km=600),
    _template(brand="Audi", model="e-tron GT", variant="Quattro", range_km=500),
    _template(brand="Audi", model="e-tron GT", variant="RS", range_km=488),
    _template(brand="Volvo", model="XC40 Recharge", variant="Ultimate AWD", range_km=592),
    _template(brand="Volvo", model="C40 Recharge", variant="Ultimate AWD", range_km=530),
    _template(brand="Kia", model="EV6", variant="GT Line AWD", range_km=708),
    _template(brand="Kia", model="EV9", variant="GT Line AWD", range_km=541),
    _template(brand="VinFast", model="VF 6", variant="Eco", range_km=399),
    _template(brand="VinFast", model="VF 7", variant="Plus AWD", range_km=431),
    _template(brand="VinFast", model="VF 8", variant="Eco", range_km=471),
    _template(brand="VinFast", model="VF 8", variant="Plus AWD", range_km=457),
    _template(brand="VinFast", model="VF 9", variant="Plus AWD", range_km=531),
    _template(brand="VinFast", model="VF MPV 7", variant="Eco", range_km=400),
    _template(brand="VinFast", model="VF MPV 7", variant="Plus", range_km=450),
    _template(brand="VinFast", model="VF3", variant="Base", range_km=200),
    _template(brand="Mini", model="Cooper SE", variant="3-Door", range_km=270),
    _template(brand="Porsche", model="Taycan", variant="RWD", range_km=484),
    _template(brand="Porsche", model="Taycan", variant="Turbo S", range_km=412),
    _template(brand="Rolls-Royce", model="Spectre", variant="Coupe", range_km=530),
    _template(brand="Lexus", model="UX300e", variant="Luxury", range_km=315),
    _template(brand="Tesla", model="Model 3", variant="RWD", range_km=513),
    _template(brand="Tesla", model="Model 3", variant="Performance", range_km=547),
    _template(brand="Tesla", model="Model Y", variant="Long Range AWD", range_km=661),
    _template(brand="Nissan", model="Leaf", variant="e+", range_km=385),
    _template(brand="Jaguar", model="I-Pace", variant="HSE", range_km=470),
    _template(brand="Maruti Suzuki", model="e Vitara", variant="Delta 49kWh", range_km=400),
    _template(brand="Maruti Suzuki", model="e Vitara", variant="Zeta 60kWh", range_km=543),
    _template(brand="Maruti Suzuki", model="e Vitara", variant="Alpha 60kWh", range_km=550),
    _template(brand="Toyota", model="Urban Cruiser EV", variant="Standard", range_km=500),
]


def _template_key(template: VehicleTemplate) -> str:
    return f"{template.brand}|{template.model}|{template.variant}".lower()


def _merge_templates(primary: List[VehicleTemplate], fallback: List[VehicleTemplate]) -> List[VehicleTemplate]:
    merged: Dict[str, VehicleTemplate] = {}
    for template in fallback:
        merged[_template_key(template)] = template
    for template in primary:
        merged[_template_key(template)] = template
    return sorted(
        merged.values(),
        key=lambda item: (item.brand.lower(), item.model.lower(), item.variant.lower()),
    )


def _require_supabase():
    if not supabase:
        raise HTTPException(
            status_code=503,
            detail="Vehicle services are temporarily unavailable because the database is not configured.",
        )


def _get_vehicle_record(vehicle_id: str) -> Dict[str, Any]:
    _require_supabase()
    vehicle_response = (
        supabase.table("vehicles").select("*").eq("id", vehicle_id).maybe_single().execute()
    )
    vehicle = vehicle_response.data if vehicle_response else None
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return vehicle


@router.get("/templates", response_model=List[VehicleTemplate])
async def get_vehicle_templates():
    if not supabase:
        return _FALLBACK_TEMPLATES

    try:
        try:
            response = (
                supabase.table("vehicle_templates")
                .select("*")
                .eq("is_active", True)
                .order("sort_order")
                .execute()
            )
        except Exception:
            response = supabase.table("vehicle_templates").select("*").execute()
        templates = response.data or []
        if not templates:
            return _FALLBACK_TEMPLATES

        db_templates = []
        for item in templates:
            try:
                db_templates.append(_coerce_template(item))
            except Exception as exc:
                logger.warning("Skipping invalid vehicle template row %s: %s", item.get("id"), exc)

        if not db_templates:
            return _FALLBACK_TEMPLATES

        return _merge_templates(db_templates, _FALLBACK_TEMPLATES)
    except Exception as exc:
        logger.warning("Falling back to seeded vehicle templates: %s", exc)
        return _FALLBACK_TEMPLATES


@router.get("/", response_model=List[VehicleProfile])
async def get_vehicles(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_same_user(auth_user, user_id)
    _require_supabase()

    try:
        response = supabase.table("vehicles").select("*").eq("user_id", user_id).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load vehicles: {e}")


@router.get("/hash/{user_id}")
async def get_vehicles_hash(
    user_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_same_user(auth_user, user_id)
    _require_supabase()

    import hashlib
    import json

    try:
        response = (
            supabase.table("vehicles")
            .select("id, updated_at")
            .eq("user_id", user_id)
            .order("id")
            .execute()
        )
        vehicles = response.data
        hash_data = {
            "count": len(vehicles),
            "ids": sorted([v.get("id", "") for v in vehicles]),
            "updated": [v.get("updated_at", "") for v in sorted(vehicles, key=lambda x: x.get("id", ""))],
        }
        hash_string = json.dumps(hash_data, sort_keys=True)
        data_hash = hashlib.md5(hash_string.encode()).hexdigest()
        return {"hash": data_hash, "count": len(vehicles)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate vehicle hash: {e}")


@router.post("/", response_model=VehicleProfile)
async def create_vehicle(
    vehicle: VehicleCreateRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_same_user(auth_user, vehicle.user_id)
    _require_supabase()

    try:
        response = supabase.table("vehicles").insert(
            {
                "user_id": vehicle.user_id,
                "brand": vehicle.brand,
                "model": vehicle.model,
                "variant": vehicle.variant,
                "range_efficiency": vehicle.range_efficiency,
                "image_url": vehicle.image_url,
                "photo_url": vehicle.photo_url,
                "preferred_charging_networks": vehicle.preferred_charging_networks,
                "is_primary": vehicle.is_primary,
            }
        ).execute()

        if response.data:
            return response.data[0]
        raise HTTPException(status_code=500, detail="Failed to create vehicle")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create vehicle: {e}")


@router.put("/{vehicle_id}", response_model=VehicleProfile)
async def update_vehicle(
    vehicle_id: str,
    vehicle: VehicleUpdateRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    _require_supabase()

    try:
        existing_vehicle = _get_vehicle_record(vehicle_id)
        ensure_same_user(auth_user, existing_vehicle["user_id"])
        update_data = {k: v for k, v in vehicle.dict().items() if v is not None}

        response = supabase.table("vehicles").update(update_data).eq("id", vehicle_id).execute()

        if response.data:
            return response.data[0]
        raise HTTPException(status_code=404, detail="Vehicle not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update vehicle: {e}")


@router.delete("/{vehicle_id}")
async def delete_vehicle(
    vehicle_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    _require_supabase()

    try:
        existing_vehicle = _get_vehicle_record(vehicle_id)
        ensure_same_user(auth_user, existing_vehicle["user_id"])
        _delete_vehicle_photo(existing_vehicle.get("photo_url"))
        supabase.table("vehicles").delete().eq("id", vehicle_id).execute()
        return {"message": "Vehicle deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete vehicle: {e}")


@router.put("/{vehicle_id}/primary", response_model=VehicleProfile)
async def set_primary_vehicle(
    vehicle_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    _require_supabase()

    try:
        vehicle_record = _get_vehicle_record(vehicle_id)
        user_id = vehicle_record["user_id"]
        ensure_same_user(auth_user, user_id)

        supabase.table("vehicles").update({"is_primary": False}).eq("user_id", user_id).execute()
        response = supabase.table("vehicles").update({"is_primary": True}).eq("id", vehicle_id).execute()

        if response.data:
            return response.data[0]
        raise HTTPException(status_code=500, detail="Failed to set primary vehicle")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to set primary vehicle: {e}")
