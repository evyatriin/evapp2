"""Pydantic models for Beckn EV charging integration."""
from __future__ import annotations

import logging
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class PaymentTypeEnum(str, Enum):
    PRE_PAID = "PRE-PAID"
    POST_PAID = "POST-PAID"
    ON_FULFILLMENT = "ON-FULFILLMENT"


class ConnectorTypeEnum(str, Enum):
    CCS2 = "CCS2"
    CHAdeMO = "CHAdeMO"
    TYPE2_AC = "TYPE2_AC"
    BHARAT_AC = "BHARAT_AC_001"
    BHARAT_DC = "BHARAT_DC_001"
    GB_T = "GB/T"
    TYPE1 = "TYPE1"


class ChargerTypeEnum(str, Enum):
    AC_SLOW = "AC_SLOW"
    AC_FAST = "AC_FAST"
    DC_FAST = "DC_FAST"
    DC_RAPID = "DC_RAPID"


class SessionStateEnum(str, Enum):
    INITIATED = "INITIATED"
    AUTHORIZING = "AUTHORIZING"
    AUTHORIZED = "AUTHORIZED"
    STARTING = "STARTING"
    CHARGING = "CHARGING"
    STOPPING = "STOPPING"
    METERING_FINAL = "METERING_FINAL"
    AWAITING_PAYMENT = "AWAITING_PAYMENT"
    PAYMENT_CONFIRMED = "PAYMENT_CONFIRMED"
    UNLOCKING = "UNLOCKING"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"
    DISPUTED = "DISPUTED"


class PaymentStatusEnum(str, Enum):
    PENDING = "PENDING"
    COLLECTED = "COLLECTED"
    FAILED = "FAILED"
    REFUNDED = "REFUNDED"
    DISPUTED = "DISPUTED"


# ---------------------------------------------------------------------------
# Pricing / Quote models
# ---------------------------------------------------------------------------

class Price(BaseModel):
    currency: str = "INR"
    value: str  # string representation of decimal amount


class QuoteBreakup(BaseModel):
    title: str
    price: Price


class Quote(BaseModel):
    price: Price
    breakup: List[QuoteBreakup] = Field(default_factory=list)
    ttl: str = "PT30M"  # ISO 8601 duration


# ---------------------------------------------------------------------------
# Payment models
# ---------------------------------------------------------------------------

class Payment(BaseModel):
    type: PaymentTypeEnum = PaymentTypeEnum.POST_PAID
    status: PaymentStatusEnum = PaymentStatusEnum.PENDING
    amount: Optional[Price] = None
    transaction_id: Optional[str] = None
    upi_link: Optional[str] = None
    collected_by: str = "BAP"
    uri: Optional[str] = None


class PaymentTransaction(BaseModel):
    id: str
    session_id: str
    user_id: str
    amount: float
    currency: str = "INR"
    status: PaymentStatusEnum = PaymentStatusEnum.PENDING
    reference_id: Optional[str] = None
    upi_link: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Connector / Charger models
# ---------------------------------------------------------------------------

class Connector(BaseModel):
    id: str
    type: ConnectorTypeEnum
    power_kw: float
    charger_type: ChargerTypeEnum
    status: str = "AVAILABLE"  # AVAILABLE | OCCUPIED | FAULTED | UNAVAILABLE
    price_per_kwh: float = 0.0
    price_per_min: Optional[float] = None


class ConnectorLocation(BaseModel):
    lat: float
    lng: float
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None


class ChargerDescriptor(BaseModel):
    name: str
    short_desc: Optional[str] = None
    long_desc: Optional[str] = None
    images: List[str] = Field(default_factory=list)
    operator: Optional[str] = None


class Charger(BaseModel):
    id: str
    descriptor: ChargerDescriptor
    location: ConnectorLocation
    connectors: List[Connector] = Field(default_factory=list)
    tags: Dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class ChargerProvider(BaseModel):
    id: str
    descriptor: ChargerDescriptor
    chargers: List[Charger] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Meter reading models
# ---------------------------------------------------------------------------

class MeterTag(BaseModel):
    descriptor: Dict[str, str]  # {"code": "...", "name": "..."}
    value: str
    display: bool = True


class MeterReading(BaseModel):
    session_id: str
    energy_kwh: float = 0.0
    current_a: float = 0.0
    voltage_v: float = 0.0
    power_kw: float = 0.0
    soc_percent: Optional[float] = None
    temperature_c: Optional[float] = None
    timestamp: Optional[datetime] = None

    def to_meter_tags(self) -> List[MeterTag]:
        """Convert meter reading into Beckn-style MeterTag list."""
        tags: List[MeterTag] = [
            MeterTag(
                descriptor={"code": "energy", "name": "Energy Delivered"},
                value=f"{self.energy_kwh:.3f} kWh",
            ),
            MeterTag(
                descriptor={"code": "current", "name": "Current"},
                value=f"{self.current_a:.2f} A",
            ),
            MeterTag(
                descriptor={"code": "voltage", "name": "Voltage"},
                value=f"{self.voltage_v:.1f} V",
            ),
            MeterTag(
                descriptor={"code": "power", "name": "Power"},
                value=f"{self.power_kw:.2f} kW",
            ),
        ]
        if self.soc_percent is not None:
            tags.append(
                MeterTag(
                    descriptor={"code": "soc", "name": "State of Charge"},
                    value=f"{self.soc_percent:.1f}%",
                )
            )
        if self.temperature_c is not None:
            tags.append(
                MeterTag(
                    descriptor={"code": "temperature", "name": "Temperature"},
                    value=f"{self.temperature_c:.1f} °C",
                )
            )
        if self.timestamp:
            tags.append(
                MeterTag(
                    descriptor={"code": "timestamp", "name": "Reading Time"},
                    value=self.timestamp.isoformat(),
                    display=False,
                )
            )
        return tags


# ---------------------------------------------------------------------------
# Session models
# ---------------------------------------------------------------------------

class ChargingSession(BaseModel):
    id: str
    user_id: str
    charger_id: str
    connector_id: str
    state: SessionStateEnum = SessionStateEnum.INITIATED
    energy_kwh: float = 0.0
    duration_seconds: int = 0
    amount_inr: float = 0.0
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    payment_status: PaymentStatusEnum = PaymentStatusEnum.PENDING
    transaction_id: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class SessionCreateRequest(BaseModel):
    charger_id: str
    connector_id: str
    vehicle_id: Optional[str] = None
    expected_energy_kwh: Optional[float] = None
    payment_type: PaymentTypeEnum = PaymentTypeEnum.POST_PAID
    idempotency_key: Optional[str] = None


class SessionResponse(BaseModel):
    session_id: str
    state: SessionStateEnum
    charger_id: str
    connector_id: str
    started_at: Optional[datetime] = None
    message: str = ""
    ocpp_accepted: bool = False


# ---------------------------------------------------------------------------
# Beckn protocol envelope models
# ---------------------------------------------------------------------------

class BecknContext(BaseModel):
    domain: str = "nic2004:85159"
    country: str = "IND"
    city: str = "std:080"
    action: str
    core_version: str = "1.1.0"
    bap_id: str = "ev-router-app"
    bap_uri: str = "https://ev-router.app"
    bpp_id: Optional[str] = "ev-router-bpp"
    bpp_uri: Optional[str] = None
    transaction_id: str
    message_id: str
    timestamp: str
    ttl: str = "PT30S"


class BecknItem(BaseModel):
    id: str
    descriptor: Dict[str, Any]
    price: Price
    fulfillment_id: str
    tags: List[Dict[str, Any]] = Field(default_factory=list)
    quantity: Optional[Dict[str, Any]] = None


class BecknFulfillment(BaseModel):
    id: str
    type: str = "CHARGING"
    state: Optional[Dict[str, Any]] = None
    start: Optional[Dict[str, Any]] = None
    end: Optional[Dict[str, Any]] = None
    tags: List[MeterTag] = Field(default_factory=list)
    agent: Optional[Dict[str, Any]] = None


class BecknOrder(BaseModel):
    id: Optional[str] = None
    state: Optional[str] = None
    provider: Dict[str, Any]
    items: List[BecknItem] = Field(default_factory=list)
    fulfillments: List[BecknFulfillment] = Field(default_factory=list)
    quote: Optional[Quote] = None
    payment: Optional[Payment] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class BecknResponse(BaseModel):
    context: BecknContext
    message: Dict[str, Any]


# ---------------------------------------------------------------------------
# QR models
# ---------------------------------------------------------------------------

class QRValidationRequest(BaseModel):
    qr_data: str = Field(..., description="Raw QR code string scanned from the charger")
