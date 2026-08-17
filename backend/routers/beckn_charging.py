"""Beckn EV Charging router — all routes gated behind BECKN_CHARGING_ENABLED."""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from auth_utils import require_auth
from config import settings
from feature_flags import require_beckn_enabled
from models.beckn_models import (
    BecknContext,
    BecknFulfillment,
    BecknItem,
    BecknOrder,
    BecknResponse,
    MeterReading,
    Payment,
    PaymentStatusEnum,
    PaymentTypeEnum,
    Price,
    Quote,
    QuoteBreakup,
    QRValidationRequest,
    SessionCreateRequest,
    SessionResponse,
    SessionStateEnum,
)
from supabase_client import supabase
from utils.circuit_breaker import CircuitOpenError, get_charger_breaker
from utils.distributed_lock import LockAcquisitionError, charger_lock
from utils.idempotency import (
    check_idempotency,
    make_idempotency_key,
    store_idempotency_response,
)
from utils.ocpp_integration import OCPPManager
from utils.payment_service import PaymentService
from utils.qr_generator import generate_charger_qr, parse_qr_data, sign_qr_data
from utils.saga import Saga, SagaStep
from utils.session_state_machine import transition_state
from utils.websocket_manager import ws_manager

router = APIRouter()
logger = logging.getLogger(__name__)

_payment_service = PaymentService()

# ---------------------------------------------------------------------------
# Helper: Beckn context builder
# ---------------------------------------------------------------------------

def create_beckn_context(action: str, transaction_id: Optional[str] = None) -> BecknContext:
    """Build a Beckn context envelope for a given *action*."""
    return BecknContext(
        domain="nic2004:85159",
        country="IND",
        city="std:080",
        action=action,
        core_version="1.1.0",
        bap_id=getattr(settings, "BAP_ID", "ev-router-bap"),
        bap_uri=getattr(settings, "BACKEND_URL", "http://localhost:8080"),
        bpp_id=getattr(settings, "BPP_ID", "ev-router-bpp"),
        bpp_uri=getattr(settings, "BACKEND_URL", "http://localhost:8080"),
        transaction_id=transaction_id or str(uuid.uuid4()),
        message_id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc).isoformat(),
        ttl="PT30S",
    )


# ---------------------------------------------------------------------------
# Helper: charger lookup
# ---------------------------------------------------------------------------

def get_charger_by_id(charger_id: str) -> Optional[Dict[str, Any]]:
    """Query charger_metadata table for *charger_id*.  Returns None if not found."""
    if not supabase:
        logger.error("Supabase client not initialized")
        return None
    try:
        resp = (
            supabase.table("charger_metadata")
            .select("*")
            .eq("id", charger_id)
            .maybe_single()
            .execute()
        )
        return resp.data if resp else None
    except Exception as exc:
        logger.error("get_charger_by_id failed for charger_id=%s: %s", charger_id, exc)
        return None


# ---------------------------------------------------------------------------
# Helper: quote calculation
# ---------------------------------------------------------------------------

def calculate_quote(energy_kwh: float, charger_id: str) -> Quote:
    """Build a Quote with 5 % service charge and 5 % GST on top of energy cost.

    Price per kWh defaults to 10 INR if not configured on the charger record.
    """
    charger = get_charger_by_id(charger_id)
    price_per_kwh = 10.0
    if charger:
        price_per_kwh = float(charger.get("price_per_kwh", 10.0))

    energy_cost = round(energy_kwh * price_per_kwh, 2)
    service_fee = round(energy_cost * 0.05, 2)
    gst = round(energy_cost * 0.05, 2)
    total = round(energy_cost + service_fee + gst, 2)

    return Quote(
        price=Price(currency="INR", value=str(total)),
        breakup=[
            QuoteBreakup(
                title="Energy Cost",
                price=Price(currency="INR", value=str(energy_cost)),
            ),
            QuoteBreakup(
                title="Service Fee (5%)",
                price=Price(currency="INR", value=str(service_fee)),
            ),
            QuoteBreakup(
                title="GST (5%)",
                price=Price(currency="INR", value=str(gst)),
            ),
        ],
        ttl="PT30M",
    )


# ---------------------------------------------------------------------------
# Helper: build Beckn provider dict from charger row
# ---------------------------------------------------------------------------

def _charger_to_provider(charger: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": charger.get("id", ""),
        "descriptor": {
            "name": charger.get("name", charger.get("id", "")),
            "short_desc": charger.get("short_desc", ""),
            "images": charger.get("images", []),
        },
        "locations": [
            {
                "id": charger.get("id", ""),
                "gps": f"{charger.get('latitude', 0)},{charger.get('longitude', 0)}",
                "address": charger.get("address", ""),
                "city": {"name": charger.get("city", "")},
                "state": {"name": charger.get("state", "")},
            }
        ],
    }


def _connector_to_item(
    charger_id: str, connector: Dict[str, Any], idx: int
) -> BecknItem:
    connector_id = str(connector.get("id", str(idx)))
    power_kw = float(connector.get("power_kw", 0))
    price_per_kwh = float(connector.get("price_per_kwh", 10.0))

    return BecknItem(
        id=connector_id,
        descriptor={
            "name": f"{connector.get('type', 'Connector')} {power_kw} kW",
            "short_desc": f"{connector.get('charger_type', '')} — {connector.get('status', 'AVAILABLE')}",
            "long_desc": f"Connector type: {connector.get('type', '')}, Power: {power_kw} kW",
        },
        price=Price(currency="INR", value=str(price_per_kwh)),
        fulfillment_id=f"fulfillment_{connector_id}",
        tags=[
            {"descriptor": {"code": "connector_type"}, "value": connector.get("type", "")},
            {"descriptor": {"code": "charger_type"}, "value": connector.get("charger_type", "")},
            {"descriptor": {"code": "power_kw"}, "value": str(power_kw)},
            {"descriptor": {"code": "status"}, "value": connector.get("status", "AVAILABLE")},
        ],
    )


# ---------------------------------------------------------------------------
# 1. POST /beckn/search
# ---------------------------------------------------------------------------

@router.post("/beckn/search", dependencies=[Depends(require_beckn_enabled)])
async def beckn_search(
    latitude: float = Query(..., description="Search centre latitude"),
    longitude: float = Query(..., description="Search centre longitude"),
    radius_km: float = Query(5.0, description="Search radius in kilometres"),
    _user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Beckn on_search — discover chargers near a location."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        # Simple bounding-box pre-filter (roughly 1° lat/lng ≈ 111 km)
        delta = radius_km / 111.0
        resp = (
            supabase.table("charger_metadata")
            .select("*")
            .gte("latitude", latitude - delta)
            .lte("latitude", latitude + delta)
            .gte("longitude", longitude - delta)
            .lte("longitude", longitude + delta)
            .eq("is_active", True)
            .limit(50)
            .execute()
        )
        chargers = resp.data or []
    except Exception as exc:
        logger.error("beckn_search DB query failed: %s", exc)
        raise HTTPException(status_code=500, detail="Search failed")

    providers = []
    for charger in chargers:
        provider = _charger_to_provider(charger)
        connectors = charger.get("connectors") or []
        provider["items"] = [
            _connector_to_item(charger["id"], c, i).model_dump()
            for i, c in enumerate(connectors)
        ]
        providers.append(provider)

    context = create_beckn_context("on_search")
    return {
        "context": context.model_dump(),
        "message": {
            "catalog": {
                "descriptor": {"name": "EV Charger Network"},
                "providers": providers,
            }
        },
    }


# ---------------------------------------------------------------------------
# 2. POST /beckn/select
# ---------------------------------------------------------------------------

@router.post("/beckn/select", dependencies=[Depends(require_beckn_enabled)])
async def beckn_select(
    charger_id: str = Query(...),
    connector_id: str = Query(...),
    _user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Beckn on_select — fetch charger details and quote for a specific connector."""
    charger = get_charger_by_id(charger_id)
    if not charger:
        raise HTTPException(status_code=404, detail="Charger not found")

    # Find the matching connector
    connectors = charger.get("connectors") or []
    connector = next(
        (c for c in connectors if str(c.get("id", "")) == str(connector_id)), None
    )
    if not connector:
        raise HTTPException(status_code=404, detail="Connector not found")

    # Estimate quote for 10 kWh (placeholder until actual session)
    quote = calculate_quote(10.0, charger_id)

    item = _connector_to_item(charger_id, connector, 0)
    fulfillment = BecknFulfillment(
        id=f"fulfillment_{connector_id}",
        type="CHARGING",
        state={"descriptor": {"code": connector.get("status", "AVAILABLE")}},
    )

    order = BecknOrder(
        provider=_charger_to_provider(charger),
        items=[item],
        fulfillments=[fulfillment],
        quote=quote,
        payment=Payment(type=PaymentTypeEnum.POST_PAID, status=PaymentStatusEnum.PENDING),
    )

    context = create_beckn_context("on_select")
    return {
        "context": context.model_dump(),
        "message": {"order": order.model_dump()},
    }


# ---------------------------------------------------------------------------
# 3. POST /beckn/init
# ---------------------------------------------------------------------------

@router.post("/beckn/init", dependencies=[Depends(require_beckn_enabled)])
async def beckn_init(
    charger_id: str = Query(...),
    connector_id: str = Query(...),
    user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Beckn on_init — initialise an order (pre-session confirmation)."""
    charger = get_charger_by_id(charger_id)
    if not charger:
        raise HTTPException(status_code=404, detail="Charger not found")

    connectors = charger.get("connectors") or []
    connector = next(
        (c for c in connectors if str(c.get("id", "")) == str(connector_id)), None
    )
    if not connector:
        raise HTTPException(status_code=404, detail="Connector not found")

    if connector.get("status", "AVAILABLE") != "AVAILABLE":
        raise HTTPException(
            status_code=409,
            detail=f"Connector is not available (status={connector.get('status')})",
        )

    quote = calculate_quote(10.0, charger_id)
    transaction_id = str(uuid.uuid4())

    order = BecknOrder(
        id=transaction_id,
        state="INITIALIZED",
        provider=_charger_to_provider(charger),
        items=[_connector_to_item(charger_id, connector, 0)],
        fulfillments=[
            BecknFulfillment(
                id=f"fulfillment_{connector_id}",
                type="CHARGING",
                state={"descriptor": {"code": "AWAITING_START"}},
            )
        ],
        quote=quote,
        payment=Payment(type=PaymentTypeEnum.POST_PAID, status=PaymentStatusEnum.PENDING),
    )

    context = create_beckn_context("on_init", transaction_id=transaction_id)
    return {
        "context": context.model_dump(),
        "message": {"order": order.model_dump()},
    }


# ---------------------------------------------------------------------------
# 4. POST /qr/validate
# ---------------------------------------------------------------------------

@router.post("/qr/validate", dependencies=[Depends(require_beckn_enabled)])
async def validate_qr(
    body: QRValidationRequest,
    _user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Parse and validate a QR code scanned from a charger, return charger details."""
    try:
        payload = parse_qr_data(body.qr_data)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid QR code: {exc}")

    charger_id = payload.get("charger_id") or payload.get("id")
    if not charger_id:
        raise HTTPException(status_code=400, detail="QR code does not contain a charger ID")

    charger = get_charger_by_id(charger_id)
    if not charger:
        raise HTTPException(status_code=404, detail="Charger not found")

    return {
        "valid": True,
        "charger_id": charger_id,
        "connector_id": payload.get("connector_id"),
        "charger": {
            "id": charger.get("id"),
            "name": charger.get("name"),
            "address": charger.get("address"),
            "connectors": charger.get("connectors", []),
            "latitude": charger.get("latitude"),
            "longitude": charger.get("longitude"),
        },
        "qr_payload": payload,
    }


# ---------------------------------------------------------------------------
# 5. GET /chargers/{charger_id}/qr
# ---------------------------------------------------------------------------

@router.get("/chargers/{charger_id}/qr", dependencies=[Depends(require_beckn_enabled)])
async def get_charger_qr(
    charger_id: str,
    _user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Generate a signed QR code for a charger."""
    charger = get_charger_by_id(charger_id)
    if not charger:
        raise HTTPException(status_code=404, detail="Charger not found")

    charger_data = {
        "charger_id": charger_id,
        "name": charger.get("name", charger_id),
        "latitude": charger.get("latitude"),
        "longitude": charger.get("longitude"),
        "ts": int(datetime.now(timezone.utc).timestamp()),
    }

    qr_string = sign_qr_data(charger_data)
    qr_code_b64 = generate_charger_qr(charger_data)

    return {
        "charger_id": charger_id,
        "qr_code": qr_code_b64,   # base64-encoded PNG (or fallback string)
        "qr_string": qr_string,
    }


# ---------------------------------------------------------------------------
# 6. POST /sessions/start  (Saga pattern)
# ---------------------------------------------------------------------------

@router.post(
    "/sessions/start",
    response_model=SessionResponse,
    dependencies=[Depends(require_beckn_enabled)],
)
async def start_charging_session(
    request: SessionCreateRequest,
    user: dict = Depends(require_auth),
) -> SessionResponse:
    """Start a new charging session using a saga for resilient multi-step execution."""
    user_id = user["user_id"]
    charger_id = request.charger_id
    connector_id = request.connector_id

    # Idempotency check
    if request.idempotency_key:
        idem_key = make_idempotency_key(user_id, request.idempotency_key, None)
        cached = check_idempotency(idem_key, user_id, None)
        if cached:
            logger.info("Idempotency hit for key=%s user=%s", idem_key, user_id)
            return SessionResponse(**cached)

    charger = get_charger_by_id(charger_id)
    if not charger:
        raise HTTPException(status_code=404, detail="Charger not found")

    connectors = charger.get("connectors") or []
    connector = next(
        (c for c in connectors if str(c.get("id", "")) == str(connector_id)), None
    )
    if not connector:
        raise HTTPException(status_code=404, detail="Connector not found")

    if connector.get("status", "AVAILABLE") != "AVAILABLE":
        raise HTTPException(
            status_code=409,
            detail=f"Connector is not available (status={connector.get('status')})",
        )

    session_id = str(uuid.uuid4())
    context: Dict[str, Any] = {
        "session_id": session_id,
        "user_id": user_id,
        "charger_id": charger_id,
        "connector_id": connector_id,
        "lock_held": False,
        "session_inserted": False,
        "ocpp_started": False,
    }

    # ------------------------------------------------------------------
    # Saga step definitions
    # ------------------------------------------------------------------

    async def acquire_lock(ctx: Dict[str, Any]) -> None:
        """Step 1: acquire distributed lock for the connector."""
        # We can't hold the context manager across steps easily, so we
        # just record the intent; the actual lock is acquired inline below.
        ctx["lock_held"] = True

    async def release_lock(ctx: Dict[str, Any]) -> None:
        """Compensation 1: mark lock as released (lock is managed separately)."""
        ctx["lock_held"] = False

    async def insert_session(ctx: Dict[str, Any]) -> None:
        """Step 2: insert charging session record into Supabase."""
        if not supabase:
            raise RuntimeError("Supabase not configured")
        now = datetime.now(timezone.utc).isoformat()
        row = {
            "id": ctx["session_id"],
            "user_id": ctx["user_id"],
            "charger_id": ctx["charger_id"],
            "connector_id": ctx["connector_id"],
            "state": SessionStateEnum.STARTING.value,
            "energy_kwh": 0.0,
            "duration_seconds": 0,
            "amount_inr": 0.0,
            "started_at": now,
            "payment_status": PaymentStatusEnum.PENDING.value,
            "metadata": {
                "vehicle_id": request.vehicle_id,
                "payment_type": request.payment_type.value,
            },
            "created_at": now,
            "updated_at": now,
        }
        supabase.table("charging_sessions").insert(row).execute()
        ctx["session_inserted"] = True

    async def delete_session(ctx: Dict[str, Any]) -> None:
        """Compensation 2: delete the session record if OCPP fails."""
        if ctx.get("session_inserted") and supabase:
            try:
                supabase.table("charging_sessions").delete().eq(
                    "id", ctx["session_id"]
                ).execute()
            except Exception as exc:
                logger.error("Failed to delete session %s during compensation: %s", ctx["session_id"], exc)
        ctx["session_inserted"] = False

    async def start_ocpp(ctx: Dict[str, Any]) -> None:
        """Step 3: send RemoteStartTransaction via OCPP."""
        manager = OCPPManager(ctx["charger_id"])
        accepted = await manager.start_charging(ctx["connector_id"])
        ctx["ocpp_started"] = accepted
        if not accepted:
            raise RuntimeError("OCPP charger rejected the start request")

    async def stop_ocpp(ctx: Dict[str, Any]) -> None:
        """Compensation 3: stop OCPP if session was started but something else failed."""
        if ctx.get("ocpp_started"):
            try:
                manager = OCPPManager(ctx["charger_id"])
                await manager.stop_charging(ctx["connector_id"])
            except Exception as exc:
                logger.error("OCPP compensation stop failed: %s", exc)
        ctx["ocpp_started"] = False

    # ------------------------------------------------------------------
    # Execute saga inside the distributed lock
    # ------------------------------------------------------------------

    try:
        async with charger_lock(charger_id, connector_id, timeout_seconds=15):
            saga = Saga()
            saga.add_step(SagaStep("acquire_lock", acquire_lock, release_lock))
            saga.add_step(SagaStep("insert_session", insert_session, delete_session))
            saga.add_step(SagaStep("start_ocpp", start_ocpp, stop_ocpp))

            await saga.execute(context)

    except LockAcquisitionError:
        raise HTTPException(
            status_code=409,
            detail="Connector is currently busy — please try again shortly",
        )
    except Exception as exc:
        logger.error("start_charging_session saga failed: %s", exc)
        raise HTTPException(status_code=500, detail=f"Failed to start session: {exc}")

    # Update session state to CHARGING after OCPP accepted
    if supabase and context.get("session_inserted"):
        try:
            supabase.table("charging_sessions").update(
                {"state": SessionStateEnum.CHARGING.value, "updated_at": datetime.now(timezone.utc).isoformat()}
            ).eq("id", session_id).execute()
        except Exception as exc:
            logger.error("Failed to update session state to CHARGING: %s", exc)

    started_at = datetime.now(timezone.utc)
    result = SessionResponse(
        session_id=session_id,
        state=SessionStateEnum.CHARGING,
        charger_id=charger_id,
        connector_id=connector_id,
        started_at=started_at,
        message="Charging session started",
        ocpp_accepted=context.get("ocpp_started", False),
    )

    # Store idempotency response
    if request.idempotency_key:
        store_idempotency_response(
            idem_key, user_id, None, result.model_dump(mode="json")
        )

    return result


# ---------------------------------------------------------------------------
# 7. GET /sessions/{session_id}/status
# ---------------------------------------------------------------------------

@router.get(
    "/sessions/{session_id}/status",
    dependencies=[Depends(require_beckn_enabled)],
)
async def get_session_status(
    session_id: str,
    user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Return Beckn on_status response with live meter tags."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        resp = (
            supabase.table("charging_sessions")
            .select("*")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        session = resp.data if resp else None
    except Exception as exc:
        logger.error("get_session_status DB query failed: session=%s %s", session_id, exc)
        raise HTTPException(status_code=500, detail="Failed to fetch session")

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # Auth check: only owner can view
    if session.get("user_id") != user["user_id"]:
        raise HTTPException(status_code=403, detail="Not authorised to view this session")

    charger_id = session.get("charger_id", "")
    connector_id = session.get("connector_id", "")

    # Fetch live metrics with circuit breaker
    live_metrics: Dict[str, Any] = {
        "energy": session.get("energy_kwh", 0.0),
        "current": 0.0,
        "voltage": 0.0,
        "power": 0.0,
        "soc": None,
        "temperature": None,
    }
    try:
        breaker = await get_charger_breaker(charger_id)
        manager = OCPPManager(charger_id)
        live_metrics = await breaker.call(manager.get_live_metrics)
    except CircuitOpenError:
        logger.warning("Circuit breaker OPEN for charger=%s — using cached metrics", charger_id)
    except Exception as exc:
        logger.error("get_live_metrics failed for charger=%s: %s", charger_id, exc)

    # Persist meter reading
    now = datetime.now(timezone.utc)
    meter = MeterReading(
        session_id=session_id,
        energy_kwh=float(live_metrics.get("energy", 0.0)),
        current_a=float(live_metrics.get("current", 0.0)),
        voltage_v=float(live_metrics.get("voltage", 0.0)),
        power_kw=float(live_metrics.get("power", 0.0)),
        soc_percent=live_metrics.get("soc"),
        temperature_c=live_metrics.get("temperature"),
        timestamp=now,
    )

    if supabase:
        try:
            supabase.table("meter_readings").insert(
                {
                    "session_id": session_id,
                    "energy_kwh": meter.energy_kwh,
                    "current_a": meter.current_a,
                    "voltage_v": meter.voltage_v,
                    "power_kw": meter.power_kw,
                    "soc_percent": meter.soc_percent,
                    "temperature_c": meter.temperature_c,
                    "recorded_at": now.isoformat(),
                }
            ).execute()
        except Exception as exc:
            logger.error("meter_readings insert failed: session=%s %s", session_id, exc)

    meter_tags = [t.model_dump() for t in meter.to_meter_tags()]
    charger = get_charger_by_id(charger_id)

    fulfillment = BecknFulfillment(
        id=f"fulfillment_{connector_id}",
        type="CHARGING",
        state={"descriptor": {"code": session.get("state", "CHARGING")}},
        tags=meter.to_meter_tags(),
    )

    order = BecknOrder(
        id=session_id,
        state=session.get("state", "CHARGING"),
        provider=_charger_to_provider(charger) if charger else {"id": charger_id, "descriptor": {"name": charger_id}},
        fulfillments=[fulfillment],
    )

    context = create_beckn_context("on_status", transaction_id=session_id)
    return {
        "context": context.model_dump(),
        "message": {
            "order": order.model_dump(),
            "meter_tags": meter_tags,
        },
    }


# ---------------------------------------------------------------------------
# 8. POST /sessions/{session_id}/end
# ---------------------------------------------------------------------------

@router.post(
    "/sessions/{session_id}/end",
    dependencies=[Depends(require_beckn_enabled)],
)
async def end_charging_session(
    session_id: str,
    user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Stop charging and return a Beckn on_update response with UPI payment link."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        resp = (
            supabase.table("charging_sessions")
            .select("*")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        session = resp.data if resp else None
    except Exception as exc:
        logger.error("end_charging_session DB query: session=%s %s", session_id, exc)
        raise HTTPException(status_code=500, detail="Failed to fetch session")

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.get("user_id") != user["user_id"]:
        raise HTTPException(status_code=403, detail="Not authorised to end this session")

    current_state = SessionStateEnum(session.get("state", SessionStateEnum.CHARGING.value))
    if current_state not in {SessionStateEnum.CHARGING, SessionStateEnum.STARTING}:
        raise HTTPException(
            status_code=409,
            detail=f"Session cannot be stopped from state {current_state.value}",
        )

    charger_id = session.get("charger_id", "")
    connector_id = session.get("connector_id", "")

    # Stop OCPP
    manager = OCPPManager(charger_id)
    try:
        await manager.stop_charging(connector_id)
    except Exception as exc:
        logger.error("OCPP stop_charging failed: session=%s %s", session_id, exc)

    # Get final meter reading
    final_metrics: Dict[str, Any] = {"energy": session.get("energy_kwh", 0.0)}
    try:
        breaker = await get_charger_breaker(charger_id)
        final_metrics = await breaker.call(manager.get_live_metrics)
    except Exception as exc:
        logger.error("Final meter read failed: session=%s %s", session_id, exc)

    energy_kwh = float(final_metrics.get("energy", session.get("energy_kwh", 0.0)))
    quote = calculate_quote(energy_kwh, charger_id)
    total_amount = float(quote.price.value)

    # Compute duration
    now = datetime.now(timezone.utc)
    started_at = session.get("started_at")
    duration_seconds = 0
    if started_at:
        try:
            started_dt = datetime.fromisoformat(str(started_at).replace("Z", "+00:00"))
            duration_seconds = max(0, int((now - started_dt).total_seconds()))
        except Exception:
            pass

    # Generate UPI collect link
    phone = user.get("metadata", {}).get("phone", "")
    reference_id = str(uuid.uuid4())
    upi_link = await _payment_service.create_upi_collect(
        phone=phone,
        amount=total_amount,
        description=f"EV Charging Session {session_id[:8]}",
        reference_id=reference_id,
    )

    # Update session in DB
    if supabase:
        try:
            supabase.table("charging_sessions").update(
                {
                    "state": SessionStateEnum.AWAITING_PAYMENT.value,
                    "energy_kwh": energy_kwh,
                    "duration_seconds": duration_seconds,
                    "amount_inr": total_amount,
                    "ended_at": now.isoformat(),
                    "transaction_id": reference_id,
                    "updated_at": now.isoformat(),
                }
            ).eq("id", session_id).execute()
        except Exception as exc:
            logger.error("Session end DB update failed: session=%s %s", session_id, exc)

    # Notify WebSocket subscribers
    await ws_manager.broadcast_session_end(
        session_id,
        {
            "session_id": session_id,
            "state": SessionStateEnum.AWAITING_PAYMENT.value,
            "energy_kwh": energy_kwh,
            "amount_inr": total_amount,
            "upi_link": upi_link,
        },
    )

    charger = get_charger_by_id(charger_id)
    order = BecknOrder(
        id=session_id,
        state=SessionStateEnum.AWAITING_PAYMENT.value,
        provider=_charger_to_provider(charger) if charger else {"id": charger_id, "descriptor": {"name": charger_id}},
        fulfillments=[
            BecknFulfillment(
                id=f"fulfillment_{connector_id}",
                type="CHARGING",
                state={"descriptor": {"code": SessionStateEnum.AWAITING_PAYMENT.value}},
                end={"time": {"timestamp": now.isoformat()}},
            )
        ],
        quote=quote,
        payment=Payment(
            type=PaymentTypeEnum.POST_PAID,
            status=PaymentStatusEnum.PENDING,
            amount=Price(currency="INR", value=str(total_amount)),
            transaction_id=reference_id,
            upi_link=upi_link,
        ),
    )

    context = create_beckn_context("on_update", transaction_id=session_id)
    return {
        "context": context.model_dump(),
        "message": {"order": order.model_dump()},
    }


# ---------------------------------------------------------------------------
# 9. POST /payments/{session_id}/confirm
# ---------------------------------------------------------------------------

@router.post(
    "/payments/{session_id}/confirm",
    dependencies=[Depends(require_beckn_enabled)],
)
async def confirm_payment(
    session_id: str,
    reference_id: str = Query(..., description="UPI transaction reference ID"),
    user: dict = Depends(require_auth),
) -> Dict[str, Any]:
    """Verify UPI payment and unlock the connector if payment is confirmed."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        resp = (
            supabase.table("charging_sessions")
            .select("*")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        session = resp.data if resp else None
    except Exception as exc:
        logger.error("confirm_payment DB query: session=%s %s", session_id, exc)
        raise HTTPException(status_code=500, detail="Failed to fetch session")

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.get("user_id") != user["user_id"]:
        raise HTTPException(status_code=403, detail="Not authorised")

    # Verify payment
    payment_status = await _payment_service.verify_payment(reference_id)

    unlock_status = False
    new_state = SessionStateEnum.AWAITING_PAYMENT

    if payment_status == "COLLECTED":
        new_state = SessionStateEnum.PAYMENT_CONFIRMED

        # Unlock connector
        charger_id = session.get("charger_id", "")
        connector_id = session.get("connector_id", "")
        manager = OCPPManager(charger_id)
        try:
            unlock_status = await manager.unlock_connector(connector_id)
        except Exception as exc:
            logger.error("unlock_connector failed: session=%s %s", session_id, exc)

        final_state = SessionStateEnum.COMPLETED if unlock_status else SessionStateEnum.UNLOCKING

        # Update session
        if supabase:
            try:
                supabase.table("charging_sessions").update(
                    {
                        "state": final_state.value,
                        "payment_status": PaymentStatusEnum.COLLECTED.value,
                        "transaction_id": reference_id,
                        "updated_at": datetime.now(timezone.utc).isoformat(),
                    }
                ).eq("id", session_id).execute()
            except Exception as exc:
                logger.error("confirm_payment DB update failed: session=%s %s", session_id, exc)

        new_state = final_state
        message = "Payment confirmed. Session completed."
    elif payment_status == "FAILED":
        message = "Payment failed. Please retry."
    else:
        message = "Payment pending. Please complete UPI payment."

    return {
        "status": payment_status,
        "message": message,
        "unlock_status": unlock_status,
        "session_state": new_state.value,
    }


# ---------------------------------------------------------------------------
# 10. GET /feature-flags  (NO auth, NO feature flag gate)
# ---------------------------------------------------------------------------

@router.get("/feature-flags")
async def get_feature_flags() -> Dict[str, Any]:
    """Return enabled feature flags — always available regardless of flag state."""
    return {
        "beckn_charging": settings.BECKN_CHARGING_ENABLED,
        "qr_scanner": settings.BECKN_CHARGING_ENABLED,
        "reservations": False,
    }


# ---------------------------------------------------------------------------
# 11. WebSocket /ws/session/{session_id}
# ---------------------------------------------------------------------------

@router.websocket("/ws/session/{session_id}")
async def websocket_session(
    websocket: WebSocket,
    session_id: str,
) -> None:
    """Live meter updates over WebSocket.

    First message must be a JSON auth payload:
        {"token": "<bearer-token>"}

    Subsequent messages from the server are:
        {"type": "meter_update", "data": {...}}
        {"type": "session_end", "data": {...}}
    """
    # Feature-flag check
    if not settings.BECKN_CHARGING_ENABLED:
        await websocket.accept()
        await websocket.send_text(
            json.dumps({"error": "Feature not available"})
        )
        await websocket.close(code=4040)
        return

    # Wait for auth message
    await websocket.accept()
    try:
        raw_auth = await asyncio.wait_for(websocket.receive_text(), timeout=10.0)
        auth_msg = json.loads(raw_auth)
        token = auth_msg.get("token", "")
        if not token:
            await websocket.send_text(json.dumps({"error": "Missing auth token"}))
            await websocket.close(code=4001)
            return
    except asyncio.TimeoutError:
        await websocket.send_text(json.dumps({"error": "Auth timeout"}))
        await websocket.close(code=4001)
        return
    except Exception as exc:
        await websocket.send_text(json.dumps({"error": f"Auth error: {exc}"}))
        await websocket.close(code=4001)
        return

    # Validate token via Supabase
    user_id: Optional[str] = None
    if supabase:
        try:
            auth_resp = supabase.auth.get_user(token)
            if auth_resp and auth_resp.user:
                user_id = auth_resp.user.id
        except Exception as exc:
            logger.warning("WebSocket auth token invalid: %s", exc)

    if not user_id:
        await websocket.send_text(json.dumps({"error": "Invalid or expired token"}))
        await websocket.close(code=4001)
        return

    # Verify session ownership
    session: Optional[Dict[str, Any]] = None
    if supabase:
        try:
            resp = (
                supabase.table("charging_sessions")
                .select("user_id, charger_id, connector_id, state")
                .eq("id", session_id)
                .maybe_single()
                .execute()
            )
            session = resp.data if resp else None
        except Exception as exc:
            logger.error("WebSocket session lookup failed: session=%s %s", session_id, exc)

    if not session:
        await websocket.send_text(json.dumps({"error": "Session not found"}))
        await websocket.close(code=4004)
        return

    if session.get("user_id") != user_id:
        await websocket.send_text(json.dumps({"error": "Not authorised"}))
        await websocket.close(code=4003)
        return

    # Register connection (already accepted above — use a non-accepting path)
    # ws_manager.connect calls accept(), so we need to re-use the connection directly
    async with _ws_session_scope(session_id, websocket, user_id):
        await websocket.send_text(
            json.dumps({"type": "connected", "session_id": session_id})
        )
        logger.info("WebSocket session scope active: session=%s user=%s", session_id, user_id)

        charger_id = session.get("charger_id", "")
        connector_id = session.get("connector_id", "")
        manager = OCPPManager(charger_id)

        try:
            while True:
                # Poll live metrics every 5 seconds
                await asyncio.sleep(5)

                # Re-fetch session state to detect termination
                if supabase:
                    try:
                        sr = (
                            supabase.table("charging_sessions")
                            .select("state")
                            .eq("id", session_id)
                            .maybe_single()
                            .execute()
                        )
                        current_state = (sr.data or {}).get("state", "CHARGING")
                    except Exception:
                        current_state = "CHARGING"
                else:
                    current_state = "CHARGING"

                if current_state not in {
                    SessionStateEnum.CHARGING.value,
                    SessionStateEnum.STARTING.value,
                }:
                    # Session ended — final broadcast already handled by /end endpoint
                    break

                # Fetch live metrics
                try:
                    breaker = await get_charger_breaker(charger_id)
                    metrics = await breaker.call(manager.get_live_metrics)
                except CircuitOpenError:
                    metrics = {"energy": 0.0, "current": 0.0, "voltage": 0.0, "power": 0.0}
                except Exception as exc:
                    logger.error("WS metrics fetch failed: session=%s %s", session_id, exc)
                    metrics = {"energy": 0.0, "current": 0.0, "voltage": 0.0, "power": 0.0}

                await ws_manager.broadcast_meter_update(session_id, metrics)

        except WebSocketDisconnect:
            logger.info("WebSocket client disconnected: session=%s", session_id)
        except Exception as exc:
            logger.error("WebSocket error: session=%s %s", session_id, exc)


from contextlib import asynccontextmanager


@asynccontextmanager
async def _ws_session_scope(session_id: str, websocket: WebSocket, user_id: str):
    """Register WebSocket without calling accept() again (already accepted above)."""
    async with ws_manager._lock:
        ws_manager._connections[session_id].append(
            {"ws": websocket, "user_id": user_id}
        )
    logger.info(
        "WebSocket registered (manual): session=%s user=%s total=%d",
        session_id,
        user_id,
        len(ws_manager._connections[session_id]),
    )
    try:
        yield
    finally:
        ws_manager.disconnect(session_id, websocket)
