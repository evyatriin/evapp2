import os
from datetime import date, timedelta
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from supabase_client import supabase, service_supabase
from auth_utils import ensure_admin_user, get_authenticated_user
from slowapi import Limiter
from slowapi.util import get_remote_address

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)

# ---------------------------------------------------------------------------
# Cost tables (USD per 1 000 calls, monthly free-tier ceiling)
# ---------------------------------------------------------------------------
_API_COSTS: dict[str, dict] = {
    "here_routing":          {"label": "HERE Routing",          "rate": 5.50,  "free_tier": 250_000},
    "here_browse":           {"label": "HERE Browse/Search",    "rate": 1.00,  "free_tier": 250_000},
    "google_places_nearby":  {"label": "Google Places Nearby",  "rate": 32.00, "free_tier": 0},
    "google_autocomplete":   {"label": "Google Autocomplete",   "rate": 2.83,  "free_tier": 0},
    "google_place_details":  {"label": "Google Place Details",  "rate": 17.00, "free_tier": 0},
    "openchargemap":         {"label": "OpenChargeMap",         "rate": 0.0,   "free_tier": 999_999},
}

GOOGLE_MONTHLY_CREDIT_USD = 200.0  # shared $200 Maps credit
CLOUD_RUN_COST_PER_REQUEST = 0.0000076  # ~$7.60 per million at 300 ms avg

# ---------------------------------------------------------------------------
# Existing moderation models
# ---------------------------------------------------------------------------
class ModerationRequest(BaseModel):
    admin_id: str
    content_type: str
    content_id: str
    action: str

class BanRequest(BaseModel):
    admin_id: str
    user_id: str
    reason: str


class VehicleTemplateCreate(BaseModel):
    id: Optional[str] = None
    brand: str
    model: str
    variant: str
    battery_kwh: Optional[float] = None
    certified_range_km: Optional[float] = None
    range_cycle: Optional[str] = None
    real_world_range_km: Optional[float] = None
    dc_fast_charge_kw: Optional[float] = None
    ac_charge_kw: Optional[float] = None
    connector_type: Optional[str] = None
    price_min: Optional[float] = None
    price_max: Optional[float] = None
    launch_status: Optional[str] = "available"
    image_url: Optional[str] = None
    source_url: Optional[str] = None
    last_seen_at: Optional[str] = None
    verified_at: Optional[str] = None
    confidence_score: Optional[float] = None
    preferred_charging_networks: Optional[List[str]] = None
    is_active: Optional[bool] = True
    sort_order: Optional[int] = 0
    # Deprecated admin payload aliases kept so older dashboard builds do not fail.
    battery_capacity_kwh: Optional[float] = None
    max_charging_power_kw: Optional[float] = None
    connectors: Optional[List[str]] = None
    range_wltp_km: Optional[float] = None
    efficiency_wh_km: Optional[float] = None


class VehicleTemplateUpdate(BaseModel):
    brand: Optional[str] = None
    model: Optional[str] = None
    variant: Optional[str] = None
    battery_kwh: Optional[float] = None
    certified_range_km: Optional[float] = None
    range_cycle: Optional[str] = None
    real_world_range_km: Optional[float] = None
    dc_fast_charge_kw: Optional[float] = None
    ac_charge_kw: Optional[float] = None
    connector_type: Optional[str] = None
    price_min: Optional[float] = None
    price_max: Optional[float] = None
    launch_status: Optional[str] = None
    image_url: Optional[str] = None
    source_url: Optional[str] = None
    last_seen_at: Optional[str] = None
    verified_at: Optional[str] = None
    confidence_score: Optional[float] = None
    preferred_charging_networks: Optional[List[str]] = None
    is_active: Optional[bool] = None
    sort_order: Optional[int] = None
    # Deprecated admin payload aliases kept so older dashboard builds do not fail.
    battery_capacity_kwh: Optional[float] = None
    max_charging_power_kw: Optional[float] = None
    connectors: Optional[List[str]] = None
    range_wltp_km: Optional[float] = None
    efficiency_wh_km: Optional[float] = None


class ContentSectionCreate(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    icon: str = "book-open"
    tone: str = "primary"
    sort_order: int = 0
    is_active: bool = True


class ContentSectionUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    icon: Optional[str] = None
    tone: Optional[str] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None


class ContentResourceCreate(BaseModel):
    id: str
    section_id: str
    title: str
    subtitle: Optional[str] = None
    url: str
    sort_order: int = 0
    is_active: bool = True


class ContentResourceUpdate(BaseModel):
    section_id: Optional[str] = None
    title: Optional[str] = None
    subtitle: Optional[str] = None
    url: Optional[str] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None


def _admin_table(table_name: str):
    client = service_supabase or supabase
    if not client:
        raise HTTPException(status_code=503, detail="Database client is unavailable")
    return client.table(table_name)


def _model_payload(model: BaseModel) -> Dict[str, Any]:
    if hasattr(model, "model_dump"):
        data = model.model_dump(exclude_none=True)
    else:
        data = model.dict(exclude_none=True)
    return {
        key: value
        for key, value in data.items()
        if value != "" and value != []
    }


def _normalized_vehicle_template_id(brand: str, model: str, variant: str) -> str:
    raw_id = f"{brand}-{model}-{variant}".lower()
    normalized_id = "".join(ch if ch.isalnum() else "-" for ch in raw_id).strip("-")
    while "--" in normalized_id:
        normalized_id = normalized_id.replace("--", "-")
    return normalized_id


def _normalize_vehicle_payload(
    payload: Dict[str, Any],
    *,
    generate_id: bool = False,
) -> Dict[str, Any]:
    connectors = payload.get("connectors")
    if isinstance(connectors, str):
        connectors = [
            item.strip()
            for item in connectors.split(",")
            if item.strip()
        ]
    if connectors and not payload.get("connector_type"):
        payload["connector_type"] = ", ".join(str(item).strip() for item in connectors if str(item).strip())
    payload.pop("connectors", None)

    if payload.get("battery_kwh") is None and payload.get("battery_capacity_kwh") is not None:
        payload["battery_kwh"] = payload["battery_capacity_kwh"]
    payload.pop("battery_capacity_kwh", None)

    if payload.get("dc_fast_charge_kw") is None and payload.get("max_charging_power_kw") is not None:
        payload["dc_fast_charge_kw"] = payload["max_charging_power_kw"]
    payload.pop("max_charging_power_kw", None)

    if payload.get("certified_range_km") is None and payload.get("range_wltp_km") is not None:
        payload["certified_range_km"] = payload["range_wltp_km"]
        payload["range_cycle"] = payload.get("range_cycle") or "WLTP"
    payload.pop("range_wltp_km", None)
    payload.pop("efficiency_wh_km", None)

    launch_status = payload.get("launch_status")
    if isinstance(launch_status, str):
        payload["launch_status"] = launch_status.strip().lower() or "available"

    confidence_score = payload.get("confidence_score")
    if confidence_score is not None:
        payload["confidence_score"] = max(0, min(1, float(confidence_score)))

    if generate_id and not payload.get("id") and all(payload.get(key) for key in ("brand", "model", "variant")):
        payload["id"] = _normalized_vehicle_template_id(
            str(payload["brand"]),
            str(payload["model"]),
            str(payload["variant"]),
        )

    return payload


def _list_rows(table_name: str, order: str, limit: int):
    return (
        _admin_table(table_name)
        .select("*")
        .order(order)
        .limit(limit)
        .execute()
    ).data or []


def _single_written_row(response, missing_message: str):
    rows = response.data or []
    if not rows:
        raise HTTPException(status_code=404, detail=missing_message)
    return rows[0]

# ---------------------------------------------------------------------------
# Existing admin endpoints
# ---------------------------------------------------------------------------
@router.get("/reports")
async def get_reports(auth_user: Dict[str, Any] = Depends(get_authenticated_user)):
    try:
        ensure_admin_user(auth_user)
        response = supabase.table("user_reports").select("*").eq("status", "Open").execute()
        return response.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/moderate/content")
@limiter.limit("30/minute")  # SECURITY FIX: Prevent spam moderation
async def moderate_content(
    http_request: Request,
    request: ModerationRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_admin_user(auth_user)
        request.admin_id = auth_user["user_id"]
        table_map = {"post": "community_posts", "comment": "community_comments", "review": "station_reviews"}
        table = table_map.get(request.content_type)
        if not table:
            raise HTTPException(400, "Invalid content type")
        is_hidden = request.action == "hide"
        supabase.table(table).update({"is_hidden": is_hidden}).eq("id", request.content_id).execute()
        supabase.table("admin_audit_logs").insert({
            "admin_id": request.admin_id,
            "action": f"{request.action}_{request.content_type}",
            "target_id": request.content_id,
        }).execute()
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ban")
@limiter.limit("10/minute")  # SECURITY FIX: Prevent spam bans
async def ban_user(
    http_request: Request,
    request: BanRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_admin_user(auth_user)
        request.admin_id = auth_user["user_id"]
        try:
            supabase.table("profiles").update(
                {"is_banned": True}
            ).eq("id", request.user_id).execute()
        except Exception as exc:
            if "Could not find the 'is_banned' column" not in str(exc):
                raise
            raise HTTPException(
                status_code=503,
                detail="Admin ban requires the profiles.is_banned migration.",
            )
        supabase.table("admin_audit_logs").insert({
            "admin_id": request.admin_id,
            "action": "ban_user",
            "target_id": request.user_id,
            "details": {"reason": request.reason},
        }).execute()
        return {"status": "success", "message": "User banned"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Catalog and content management
# ---------------------------------------------------------------------------
@router.get("/vehicle-templates")
async def list_vehicle_templates(
    limit: int = 200,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        return _list_rows("vehicle_templates", "brand", limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/vehicle-templates")
async def create_vehicle_template(
    vehicle: VehicleTemplateCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        payload = _normalize_vehicle_payload(_model_payload(vehicle), generate_id=True)
        response = _admin_table("vehicle_templates").insert(payload).execute()
        return _single_written_row(response, "Vehicle template was not created")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/vehicle-templates/{template_id}")
async def update_vehicle_template(
    template_id: str,
    vehicle: VehicleTemplateUpdate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        payload = _normalize_vehicle_payload(_model_payload(vehicle))
        if not payload:
            raise HTTPException(status_code=400, detail="No update fields supplied")
        response = _admin_table("vehicle_templates").update(payload).eq("id", template_id).execute()
        return _single_written_row(response, "Vehicle template not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/vehicle-templates/{template_id}")
async def delete_vehicle_template(
    template_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        response = _admin_table("vehicle_templates").delete().eq("id", template_id).execute()
        _single_written_row(response, "Vehicle template not found")
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/content/sections")
async def list_content_sections(
    limit: int = 100,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        return _list_rows("app_resource_sections", "sort_order", limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/content/sections")
async def create_content_section(
    section: ContentSectionCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        response = _admin_table("app_resource_sections").insert(_model_payload(section)).execute()
        return _single_written_row(response, "Content section was not created")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/content/sections/{section_id}")
async def update_content_section(
    section_id: str,
    section: ContentSectionUpdate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        payload = _model_payload(section)
        if not payload:
            raise HTTPException(status_code=400, detail="No update fields supplied")
        response = _admin_table("app_resource_sections").update(payload).eq("id", section_id).execute()
        return _single_written_row(response, "Content section not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/content/sections/{section_id}")
async def delete_content_section(
    section_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        response = _admin_table("app_resource_sections").delete().eq("id", section_id).execute()
        _single_written_row(response, "Content section not found")
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/content/resources")
async def list_content_resources(
    limit: int = 200,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        return _list_rows("app_resources", "sort_order", limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/content/resources")
async def create_content_resource(
    resource: ContentResourceCreate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        response = _admin_table("app_resources").insert(_model_payload(resource)).execute()
        return _single_written_row(response, "Content resource was not created")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/content/resources/{resource_id}")
async def update_content_resource(
    resource_id: str,
    resource: ContentResourceUpdate,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        payload = _model_payload(resource)
        if not payload:
            raise HTTPException(status_code=400, detail="No update fields supplied")
        response = _admin_table("app_resources").update(payload).eq("id", resource_id).execute()
        return _single_written_row(response, "Content resource not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/content/resources/{resource_id}")
async def delete_content_resource(
    resource_id: str,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    ensure_admin_user(auth_user)
    try:
        response = _admin_table("app_resources").delete().eq("id", resource_id).execute()
        _single_written_row(response, "Content resource not found")
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Metrics endpoint
# ---------------------------------------------------------------------------
@router.get("/metrics")
async def get_metrics(days: int = 30, auth_user: Dict[str, Any] = Depends(get_authenticated_user)):
    ensure_admin_user(auth_user)
    try:
        today = date.today()
        since = today - timedelta(days=days - 1)

        # --- API daily stats ---
        api_rows = (
            service_supabase.table("api_daily_stats")
            .select("*")
            .gte("stat_date", since.isoformat())
            .execute()
        ).data or []

        # --- External API stats ---
        ext_rows = (
            service_supabase.table("external_api_daily_stats")
            .select("*")
            .gte("stat_date", since.isoformat())
            .execute()
        ).data or []

        # --- User stats ---
        user_rows = (
            service_supabase.table("user_daily_stats")
            .select("*")
            .gte("stat_date", since.isoformat())
            .execute()
        ).data or []

        # --- Total Supabase user count (profiles table) ---
        try:
            total_users = len(
                (service_supabase.table("profiles").select("id").execute()).data or []
            )
        except Exception:
            total_users = None

        today_str = today.isoformat()

        # Today's API summary
        today_api = [r for r in api_rows if r["stat_date"] == today_str]
        total_calls_today = sum(r["call_count"] for r in today_api)
        error_calls_today = sum(r["error_count"] for r in today_api)
        total_dur = sum(r["total_duration_ms"] for r in today_api)
        avg_latency = int(total_dur / total_calls_today) if total_calls_today else 0

        # Today's user summary
        today_user = next((r for r in user_rows if r["stat_date"] == today_str), {})

        # --- Daily trend (call count + errors per day) ---
        trend: dict[str, dict] = {}
        for r in api_rows:
            d = r["stat_date"]
            if d not in trend:
                trend[d] = {"date": d, "total_calls": 0, "error_calls": 0}
            trend[d]["total_calls"] += r["call_count"]
            trend[d]["error_calls"] += r["error_count"]
        for r in user_rows:
            d = r["stat_date"]
            if d not in trend:
                trend[d] = {"date": d, "total_calls": 0, "error_calls": 0}
            trend[d]["logins"] = r.get("logins", 0)
            trend[d]["new_signups"] = r.get("new_signups", 0)
        daily_trend = sorted(trend.values(), key=lambda x: x["date"])

        # --- Top endpoints today ---
        ep_map: dict[str, dict] = {}
        for r in today_api:
            key = r["endpoint"]
            if key not in ep_map:
                ep_map[key] = {"endpoint": key, "method": r.get("method", ""), "calls": 0, "errors": 0, "total_ms": 0}
            ep_map[key]["calls"] += r["call_count"]
            ep_map[key]["errors"] += r["error_count"]
            ep_map[key]["total_ms"] += r["total_duration_ms"]
        top_endpoints = sorted(ep_map.values(), key=lambda x: -x["calls"])[:15]
        for ep in top_endpoints:
            ep["avg_latency_ms"] = int(ep["total_ms"] / ep["calls"]) if ep["calls"] else 0
            del ep["total_ms"]

        # --- External API usage (this month) ---
        month_start = today.replace(day=1).isoformat()
        ext_month_rows = (
            service_supabase.table("external_api_daily_stats")
            .select("*")
            .gte("stat_date", month_start)
            .execute()
        ).data or []

        ext_month: dict[str, int] = {}
        for r in ext_month_rows:
            svc = r["service_name"]
            ext_month[svc] = ext_month.get(svc, 0) + r["call_count"]

        ext_today: dict[str, int] = {}
        for r in ext_rows:
            if r["stat_date"] == today_str:
                svc = r["service_name"]
                ext_today[svc] = ext_today.get(svc, 0) + r["call_count"]

        # Cost calculation
        google_gross_usd = 0.0
        services_detail = []
        for key, meta in _API_COSTS.items():
            month_calls = ext_month.get(key, 0)
            today_calls = ext_today.get(key, 0)
            billable = max(0, month_calls - meta["free_tier"])
            cost_month = (billable / 1000) * meta["rate"]
            cost_today = (today_calls / 1000) * meta["rate"]
            if "google" in key:
                google_gross_usd += cost_month
            services_detail.append({
                "key": key,
                "label": meta["label"],
                "calls_today": today_calls,
                "calls_month": month_calls,
                "free_tier": meta["free_tier"],
                "rate_per_1000_usd": meta["rate"],
                "cost_today_usd": round(cost_today, 4),
                "cost_month_usd": round(cost_month, 4),
            })

        google_credit_used = min(google_gross_usd, GOOGLE_MONTHLY_CREDIT_USD)
        total_api_cost = sum(s["cost_month_usd"] for s in services_detail)
        net_google = max(0, google_gross_usd - google_credit_used)
        non_google = sum(s["cost_month_usd"] for s in services_detail if "google" not in s["key"])

        total_calls_month = sum(r["call_count"] for r in api_rows
                                if r["stat_date"] >= month_start)
        cloud_run_est = round(total_calls_month * CLOUD_RUN_COST_PER_REQUEST, 2)

        net_monthly = round(non_google + net_google + cloud_run_est, 2)

        return {
            "generated_at": today_str,
            "period_days": days,
            "total_registered_users": total_users,
            "today": {
                "date": today_str,
                "total_calls": total_calls_today,
                "error_calls": error_calls_today,
                "error_rate_pct": round(100 * error_calls_today / total_calls_today, 2) if total_calls_today else 0,
                "avg_latency_ms": avg_latency,
                "logins": today_user.get("logins", 0),
                "new_signups": today_user.get("new_signups", 0),
            },
            "daily_trend": daily_trend,
            "top_endpoints": top_endpoints,
            "external_services": services_detail,
            "costs": {
                "google_monthly_credit_usd": GOOGLE_MONTHLY_CREDIT_USD,
                "google_gross_usd": round(google_gross_usd, 2),
                "google_credit_applied_usd": round(google_credit_used, 2),
                "api_total_month_usd": round(total_api_cost, 2),
                "cloud_run_estimate_month_usd": cloud_run_est,
                "net_monthly_usd": net_monthly,
            },
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Dashboard HTML (requires admin authentication)
# ---------------------------------------------------------------------------
@router.get("/dashboard", response_class=HTMLResponse)
async def admin_dashboard():
    html_path = os.path.join(os.path.dirname(__file__), "..", "templates", "admin_dashboard.html")
    try:
        with open(html_path, encoding="utf-8") as f:
            return HTMLResponse(f.read())
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Dashboard template not found")
