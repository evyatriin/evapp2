import os
from datetime import date, timedelta
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from supabase_client import supabase, service_supabase
from auth_utils import ensure_admin_user, get_authenticated_user

router = APIRouter()

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

# ---------------------------------------------------------------------------
# Existing admin endpoints
# ---------------------------------------------------------------------------
@router.get("/reports")
async def get_reports(auth_user: Dict[str, Any] = Depends(get_authenticated_user)):
    try:
        ensure_admin_user(auth_user)
        response = supabase.table("user_reports").select("*").eq("status", "Open").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/moderate/content")
async def moderate_content(
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
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ban")
async def ban_user(
    request: BanRequest,
    auth_user: Dict[str, Any] = Depends(get_authenticated_user),
):
    try:
        ensure_admin_user(auth_user)
        request.admin_id = auth_user["user_id"]
        supabase.table("profiles").update({"is_banned": True}).eq("id", request.user_id).execute()
        supabase.table("admin_audit_logs").insert({
            "admin_id": request.admin_id,
            "action": "ban_user",
            "target_id": request.user_id,
            "details": {"reason": request.reason},
        }).execute()
        return {"status": "success", "message": "User banned"}
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
# Dashboard HTML (no auth — auth handled by the page itself)
# ---------------------------------------------------------------------------
@router.get("/dashboard", response_class=HTMLResponse)
async def admin_dashboard():
    html_path = os.path.join(os.path.dirname(__file__), "..", "templates", "admin_dashboard.html")
    try:
        with open(html_path, encoding="utf-8") as f:
            return HTMLResponse(f.read())
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Dashboard template not found")
