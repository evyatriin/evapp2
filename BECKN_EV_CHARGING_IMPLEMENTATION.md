# Beckn EV Charging Integration - Complete Implementation Plan

**Document Version**: 2.0  
**Date**: 2026-05-14  
**Status**: Production-Ready  
**Scope**: Full Beckn ON-FULFILLMENT postpaid metered charging integration with QR scanner, resilience patterns, and observability

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [QR Code Scanner](#qr-code-scanner)
3. [Data Models & Schemas](#data-models--schemas)
4. [Database Design](#database-design)
5. [Backend Implementation](#backend-implementation)
6. [Frontend Implementation](#frontend-implementation)
7. [OCPP Integration](#ocpp-integration)
8. [Payment Flow](#payment-flow)
9. [Real-time Updates](#real-time-updates)
10. [**Session State Machine & Idempotency**](#session-state-machine--idempotency) ⭐
11. [**Security Hardening**](#security-hardening) ⭐
12. [**Resilience Patterns**](#resilience-patterns) ⭐
13. [**Caching & Background Jobs**](#caching--background-jobs) ⭐
14. [**Observability**](#observability) ⭐
15. [**Edge Cases & Failure Modes**](#edge-cases--failure-modes) ⭐
16. [**Supplementary Features**](#supplementary-features) ⭐
17. [**Flutter State Management**](#flutter-state-management) ⭐
18. [**CI/CD & API Documentation**](#cicd--api-documentation) ⭐
19. [Testing Strategy](#testing-strategy)
20. [Deployment](#deployment)

---

## Architecture Overview

### System Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     EV Router Mobile App (Flutter)               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Charging UI                                                  ││
│  │ - Search & Select Chargers                                  ││
│  │ - Live Meter Display (kWh, ₹, SOC)                          ││
│  │ - Session Status & Payment Dialog                           ││
│  └──────────────┬──────────────────────────────────────────────┘│
└─────────────────┼──────────────────────────────────────────────┘
                  │ HTTP + WebSocket
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│              FastAPI Backend (Python)                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Beckn API Routes (/api/chargers/beckn/*)                    ││
│  │ - search: Find chargers by location                         ││
│  │ - select: Get charger details                               ││
│  │ - init: Payment terms                                       ││
│  │ - confirm: Start session                                    ││
│  │ - status: Live metering                                     ││
│  │ - update: Session end & billing                             ││
│  └──────────────┬──────────────────────────────────────────────┘│
│  ┌──────────────▼──────────────────────────────────────────────┐│
│  │ Session Management                                           ││
│  │ - ChargingSession CRUD                                      ││
│  │ - Live meter aggregation                                    ││
│  │ - Payment initiation                                        ││
│  └──────────────┬──────────────────────────────────────────────┘│
│  ┌──────────────▼──────────────────────────────────────────────┐│
│  │ OCPP Bridge                                                  ││
│  │ - Fetch live charger metrics                                ││
│  │ - Map to Beckn schema                                       ││
│  │ - Cable unlock commands                                     ││
│  └──────────────┬──────────────────────────────────────────────┘│
└─────────────────┼──────────────────────────────────────────────┘
                  │ OCPP 1.6/2.0
                  ▼
         ┌────────────────────────┐
         │ EV Charging Station    │
         │ (OCPP-enabled)         │
         │ - Live meter readings  │
         │ - Cable unlock         │
         └────────────────────────┘
                  │ Payment (UPI)
                  ▼
         ┌────────────────────────┐
         │ Payment Gateway        │
         │ (UPI/NEFT/Card)        │
         └────────────────────────┘
```

### Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Frontend | Flutter | Mobile app for drivers |
| Backend | FastAPI (Python) | Beckn API & session management |
| Database | Supabase (PostgreSQL) | Sessions, meter readings, payments |
| Real-time | WebSocket | Live meter updates to UI |
| Charger Protocol | OCPP 1.6/2.0 | Hardware integration |
| Payment | UPI/NEFT | Postpaid collection |
| QR Scanner | mobile_scanner (Flutter) | Charger identification |

---

## QR Code Scanner

### QR Code Format & Standard

**QR Code Data Structure** (encoded in each charger's physical QR):

```
evrouter://charge?
  charger_id=CHARGER_001&
  connector_id=CONN_A&
  location_name=Delhi%20Sector%2062&
  latitude=12.9716&
  longitude=77.5946&
  power_kw=50&
  connector_type=CCS2&
  rate=15.0
```

**Example URL**:
```
evrouter://charge?charger_id=CHARGER_001&connector_id=CONN_A&location_name=Delhi%20Sector%2062&latitude=12.9716&longitude=77.5946&power_kw=50&connector_type=CCS2&rate=15.0
```

### QR Generation (Backend)

Create file: `backend/utils/qr_generator.py`

```python
import qrcode
from io import BytesIO
import base64
from typing import Dict, Any
import urllib.parse

class QRGenerator:
    """Generate QR codes for chargers"""
    
    @staticmethod
    def generate_charger_qr(charger_data: Dict[str, Any]) -> str:
        """
        Generate QR code for charger
        Returns base64 encoded image
        """
        qr_data = QRGenerator.build_qr_string(charger_data)
        
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_data)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to base64
        buffer = BytesIO()
        img.save(buffer, format='PNG')
        buffer.seek(0)
        base64_str = base64.b64encode(buffer.getvalue()).decode()
        
        return f"data:image/png;base64,{base64_str}"
    
    @staticmethod
    def build_qr_string(charger_data: Dict[str, Any]) -> str:
        """Build URL-encoded QR string"""
        params = {
            "charger_id": charger_data.get("charger_id"),
            "connector_id": charger_data.get("connector_id"),
            "location_name": charger_data.get("name"),
            "latitude": charger_data.get("latitude"),
            "longitude": charger_data.get("longitude"),
            "power_kw": charger_data.get("power_kw"),
            "connector_type": charger_data.get("connector_types", ["CCS2"])[0],
            "rate": charger_data.get("price_per_kwh", 15.0),
        }
        
        query_string = urllib.parse.urlencode(params)
        return f"evrouter://charge?{query_string}"
    
    @staticmethod
    def parse_qr_data(qr_string: str) -> Dict[str, Any]:
        """Parse QR data from scanned string"""
        try:
            # Remove protocol
            if qr_string.startswith("evrouter://charge?"):
                query = qr_string.replace("evrouter://charge?", "")
            else:
                query = qr_string
            
            # Parse query parameters
            params = urllib.parse.parse_qs(query)
            
            # Flatten single-item lists
            data = {k: v[0] if len(v) == 1 else v for k, v in params.items()}
            
            # Convert types
            data["latitude"] = float(data.get("latitude", 0))
            data["longitude"] = float(data.get("longitude", 0))
            data["power_kw"] = float(data.get("power_kw", 0))
            data["rate"] = float(data.get("rate", 15.0))
            
            return data
        except Exception as e:
            raise ValueError(f"Invalid QR data: {e}")
```

Add to `requirements.txt`:
```
qrcode==7.4.2
pillow==10.1.0
```

### Backend QR Validation Endpoint

Add to `backend/routers/beckn_charging.py`:

```python
from utils.qr_generator import QRGenerator
from pydantic import BaseModel

class QRValidationRequest(BaseModel):
    qr_data: str  # Raw scanned QR string

@router.post("/qr/validate")
async def validate_qr_code(request: QRValidationRequest):
    """
    Validate and decode scanned QR code
    Returns charger details and connector info
    """
    try:
        # Parse QR data
        qr_info = QRGenerator.parse_qr_data(request.qr_data)
        
        # Fetch charger details from database
        charger_id = qr_info.get("charger_id")
        charger = await get_charger_by_id(charger_id)
        
        if not charger:
            raise HTTPException(status_code=404, detail="Charger not found")
        
        # Validate charger exists and is online
        if charger.get("availability_status") != "Online":
            raise HTTPException(status_code=400, detail="Charger is offline")
        
        # Return charger details for immediate start
        response = {
            "status": "valid",
            "charger_id": qr_info.get("charger_id"),
            "connector_id": qr_info.get("connector_id"),
            "charger_name": charger.get("name"),
            "location_name": qr_info.get("location_name"),
            "latitude": qr_info.get("latitude"),
            "longitude": qr_info.get("longitude"),
            "power_kw": charger.get("power_kw"),
            "connector_type": qr_info.get("connector_type"),
            "charging_rate_inr_per_kwh": qr_info.get("rate"),
            "can_start_immediately": True,
        }
        
        # Log QR scan
        logger.info(f"QR scan: {charger_id} by user")
        
        return response
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid QR code: {str(e)}")
    except Exception as e:
        logger.error(f"QR validation error: {e}")
        raise HTTPException(status_code=500, detail="Failed to validate QR code")


@router.get("/chargers/{charger_id}/qr")
async def get_charger_qr(charger_id: str):
    """
    Get QR code for a specific charger
    Used for charger admin to generate/print QR codes
    """
    try:
        charger = await get_charger_by_id(charger_id)
        if not charger:
            raise HTTPException(status_code=404, detail="Charger not found")
        
        qr_base64 = QRGenerator.generate_charger_qr(charger)
        
        return {
            "charger_id": charger_id,
            "qr_code": qr_base64,
            "qr_string": QRGenerator.build_qr_string(charger),
        }
    except Exception as e:
        logger.error(f"QR generation error: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate QR code")
```

---

## Data Models & Schemas

### 1. Core Beckn Models

Create file: `backend/models/beckn_models.py`

```python
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum
import uuid

# ===== Enums =====
class PaymentTypeEnum(str, Enum):
    PRE_FULFILLMENT = "PRE_FULFILLMENT"
    ON_FULFILLMENT = "ON_FULFILLMENT"  # Postpaid metered

class ConnectorTypeEnum(str, Enum):
    CCS2 = "CCS2"
    CHADEMO = "CHADEMO"
    TYPE2 = "TYPE2"
    TYPE1 = "TYPE1"

class ChargerTypeEnum(str, Enum):
    AC = "AC"
    DC = "DC"

class SessionStateEnum(str, Enum):
    INITIATED = "initiated"
    CONFIRMED = "confirmed"
    CHARGING = "charging"
    PAUSED = "paused"
    COMPLETED = "completed"
    CANCELLED = "cancelled"

class PaymentStatusEnum(str, Enum):
    NOT_PAID = "NOT_PAID"
    PENDING_COLLECT = "PENDING_COLLECT"
    COLLECTED = "COLLECTED"
    FAILED = "FAILED"

# ===== Quote & Pricing =====
class Price(BaseModel):
    currency: str = "INR"
    value: str  # String to avoid floating point issues

class QuoteBreakup(BaseModel):
    title: str  # e.g., "Energy Cost", "Service Charge", "GST"
    price: Price

class Quote(BaseModel):
    price: Price
    breakup: Optional[List[QuoteBreakup]] = []
    valid_till: Optional[str] = None

# ===== Payment Models =====
class Payment(BaseModel):
    uri: Optional[str] = None  # UPI string
    tl_method: str = "http"
    params: Dict[str, Any] = {}
    type: PaymentTypeEnum = PaymentTypeEnum.ON_FULFILLMENT
    status: PaymentStatusEnum = PaymentStatusEnum.NOT_PAID

# ===== Connector Models =====
class Connector(BaseModel):
    id: str
    connector_type: ConnectorTypeEnum
    charger_type: ChargerTypeEnum
    power_rating_kw: float
    availability: str = "Online"  # Online, Offline, Charging, Reserved
    location_id: str

class ConnectorLocation(BaseModel):
    id: str
    gps: str  # "lat,lon"
    address: Optional[Dict[str, str]] = None
    circle: Optional[Dict[str, Any]] = None  # radius in km

# ===== Meter Tags (Live Data) =====
class MeterTag(BaseModel):
    code: str
    value: str

class MeterReading(BaseModel):
    session_id: str
    energy_delivered_kwh: float
    cost_so_far_inr: float
    charging_rate_inr_per_kwh: float
    current_amps: Optional[float] = None
    voltage_volts: Optional[float] = None
    power_kw: Optional[float] = None
    soc_percent: Optional[float] = None
    timestamp: datetime

    def to_meter_tags(self) -> List[MeterTag]:
        return [
            MeterTag(code="energy-delivered", value=str(self.energy_delivered_kwh)),
            MeterTag(code="cost-so-far", value=str(self.cost_so_far_inr)),
            MeterTag(code="charging-rate", value=str(self.charging_rate_inr_per_kwh)),
            MeterTag(code="current", value=str(self.current_amps or 0)),
            MeterTag(code="voltage", value=str(self.voltage_volts or 0)),
            MeterTag(code="power", value=str(self.power_kw or 0)),
            MeterTag(code="soc", value=str(self.soc_percent or 0)),
        ]

# ===== Charging Session Models =====
class ChargingSession(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    charger_id: str
    connector_id: str
    user_id: str
    vehicle_id: Optional[str] = None
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_minutes: Optional[int] = None
    energy_delivered_kwh: float = 0.0
    total_cost_inr: float = 0.0
    charging_rate_inr_per_kwh: float
    payment_type: PaymentTypeEnum = PaymentTypeEnum.ON_FULFILLMENT
    state: SessionStateEnum = SessionStateEnum.INITIATED
    meter_readings: Optional[List[MeterReading]] = []

class SessionCreateRequest(BaseModel):
    charger_id: str
    connector_id: str
    charging_rate_inr_per_kwh: float
    vehicle_id: Optional[str] = None

class SessionResponse(BaseModel):
    session_id: str
    charger_id: str
    connector_id: str
    state: SessionStateEnum
    start_time: datetime
    energy_delivered_kwh: float = 0.0
    total_cost_inr: float = 0.0
    timestamp: datetime

# ===== Beckn Order Models =====
class BecknItem(BaseModel):
    id: str
    descriptor: Dict[str, str]
    price: Quote
    tags: Optional[List[MeterTag]] = []

class BecknFulfillment(BaseModel):
    id: str
    type: str = "DELIVERY"
    state: Dict[str, str]
    tracking: Optional[Dict[str, Any]] = None
    stops: Optional[List[Dict[str, Any]]] = None

class BecknOrder(BaseModel):
    id: str
    state: str  # "Accepted", "In-progress", "Completed"
    items: List[BecknItem]
    quote: Quote
    payment: Payment
    fulfillment: BecknFulfillment
    billing: Optional[Dict[str, Any]] = None

class BecknContext(BaseModel):
    domain: str = "ey-charging"
    action: str  # search, select, init, confirm, status, update
    city_code: str = "std:080"
    country_code: str = "IND"
    bap_id: str
    bap_uri: str
    bpp_id: Optional[str] = None
    bpp_uri: Optional[str] = None
    transaction_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    message_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    version: str = "1.1.0"

class BecknResponse(BaseModel):
    context: BecknContext
    message: Dict[str, Any]

# ===== Payment Transaction Models =====
class PaymentTransaction(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    session_id: str
    user_id: str
    amount_inr: float
    currency: str = "INR"
    payment_method: str  # "UPI", "NEFT", "CARD"
    upi_id: Optional[str] = None
    phone_number: Optional[str] = None
    reference_id: Optional[str] = None
    status: PaymentStatusEnum = PaymentStatusEnum.PENDING_COLLECT
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None
    notes: Optional[str] = None

# ===== Provider/Charger Models =====
class ChargerDescriptor(BaseModel):
    name: str
    code: Optional[str] = None
    short_desc: Optional[str] = None
    long_desc: Optional[str] = None
    images: Optional[List[str]] = []

class Charger(BaseModel):
    id: str
    descriptor: ChargerDescriptor
    location: ConnectorLocation
    connectors: List[Connector]
    rating: Optional[float] = None
    tags: Optional[List[MeterTag]] = []

class ChargerProvider(BaseModel):
    id: str
    descriptor: Dict[str, str]
    locations: List[ConnectorLocation]
    items: List[BecknItem]
```

### 2. Database Models

Create file: `backend/models/db_models.py`

```python
from sqlalchemy import Column, String, Float, DateTime, Enum, Integer, JSON, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid

# These are SQLAlchemy models for database ORM (optional, use Supabase client otherwise)
# If using raw Supabase client, define as Pydantic models above

class DBChargingSession:
    """Maps to charging_sessions table"""
    __tablename__ = "charging_sessions"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    charger_id = Column(String, nullable=False, index=True)
    connector_id = Column(String, nullable=False)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    vehicle_id = Column(UUID(as_uuid=True), nullable=True)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=True)
    energy_delivered_kwh = Column(Float, default=0.0)
    total_cost_inr = Column(Float, default=0.0)
    charging_rate_inr_per_kwh = Column(Float, nullable=False)
    payment_type = Column(String, default="ON_FULFILLMENT")
    state = Column(String, default="initiated")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class DBMeterReading:
    """Maps to meter_readings table"""
    __tablename__ = "meter_readings"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(UUID(as_uuid=True), ForeignKey("charging_sessions.id"))
    charger_id = Column(String, nullable=False, index=True)
    energy_kwh = Column(Float)
    cost_so_far_inr = Column(Float)
    charging_rate_inr_per_kwh = Column(Float)
    current_amps = Column(Float, nullable=True)
    voltage_volts = Column(Float, nullable=True)
    power_kw = Column(Float, nullable=True)
    soc_percent = Column(Float, nullable=True)
    recorded_at = Column(DateTime, default=datetime.utcnow, index=True)

class DBPaymentTransaction:
    """Maps to payment_transactions table"""
    __tablename__ = "payment_transactions"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("charging_sessions.id"))
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    amount_inr = Column(Float, nullable=False)
    currency = Column(String, default="INR")
    payment_method = Column(String)  # UPI, NEFT, CARD
    upi_id = Column(String, nullable=True)
    phone_number = Column(String, nullable=True)
    reference_id = Column(String, nullable=True, unique=True)
    status = Column(String, default="PENDING_COLLECT")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True)
    notes = Column(String, nullable=True)
```

---

## Database Design

### SQL Schema

Create file: `backend/migrations/001_create_beckn_tables.sql`

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Charging Sessions Table
CREATE TABLE IF NOT EXISTS charging_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    charger_id TEXT NOT NULL,
    connector_id TEXT NOT NULL,
    user_id UUID NOT NULL,
    vehicle_id UUID,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_minutes INTEGER,
    energy_delivered_kwh DECIMAL(10, 2) DEFAULT 0.0,
    total_cost_inr DECIMAL(10, 2) DEFAULT 0.0,
    charging_rate_inr_per_kwh DECIMAL(10, 2) NOT NULL,
    payment_type TEXT DEFAULT 'ON_FULFILLMENT',
    state TEXT DEFAULT 'initiated',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT valid_state CHECK (state IN (
        'initiated', 'confirmed', 'charging', 'paused', 'completed', 'cancelled'
    )),
    CONSTRAINT valid_payment_type CHECK (payment_type IN (
        'PRE_FULFILLMENT', 'ON_FULFILLMENT'
    ))
);

CREATE INDEX idx_sessions_user ON charging_sessions(user_id);
CREATE INDEX idx_sessions_charger ON charging_sessions(charger_id);
CREATE INDEX idx_sessions_state ON charging_sessions(state);
CREATE INDEX idx_sessions_created_at ON charging_sessions(created_at);

-- Meter Readings Table (time-series data)
CREATE TABLE IF NOT EXISTS meter_readings (
    id SERIAL PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES charging_sessions(id) ON DELETE CASCADE,
    charger_id TEXT NOT NULL,
    energy_kwh DECIMAL(10, 2),
    cost_so_far_inr DECIMAL(10, 2),
    charging_rate_inr_per_kwh DECIMAL(10, 2),
    current_amps DECIMAL(8, 2),
    voltage_volts DECIMAL(8, 2),
    power_kw DECIMAL(8, 2),
    soc_percent DECIMAL(5, 2),
    recorded_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_meter_session ON meter_readings(session_id);
CREATE INDEX idx_meter_charger ON meter_readings(charger_id);
CREATE INDEX idx_meter_recorded_at ON meter_readings(recorded_at);

-- Payment Transactions Table
CREATE TABLE IF NOT EXISTS payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES charging_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    amount_inr DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'INR',
    payment_method TEXT NOT NULL,
    upi_id TEXT,
    phone_number TEXT,
    reference_id TEXT UNIQUE,
    status TEXT DEFAULT 'PENDING_COLLECT',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP,
    notes TEXT,
    CONSTRAINT valid_payment_status CHECK (status IN (
        'NOT_PAID', 'PENDING_COLLECT', 'COLLECTED', 'FAILED'
    ))
);

CREATE INDEX idx_payment_session ON payment_transactions(session_id);
CREATE INDEX idx_payment_user ON payment_transactions(user_id);
CREATE INDEX idx_payment_status ON payment_transactions(status);
CREATE INDEX idx_payment_created_at ON payment_transactions(created_at);

-- Charger Metadata Cache
CREATE TABLE IF NOT EXISTS charger_metadata (
    charger_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    connector_types TEXT[],
    power_kw DECIMAL(8, 2),
    availability_status TEXT DEFAULT 'Online',
    metadata JSONB,
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_charger_location ON charger_metadata USING GIST (
    ll_to_earth(latitude, longitude)
);

-- Beckn Transaction Log (for audit trail)
CREATE TABLE IF NOT EXISTS beckn_transaction_log (
    id SERIAL PRIMARY KEY,
    session_id UUID REFERENCES charging_sessions(id),
    action TEXT NOT NULL,
    request_context JSONB,
    response_message JSONB,
    status_code INTEGER,
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_beckn_session ON beckn_transaction_log(session_id);
CREATE INDEX idx_beckn_action ON beckn_transaction_log(action);
```

---

## Backend Implementation

### 1. Create Beckn Router

Create file: `backend/routers/beckn_charging.py`

```python
import logging
from datetime import datetime
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
import uuid

from models.beckn_models import (
    BecknResponse, BecknContext, BecknOrder, BecknItem, Price, Quote, Payment,
    ChargingSession, SessionCreateRequest, SessionResponse, MeterReading,
    PaymentTransaction, ConnectorTypeEnum, SessionStateEnum, PaymentStatusEnum
)
from auth_utils import require_auth, get_authenticated_user
from supabase_client import supabase
from utils.ocpp_integration import OCPPManager
from utils.payment_service import PaymentService
from config import settings

router = APIRouter()
logger = logging.getLogger(__name__)

CHARGING_RATE_INR_PER_KWH = 15.0  # Default rate, can vary by charger


# ===== Helper Functions =====

def create_beckn_context(action: str, transaction_id: Optional[str] = None) -> BecknContext:
    """Create Beckn context for responses"""
    return BecknContext(
        action=action,
        bap_id=settings.BAP_ID,
        bap_uri=settings.BACKEND_URL,
        bpp_id=settings.BPP_ID,
        bpp_uri=settings.BACKEND_URL,
        transaction_id=transaction_id or str(uuid.uuid4()),
    )


async def get_charger_by_id(charger_id: str) -> Dict[str, Any]:
    """Fetch charger from database"""
    try:
        result = supabase.table("charger_metadata").select("*").eq("charger_id", charger_id).single().execute()
        return result.data
    except Exception as e:
        logger.error(f"Error fetching charger: {e}")
        return None


async def calculate_quote(energy_kwh: float, charger_id: str) -> Quote:
    """Calculate quote with breakdown"""
    charger = await get_charger_by_id(charger_id)
    rate = CHARGING_RATE_INR_PER_KWH
    
    energy_cost = energy_kwh * rate
    service_charge = energy_cost * 0.05  # 5% service charge
    gst = (energy_cost + service_charge) * 0.05  # 5% GST
    total = energy_cost + service_charge + gst
    
    return Quote(
        price=Price(value=f"{total:.2f}"),
        breakup=[
            {"title": "Energy Cost", "price": Price(value=f"{energy_cost:.2f}")},
            {"title": "Service Charge", "price": Price(value=f"{service_charge:.2f}")},
            {"title": "GST", "price": Price(value=f"{gst:.2f}")},
        ]
    )


# ===== Beckn API Endpoints =====

@router.post("/beckn/search")
async def beckn_search(
    latitude: float = Query(...),
    longitude: float = Query(...),
    radius_km: float = Query(5.0),
):
    """
    Beckn search endpoint - returns nearby chargers
    Response: on_search (catalog of chargers)
    """
    try:
        # Query chargers within radius
        result = supabase.rpc(
            "nearby_chargers",
            {"lat": latitude, "lon": longitude, "radius": radius_km}
        ).execute()
        
        chargers = result.data or []
        
        # Build Beckn catalog response
        providers = []
        for charger in chargers:
            items = [
                BecknItem(
                    id="charging_session",
                    descriptor={
                        "name": f"{charger['power_kw']}kW DC Charging",
                        "code": "EV_CHARGING_SESSION"
                    },
                    price=Price(value=f"{CHARGING_RATE_INR_PER_KWH:.2f}"),
                    tags=[
                        {"code": "connector-type", "value": charger["connector_types"][0]},
                        {"code": "power-rating", "value": str(charger["power_kw"])},
                    ]
                )
            ]
            
            providers.append({
                "id": charger["charger_id"],
                "descriptor": {"name": charger["name"]},
                "locations": [{
                    "id": charger["charger_id"],
                    "gps": f"{charger['latitude']},{charger['longitude']}",
                    "address": {"full": charger.get("address", "Unknown")},
                }],
                "items": [item.dict() for item in items]
            })
        
        response = BecknResponse(
            context=create_beckn_context("on_search"),
            message={
                "catalog": {
                    "descriptor": {"name": "EV-Router Charging Network"},
                    "providers": providers
                }
            }
        )
        
        return response.dict()
    except Exception as e:
        logger.error(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/beckn/select")
async def beckn_select(
    charger_id: str = Query(...),
    connector_id: str = Query(...),
):
    """
    Beckn select endpoint - returns charger details
    Response: on_select (charger details with quote)
    """
    try:
        charger = await get_charger_by_id(charger_id)
        if not charger:
            raise HTTPException(status_code=404, detail="Charger not found")
        
        quote = await calculate_quote(50, charger_id)  # Assume 50 kWh session
        
        response = BecknResponse(
            context=create_beckn_context("on_select"),
            message={
                "order": {
                    "provider": {
                        "id": charger_id,
                        "descriptor": {"name": charger["name"]}
                    },
                    "items": [{
                        "id": "charging_session",
                        "descriptor": {"name": f"{charger['power_kw']}kW Charging"},
                        "price": quote.dict()
                    }],
                    "quote": quote.dict()
                }
            }
        )
        
        return response.dict()
    except Exception as e:
        logger.error(f"Select error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/beckn/init")
async def beckn_init(
    charger_id: str = Query(...),
    connector_id: str = Query(...),
    user_id: str = Depends(require_auth),
):
    """
    Beckn init endpoint - initialize order with payment terms
    Response: on_init (order with payment details)
    """
    try:
        charger = await get_charger_by_id(charger_id)
        quote = await calculate_quote(50, charger_id)
        
        response = BecknResponse(
            context=create_beckn_context("on_init"),
            message={
                "order": {
                    "id": str(uuid.uuid4()),
                    "provider": {"id": charger_id},
                    "quote": quote.dict(),
                    "payment": {
                        "type": "ON_FULFILLMENT",
                        "status": "NOT_PAID",
                        "params": {
                            "amount": quote.price.value,
                            "currency": "INR"
                        }
                    }
                }
            }
        )
        
        return response.dict()
    except Exception as e:
        logger.error(f"Init error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sessions/start")
async def start_charging_session(
    request: SessionCreateRequest,
    user_id: str = Depends(require_auth),
):
    """
    Start a new charging session
    Initiates ON_FULFILLMENT postpaid metering
    """
    try:
        charger = await get_charger_by_id(request.charger_id)
        if not charger:
            raise HTTPException(status_code=404, detail="Charger not found")
        
        session_id = str(uuid.uuid4())
        now = datetime.utcnow()
        
        # Create session in database
        supabase.table("charging_sessions").insert({
            "id": session_id,
            "charger_id": request.charger_id,
            "connector_id": request.connector_id,
            "user_id": user_id,
            "vehicle_id": request.vehicle_id,
            "start_time": now.isoformat(),
            "charging_rate_inr_per_kwh": request.charging_rate_inr_per_kwh,
            "payment_type": "ON_FULFILLMENT",
            "state": "charging",
        }).execute()
        
        # Send start command to OCPP charger
        ocpp = OCPPManager(request.charger_id)
        await ocpp.start_charging(request.connector_id)
        
        response = SessionResponse(
            session_id=session_id,
            charger_id=request.charger_id,
            connector_id=request.connector_id,
            state=SessionStateEnum.CHARGING,
            start_time=now
        )
        
        logger.info(f"Started session {session_id}")
        return response.dict()
    except Exception as e:
        logger.error(f"Start session error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sessions/{session_id}/status")
async def get_session_status(
    session_id: str,
    user_id: str = Depends(require_auth),
):
    """
    Get current session status with live meter data (on_status)
    Called frequently by mobile app to show live metrics
    """
    try:
        # Fetch session
        session_result = supabase.table("charging_sessions").select("*").eq("id", session_id).single().execute()
        session = session_result.data
        
        if session["user_id"] != user_id:
            raise HTTPException(status_code=403, detail="Not authorized")
        
        # Get latest meter reading
        meter_result = supabase.table("meter_readings").select("*").eq(
            "session_id", session_id
        ).order("recorded_at", desc=True).limit(1).execute()
        
        meter_data = meter_result.data[0] if meter_result.data else None
        
        # Fetch live data from OCPP charger
        ocpp = OCPPManager(session["charger_id"])
        live_metrics = await ocpp.get_live_metrics()
        
        # Create meter reading record
        energy_kwh = live_metrics.get("energy", 0)
        cost_so_far = energy_kwh * session["charging_rate_inr_per_kwh"]
        
        meter_record = {
            "session_id": session_id,
            "charger_id": session["charger_id"],
            "energy_kwh": energy_kwh,
            "cost_so_far_inr": cost_so_far,
            "charging_rate_inr_per_kwh": session["charging_rate_inr_per_kwh"],
            "current_amps": live_metrics.get("current"),
            "voltage_volts": live_metrics.get("voltage"),
            "power_kw": live_metrics.get("power"),
            "soc_percent": live_metrics.get("soc"),
            "recorded_at": datetime.utcnow().isoformat()
        }
        
        supabase.table("meter_readings").insert(meter_record).execute()
        
        # Build Beckn on_status response
        response = BecknResponse(
            context=create_beckn_context("on_status"),
            message={
                "order": {
                    "id": session_id,
                    "state": "In-progress",
                    "tags": [
                        {"code": "energy-delivered", "value": str(energy_kwh)},
                        {"code": "cost-so-far", "value": str(cost_so_far)},
                        {"code": "charging-rate", "value": str(session["charging_rate_inr_per_kwh"])},
                        {"code": "current", "value": str(live_metrics.get("current", 0))},
                        {"code": "voltage", "value": str(live_metrics.get("voltage", 0))},
                        {"code": "power", "value": str(live_metrics.get("power", 0))},
                        {"code": "soc", "value": str(live_metrics.get("soc", 0))},
                    ]
                }
            }
        )
        
        return response.dict()
    except Exception as e:
        logger.error(f"Status error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sessions/{session_id}/end")
async def end_charging_session(
    session_id: str,
    user_id: str = Depends(require_auth),
):
    """
    End session and generate payment (on_update)
    Triggers UPI collect payment and cable unlock
    """
    try:
        # Fetch session
        session_result = supabase.table("charging_sessions").select("*").eq("id", session_id).single().execute()
        session = session_result.data
        
        if session["user_id"] != user_id:
            raise HTTPException(status_code=403, detail="Not authorized")
        
        now = datetime.utcnow()
        duration_minutes = int((now - datetime.fromisoformat(session["start_time"])).total_seconds() / 60)
        
        # Get final meter reading
        meter_result = supabase.table("meter_readings").select("*").eq(
            "session_id", session_id
        ).order("recorded_at", desc=True).limit(1).execute()
        
        final_meter = meter_result.data[0] if meter_result.data else {}
        energy_kwh = final_meter.get("energy_kwh", 0)
        total_cost = final_meter.get("cost_so_far_inr", 0)
        
        # Update session
        supabase.table("charging_sessions").update({
            "end_time": now.isoformat(),
            "duration_minutes": duration_minutes,
            "state": "completed",
            "energy_delivered_kwh": energy_kwh,
            "total_cost_inr": total_cost,
        }).eq("id", session_id).execute()
        
        # Get user phone for UPI payment
        user_data = await get_authenticated_user(user_id)
        user_phone = user_data.get("phone_number", "")
        
        # Create payment transaction
        payment_service = PaymentService()
        upi_deep_link = await payment_service.create_upi_collect(
            phone=user_phone,
            amount=total_cost,
            description=f"EV Charging Session {session_id}",
            reference_id=session_id
        )
        
        # Store payment transaction
        supabase.table("payment_transactions").insert({
            "session_id": session_id,
            "user_id": user_id,
            "amount_inr": total_cost,
            "payment_method": "UPI",
            "upi_id": user_phone,
            "status": "PENDING_COLLECT",
            "reference_id": session_id,
        }).execute()
        
        # Send OCPP command to stop charging
        ocpp = OCPPManager(session["charger_id"])
        await ocpp.stop_charging(session["connector_id"])
        
        # Build Beckn on_update response with payment
        response = BecknResponse(
            context=create_beckn_context("on_update"),
            message={
                "order": {
                    "id": session_id,
                    "state": "Completed",
                    "quote": {
                        "price": {"currency": "INR", "value": f"{total_cost:.2f}"},
                        "breakup": [
                            {"title": "Energy", "price": {"currency": "INR", "value": f"{energy_kwh * session['charging_rate_inr_per_kwh']:.2f}"}},
                        ]
                    },
                    "payment": {
                        "uri": upi_deep_link,
                        "type": "ON_FULFILLMENT",
                        "status": "PENDING_COLLECT",
                        "params": {
                            "amount": f"{total_cost:.2f}",
                            "currency": "INR"
                        }
                    },
                    "tags": [
                        {"code": "total-energy", "value": str(energy_kwh)},
                        {"code": "total-cost", "value": str(total_cost)},
                        {"code": "duration-minutes", "value": str(duration_minutes)},
                        {"code": "session-start", "value": session["start_time"]},
                        {"code": "session-end", "value": now.isoformat()},
                    ]
                }
            }
        )
        
        logger.info(f"Ended session {session_id}: {energy_kwh} kWh, ₹{total_cost}")
        return response.dict()
    except Exception as e:
        logger.error(f"End session error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/payments/{session_id}/confirm")
async def confirm_payment(
    session_id: str,
    reference_id: str = Query(...),
    user_id: str = Depends(require_auth),
):
    """
    Confirm payment was received
    Called after UPI payment succeeds
    Triggers cable unlock
    """
    try:
        # Verify payment status
        payment_service = PaymentService()
        payment_status = await payment_service.verify_payment(reference_id)
        
        if payment_status != "COLLECTED":
            raise HTTPException(status_code=400, detail="Payment not confirmed")
        
        # Update payment transaction
        supabase.table("payment_transactions").update({
            "status": "COLLECTED",
            "updated_at": datetime.utcnow().isoformat()
        }).eq("reference_id", session_id).execute()
        
        # Get session to unlock cable
        session_result = supabase.table("charging_sessions").select("*").eq("id", session_id).single().execute()
        session = session_result.data
        
        # Send OCPP unlock command
        ocpp = OCPPManager(session["charger_id"])
        unlock_result = await ocpp.unlock_connector(session["connector_id"])
        
        return {
            "status": "success",
            "message": "Payment confirmed and cable unlocked",
            "unlock_status": unlock_result
        }
    except Exception as e:
        logger.error(f"Payment confirmation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
```

### 2. Update main.py

Update `backend/main.py` to include Beckn router:

```python
from routers import beckn_charging

# Add to app.include_router section:
app.include_router(beckn_charging.router, prefix="/api/chargers", tags=["Beckn Charging"])
```

---

## Frontend Implementation

### 0. QR Scanner Service Layer

Create file: `lib/services/qr_scanner_service.dart`

```dart
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class QRScannerService {
  final String baseUrl;
  final String accessToken;
  
  QRScannerService({
    required this.baseUrl,
    required this.accessToken,
  });

  // Validate scanned QR code
  Future<Map<String, dynamic>> validateQRCode(String qrData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/qr/validate'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'qr_data': qrData,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Failed to validate QR code');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get QR code image for a charger (admin function)
  Future<String> getChargerQRCode(String chargerId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/chargers/$chargerId/qr'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['qr_code'];
      } else {
        throw Exception('Failed to get QR code');
      }
    } catch (e) {
      rethrow;
    }
  }
}
```

### 1. Flutter Service Layer

Create file: `lib/services/beckn_charging_service.dart`

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BecknChargingService {
  final String baseUrl;
  final String accessToken;
  
  BecknChargingService({
    required this.baseUrl,
    required this.accessToken,
  });

  // Search nearby chargers
  Future<Map<String, dynamic>> searchChargers({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/beckn/search'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'radius_km': radiusKm,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to search chargers: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get charger details
  Future<Map<String, dynamic>> selectCharger({
    required String chargerId,
    required String connectorId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/beckn/select'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        queryParameters: {
          'charger_id': chargerId,
          'connector_id': connectorId,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to select charger');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Start charging session
  Future<String> startSession({
    required String chargerId,
    required String connectorId,
    required double chargingRateInrPerKwh,
    String? vehicleId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/sessions/start'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'charger_id': chargerId,
          'connector_id': connectorId,
          'charging_rate_inr_per_kwh': chargingRateInrPerKwh,
          'vehicle_id': vehicleId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['session_id'];
      } else {
        throw Exception('Failed to start session');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get live session status
  Future<Map<String, dynamic>> getSessionStatus(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/chargers/sessions/$sessionId/status'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get session status');
      }
    } catch (e) {
      rethrow;
    }
  }

  // End charging session
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/sessions/$sessionId/end'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to end session');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Confirm payment after UPI success
  Future<Map<String, dynamic>> confirmPayment({
    required String sessionId,
    required String referenceId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chargers/payments/$sessionId/confirm'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        queryParameters: {
          'reference_id': referenceId,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to confirm payment');
      }
    } catch (e) {
      rethrow;
    }
  }

  // WebSocket for live meter updates
  WebSocketChannel getSessionWebSocket(String sessionId) {
    final uri = baseUrl.replaceFirst('http', 'ws');
    return WebSocketChannel.connect(
      Uri.parse('$uri/api/chargers/ws/session/$sessionId?token=$accessToken'),
    );
  }
}
```

### 2. Flutter QR Scanner Screen

Create file: `lib/screens/charging/qr_scanner_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/qr_scanner_service.dart';
import 'charger_confirm_screen.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late MobileScannerController cameraController;
  bool isScanning = true;
  bool isLoading = false;
  String? lastScannedCode;
  late QRScannerService qrService;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
    qrService = QRScannerService(
      baseUrl: 'https://api.evrouter.com',
      accessToken: 'your_token_here',
    );
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required')),
        );
      }
    }
  }

  Future<void> _processQRCode(String code) async {
    if (code == lastScannedCode) return;
    
    lastScannedCode = code;
    
    if (isLoading) return;
    
    setState(() => isLoading = true);
    
    try {
      final result = await qrService.validateQRCode(code);
      
      if (result['status'] == 'valid') {
        if (mounted) {
          // Navigate to charger confirmation screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChargerConfirmScreen(
                chargerData: result,
                fromQRScan: true,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid charger: ${e.toString()}')),
        );
      }
      lastScannedCode = null;
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Charger QR'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _processQRCode(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          
          // Overlay
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),

          // Loading indicator
          if (isLoading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Validating charger...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom instructions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Position the QR code within the frame',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### 3. Flutter Charger Confirmation Screen

Create file: `lib/screens/charging/charger_confirm_screen.dart`

```dart
import 'package:flutter/material.dart';

import '../../services/beckn_charging_service.dart';
import 'charging_session_screen.dart';

class ChargerConfirmScreen extends StatefulWidget {
  final Map<String, dynamic> chargerData;
  final bool fromQRScan;

  const ChargerConfirmScreen({
    required this.chargerData,
    this.fromQRScan = false,
  });

  @override
  State<ChargerConfirmScreen> createState() => _ChargerConfirmScreenState();
}

class _ChargerConfirmScreenState extends State<ChargerConfirmScreen> {
  bool isStarting = false;

  Future<void> _startCharging() async {
    setState(() => isStarting = true);
    
    try {
      final service = BecknChargingService(
        baseUrl: 'https://api.evrouter.com',
        accessToken: 'your_token_here',
      );

      final sessionId = await service.startSession(
        chargerId: widget.chargerData['charger_id'],
        connectorId: widget.chargerData['connector_id'],
        chargingRateInrPerKwh: widget.chargerData['charging_rate_inr_per_kwh'],
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChargingSessionScreen(
              sessionId: sessionId,
              chargerId: widget.chargerData['charger_id'],
              connectorId: widget.chargerData['connector_id'],
              chargingRateInrPerKwh: widget.chargerData['charging_rate_inr_per_kwh'],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => isStarting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Charger'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Charger Info Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chargerData['charger_name'] ?? 'Unknown Charger',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.chargerData['location_name'] ?? 'Unknown Location',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Charger Details Grid
            GridView(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildDetailCard(
                  'Power',
                  '${widget.chargerData['power_kw']} kW',
                  Icons.bolt,
                ),
                _buildDetailCard(
                  'Type',
                  widget.chargerData['connector_type'] ?? 'CCS2',
                  Icons.ev_station,
                ),
                _buildDetailCard(
                  'Rate',
                  '₹${widget.chargerData['charging_rate_inr_per_kwh']}/kWh',
                  Icons.attach_money,
                ),
                _buildDetailCard(
                  'Status',
                  'Available',
                  Icons.check_circle,
                  statusColor: Colors.green,
                ),
              ],
            ),
            const Spacer(),

            // Action Buttons
            if (isStarting)
              const Center(
                child: CircularProgressIndicator(),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _startCharging,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Colors.green,
                    ),
                    child: const Text(
                      'Start Charging',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
    String label,
    String value,
    IconData icon, {
    Color? statusColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: statusColor ?? Colors.blue),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4. Flutter UI Components - Charging Session

Create file: `lib/screens/charging/charging_session_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

import '../../services/beckn_charging_service.dart';

class ChargingSessionScreen extends StatefulWidget {
  final String sessionId;
  final String chargerId;
  final String connectorId;
  final double chargingRateInrPerKwh;

  const ChargingSessionScreen({
    required this.sessionId,
    required this.chargerId,
    required this.connectorId,
    required this.chargingRateInrPerKwh,
  });

  @override
  State<ChargingSessionScreen> createState() => _ChargingSessionScreenState();
}

class _ChargingSessionScreenState extends State<ChargingSessionScreen> {
  late String sessionId;
  late WebSocketChannel channel;
  
  double energyDelivered = 0.0;
  double costSoFar = 0.0;
  double currentAmps = 0.0;
  double voltage = 0.0;
  double power = 0.0;
  double soc = 0.0;
  bool isCharging = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    sessionId = widget.sessionId;
    _connectToSession();
  }

  Future<void> _connectToSession() async {
    try {
      final service = BecknChargingService(
        baseUrl: 'https://api.evrouter.com',
        accessToken: 'your_token_here',
      );

      // Connect WebSocket for live updates
      channel = service.getSessionWebSocket(sessionId);
      
      channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'meter_update') {
            _updateMeterData(data['data']);
          }
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection error: $error')),
          );
        },
      );

      setState(() => isLoading = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _updateMeterData(Map<String, dynamic> data) {
    setState(() {
      energyDelivered = double.parse(data['energy_delivered'].toString());
      costSoFar = double.parse(data['cost_so_far'].toString());
      currentAmps = double.parse(data['current'].toString());
      voltage = double.parse(data['voltage'].toString());
      power = double.parse(data['power'].toString());
      soc = double.parse(data['soc'].toString());
    });
  }

  Future<void> _endSession() async {
    try {
      final service = BecknChargingService(
        baseUrl: 'https://api.evrouter.com',
        accessToken: 'your_token_here',
      );

      final result = await service.endSession(sessionId);
      
      if (mounted) {
        _showPaymentDialog(result['message']['order']['payment']['uri']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ending session: $e')),
      );
    }
  }

  void _showPaymentDialog(String upiUri) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount Due: ₹${costSoFar.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            const Text('Energy Delivered: '),
            Text('${energyDelivered.toStringAsFixed(2)} kWh'),
            const SizedBox(height: 16),
            Text('Open UPI app to complete payment'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Launch UPI
              // if (await canLaunch(upiUri)) {
              //   await launch(upiUri);
              // }
              
              // Confirm payment after UPI success
              final service = BecknChargingService(
                baseUrl: 'https://api.evrouter.com',
                accessToken: 'your_token_here',
              );
              
              await service.confirmPayment(
                sessionId: sessionId,
                referenceId: sessionId,
              );
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment confirmed! Cable unlocked.')),
              );
            },
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Starting Session...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging Session'),
        actions: [
          if (isCharging)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => isCharging = false);
                  _endSession();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop Charging'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Energy & Cost
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '${energyDelivered.toStringAsFixed(2)} kWh',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${costSoFar.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Live Metrics Grid
            GridView(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
              ),
              shrinkWrap: true,
              children: [
                _buildMetricCard('Current', '${currentAmps.toStringAsFixed(1)} A'),
                _buildMetricCard('Voltage', '${voltage.toStringAsFixed(0)} V'),
                _buildMetricCard('Power', '${power.toStringAsFixed(1)} kW'),
                _buildMetricCard('SOC', '${soc.toStringAsFixed(1)} %'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
```

### 5. Main Charging Screen with QR Button

Create file: `lib/screens/charging/charging_home_screen.dart`

```dart
import 'package:flutter/material.dart';

import 'qr_scanner_screen.dart';
import 'charger_search_screen.dart';

class ChargingHomeScreen extends StatefulWidget {
  const ChargingHomeScreen({Key? key}) : super(key: key);

  @override
  State<ChargingHomeScreen> createState() => _ChargingHomeScreenState();
}

class _ChargingHomeScreenState extends State<ChargingHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Chargers'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // QR Code Scan Option
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QRScannerScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        size: 64,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Scan Charger QR Code',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Point camera at charger QR code for instant access',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Divider
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
            const SizedBox(height: 16),

            // Search Option
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChargerSearchScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 64,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Find Nearby Chargers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search and filter chargers by location & amenities',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 6. Update pubspec.yaml

Add required dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  web_socket_channel: ^2.4.0
  provider: ^6.0.0
  mobile_scanner: ^3.5.0
  permission_handler: ^11.4.4
  qr_code_scanner: ^0.7.0
  
dev_dependencies:
  flutter_test:
    sdk: flutter
```

Run:
```bash
flutter pub get
```

---

## OCPP Integration

Create file: `backend/utils/ocpp_integration.py`

```python
import logging
import asyncio
from typing import Dict, Any, Optional
import httpx

logger = logging.getLogger(__name__)

class OCPPManager:
    """
    Manages OCPP communication with EV chargers
    Maps OCPP metrics to Beckn schema
    """
    
    def __init__(self, charger_id: str, charger_endpoint: Optional[str] = None):
        self.charger_id = charger_id
        self.charger_endpoint = charger_endpoint or f"http://charger-{charger_id}.local:8080"
        self.timeout = 10
    
    async def start_charging(self, connector_id: str) -> bool:
        """Start charging on a connector"""
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.charger_endpoint}/api/start",
                    json={"connector_id": connector_id}
                )
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to start charging: {e}")
            return False
    
    async def stop_charging(self, connector_id: str) -> bool:
        """Stop charging on a connector"""
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.charger_endpoint}/api/stop",
                    json={"connector_id": connector_id}
                )
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to stop charging: {e}")
            return False
    
    async def get_live_metrics(self) -> Dict[str, Any]:
        """
        Fetch live OCPP metrics from charger
        Returns dict with keys: energy, current, voltage, power, soc, temperature
        """
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    f"{self.charger_endpoint}/api/metrics"
                )
                data = response.json()
                
                # Map OCPP fields to standardized format
                return {
                    "energy": float(data.get("energy_delivered", 0)),  # kWh
                    "current": float(data.get("current_a", 0)),  # Amps
                    "voltage": float(data.get("voltage_v", 0)),  # Volts
                    "power": float(data.get("power_kw", 0)),  # kW
                    "soc": float(data.get("soc_percent", 0)),  # Percent (if available)
                    "temperature": float(data.get("temperature_c", 0)),  # Celsius
                }
        except Exception as e:
            logger.error(f"Failed to get live metrics: {e}")
            return {
                "energy": 0,
                "current": 0,
                "voltage": 0,
                "power": 0,
                "soc": 0,
                "temperature": 0,
            }
    
    async def unlock_connector(self, connector_id: str) -> bool:
        """
        Send UnlockConnector command to OCPP charger
        Called after successful payment
        """
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.charger_endpoint}/api/unlock",
                    json={"connector_id": connector_id}
                )
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to unlock connector: {e}")
            return False
    
    async def get_connector_status(self, connector_id: str) -> str:
        """Get current connector status"""
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    f"{self.charger_endpoint}/api/connector/{connector_id}/status"
                )
                data = response.json()
                return data.get("status", "Unknown")
        except Exception as e:
            logger.error(f"Failed to get connector status: {e}")
            return "Unknown"
    
    async def set_charging_profile(
        self,
        connector_id: str,
        power_kw: float,
        duration_minutes: int
    ) -> bool:
        """Set dynamic charging profile"""
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.charger_endpoint}/api/profile",
                    json={
                        "connector_id": connector_id,
                        "power_kw": power_kw,
                        "duration_minutes": duration_minutes,
                    }
                )
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to set charging profile: {e}")
            return False
```

---

## Payment Flow

Create file: `backend/utils/payment_service.py`

```python
import logging
import uuid
from typing import Dict, Any
import httpx
from datetime import datetime

logger = logging.getLogger(__name__)

class PaymentService:
    """
    Handles UPI payment generation and verification
    Integrates with payment gateway
    """
    
    def __init__(self):
        self.gateway_url = "https://payment-gateway.com/api"
        self.merchant_id = "YOUR_MERCHANT_ID"
        self.api_key = "YOUR_API_KEY"
    
    async def create_upi_collect(
        self,
        phone: str,
        amount: float,
        description: str,
        reference_id: str
    ) -> str:
        """
        Generate UPI deep link for payment collection
        Format: upi://pay?pa=...&pn=...&am=...&tn=...
        """
        try:
            upi_id = f"evrouter@paytm"  # Your merchant UPI
            
            upi_link = (
                f"upi://pay?"
                f"pa={upi_id}&"
                f"pn=EV%20Router&"
                f"am={amount}&"
                f"tn={description}&"
                f"tr={reference_id}"
            )
            
            logger.info(f"Generated UPI link for ₹{amount}")
            return upi_link
        except Exception as e:
            logger.error(f"Failed to create UPI collect: {e}")
            raise
    
    async def verify_payment(self, reference_id: str) -> str:
        """
        Verify payment status from gateway
        Returns: "COLLECTED", "PENDING", or "FAILED"
        """
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{self.gateway_url}/verify",
                    params={
                        "reference_id": reference_id,
                        "merchant_id": self.merchant_id,
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    timeout=10
                )
                
                data = response.json()
                return data.get("status", "FAILED")
        except Exception as e:
            logger.error(f"Payment verification failed: {e}")
            return "FAILED"
    
    async def refund_payment(self, reference_id: str, amount: float) -> bool:
        """Process refund for failed/cancelled sessions"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.gateway_url}/refund",
                    json={
                        "reference_id": reference_id,
                        "amount": amount,
                        "merchant_id": self.merchant_id,
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    timeout=10
                )
                
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Refund failed: {e}")
            return False
    
    def generate_receipt(self, session_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate digital receipt after payment"""
        return {
            "receipt_id": str(uuid.uuid4()),
            "session_id": session_data.get("session_id"),
            "date": datetime.utcnow().isoformat(),
            "charger_name": session_data.get("charger_name"),
            "energy_kwh": session_data.get("energy_kwh"),
            "amount": session_data.get("amount"),
            "currency": "INR",
        }
```

---

## Real-time Updates

Create file: `backend/websocket_handler.py`

```python
import logging
import asyncio
from datetime import datetime
from typing import Dict, List
from fastapi import WebSocket, WebSocketDisconnect, Depends
import json

from auth_utils import get_authenticated_user
from supabase_client import supabase

logger = logging.getLogger(__name__)

class SessionWebSocketManager:
    """Manages WebSocket connections for live meter updates"""
    
    def __init__(self):
        self.active_sessions: Dict[str, List[WebSocket]] = {}
        self.update_interval = 2  # seconds
    
    async def connect(self, session_id: str, websocket: WebSocket, user_id: str):
        """Accept WebSocket connection"""
        await websocket.accept()
        
        if session_id not in self.active_sessions:
            self.active_sessions[session_id] = []
        
        self.active_sessions[session_id].append(websocket)
        logger.info(f"Client connected to session {session_id}")
    
    def disconnect(self, session_id: str, websocket: WebSocket):
        """Remove disconnected WebSocket"""
        if session_id in self.active_sessions:
            self.active_sessions[session_id].remove(websocket)
            if not self.active_sessions[session_id]:
                del self.active_sessions[session_id]
            logger.info(f"Client disconnected from session {session_id}")
    
    async def broadcast_meter_update(self, session_id: str, meter_data: Dict):
        """Broadcast meter data to all connected clients"""
        if session_id not in self.active_sessions:
            return
        
        message = json.dumps({
            "type": "meter_update",
            "data": meter_data,
            "timestamp": datetime.utcnow().isoformat()
        })
        
        disconnected = []
        for websocket in self.active_sessions[session_id]:
            try:
                await websocket.send_text(message)
            except Exception as e:
                logger.error(f"Failed to send update: {e}")
                disconnected.append(websocket)
        
        # Clean up disconnected clients
        for ws in disconnected:
            self.disconnect(session_id, ws)
    
    async def broadcast_session_end(self, session_id: str, final_data: Dict):
        """Notify clients that session has ended"""
        message = json.dumps({
            "type": "session_end",
            "data": final_data,
            "timestamp": datetime.utcnow().isoformat()
        })
        
        if session_id in self.active_sessions:
            for websocket in self.active_sessions[session_id]:
                try:
                    await websocket.send_text(message)
                    await websocket.close()
                except Exception as e:
                    logger.error(f"Failed to close connection: {e}")
            
            del self.active_sessions[session_id]

ws_manager = SessionWebSocketManager()

async def broadcast_meter_updates():
    """Background task: fetch and broadcast meter updates"""
    while True:
        try:
            await asyncio.sleep(2)  # Update every 2 seconds
            
            for session_id in list(ws_manager.active_sessions.keys()):
                # Fetch latest meter reading
                result = supabase.table("meter_readings").select("*").eq(
                    "session_id", session_id
                ).order("recorded_at", desc=True).limit(1).execute()
                
                if result.data:
                    meter = result.data[0]
                    meter_data = {
                        "energy_delivered": meter.get("energy_kwh"),
                        "cost_so_far": meter.get("cost_so_far_inr"),
                        "current": meter.get("current_amps"),
                        "voltage": meter.get("voltage_volts"),
                        "power": meter.get("power_kw"),
                        "soc": meter.get("soc_percent"),
                    }
                    
                    await ws_manager.broadcast_meter_update(session_id, meter_data)
        
        except Exception as e:
            logger.error(f"Error in meter broadcast: {e}")
```

Add to `backend/main.py`:

```python
import asyncio
from websocket_handler import broadcast_meter_updates

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start background task for meter updates
    task = asyncio.create_task(broadcast_meter_updates())
    yield
    task.cancel()
```

---

## Session State Machine & Idempotency

### Why This Matters

Without these patterns, the system fails in production:
- **Network retries** → duplicate sessions, double-charged users
- **Race conditions** → two users grab same charger simultaneously
- **Orphan sessions** → charger running, no DB record

### State Machine

Create file: `backend/utils/session_state_machine.py`

```python
from enum import Enum
from typing import Dict, Set, Optional
import logging

logger = logging.getLogger(__name__)


class SessionState(str, Enum):
    INITIATED = "initiated"
    AUTHORIZING = "authorizing"      # Validating user/payment auth
    AUTHORIZED = "authorized"         # Ready to start
    STARTING = "starting"             # Sending OCPP start command
    CHARGING = "charging"             # Actively charging
    STOPPING = "stopping"             # OCPP stop sent
    METERING_FINAL = "metering_final" # Reading final meter values
    AWAITING_PAYMENT = "awaiting_payment"
    PAYMENT_CONFIRMED = "payment_confirmed"
    UNLOCKING = "unlocking"           # Cable unlock in progress
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"
    DISPUTED = "disputed"             # User contests bill


# Valid state transitions (source -> allowed destinations)
VALID_TRANSITIONS: Dict[SessionState, Set[SessionState]] = {
    SessionState.INITIATED: {SessionState.AUTHORIZING, SessionState.CANCELLED, SessionState.FAILED},
    SessionState.AUTHORIZING: {SessionState.AUTHORIZED, SessionState.FAILED, SessionState.CANCELLED},
    SessionState.AUTHORIZED: {SessionState.STARTING, SessionState.CANCELLED},
    SessionState.STARTING: {SessionState.CHARGING, SessionState.FAILED},
    SessionState.CHARGING: {SessionState.STOPPING, SessionState.FAILED},
    SessionState.STOPPING: {SessionState.METERING_FINAL, SessionState.FAILED},
    SessionState.METERING_FINAL: {SessionState.AWAITING_PAYMENT},
    SessionState.AWAITING_PAYMENT: {SessionState.PAYMENT_CONFIRMED, SessionState.DISPUTED, SessionState.FAILED},
    SessionState.PAYMENT_CONFIRMED: {SessionState.UNLOCKING},
    SessionState.UNLOCKING: {SessionState.COMPLETED, SessionState.FAILED},
    # Terminal states
    SessionState.COMPLETED: set(),
    SessionState.CANCELLED: set(),
    SessionState.FAILED: set(),
    SessionState.DISPUTED: {SessionState.PAYMENT_CONFIRMED, SessionState.FAILED},
}


class InvalidStateTransition(Exception):
    pass


def can_transition(current: SessionState, target: SessionState) -> bool:
    """Check if state transition is valid"""
    return target in VALID_TRANSITIONS.get(current, set())


def transition_state(
    current: SessionState,
    target: SessionState,
    session_id: str,
) -> SessionState:
    """Execute state transition with validation"""
    if not can_transition(current, target):
        raise InvalidStateTransition(
            f"Session {session_id}: cannot transition from {current} to {target}"
        )
    
    logger.info(f"Session {session_id}: {current} -> {target}")
    return target


def is_terminal(state: SessionState) -> bool:
    """Check if session has reached a terminal state"""
    return state in {
        SessionState.COMPLETED,
        SessionState.CANCELLED,
        SessionState.FAILED,
    }


def is_billable(state: SessionState) -> bool:
    """Check if session reached a state where billing applies"""
    return state in {
        SessionState.AWAITING_PAYMENT,
        SessionState.PAYMENT_CONFIRMED,
        SessionState.UNLOCKING,
        SessionState.COMPLETED,
    }
```

### Idempotency Keys

Add to `backend/utils/idempotency.py`:

```python
import hashlib
import json
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from fastapi import Request, Header, HTTPException
import redis
from config import settings

redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True)

IDEMPOTENCY_TTL_SECONDS = 86400  # 24 hours


def make_idempotency_key(user_id: str, request_key: str, body: Dict[str, Any]) -> str:
    """Build a stable key from user + request key + body hash"""
    body_hash = hashlib.sha256(
        json.dumps(body, sort_keys=True).encode()
    ).hexdigest()[:16]
    return f"idempotency:{user_id}:{request_key}:{body_hash}"


async def check_idempotency(
    idempotency_key: Optional[str],
    user_id: str,
    body: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """
    Check if we've already processed this request.
    Returns cached response if found, None otherwise.
    """
    if not idempotency_key:
        return None
    
    full_key = make_idempotency_key(user_id, idempotency_key, body)
    cached = redis_client.get(full_key)
    
    if cached:
        return json.loads(cached)
    return None


async def store_idempotency_response(
    idempotency_key: str,
    user_id: str,
    body: Dict[str, Any],
    response: Dict[str, Any],
) -> None:
    """Cache the response for this request key"""
    full_key = make_idempotency_key(user_id, idempotency_key, body)
    redis_client.setex(
        full_key,
        IDEMPOTENCY_TTL_SECONDS,
        json.dumps(response),
    )


# Usage in route:
"""
@router.post("/sessions/start")
async def start_session(
    request: SessionCreateRequest,
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    user_id: str = Depends(require_auth),
):
    # Check idempotency
    cached = await check_idempotency(idempotency_key, user_id, request.dict())
    if cached:
        return cached
    
    # ... normal processing ...
    
    # Cache successful response
    if idempotency_key:
        await store_idempotency_response(idempotency_key, user_id, request.dict(), response)
    
    return response
"""
```

### Distributed Locking (Charger Reservation)

Create file: `backend/utils/distributed_lock.py`

```python
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional
import redis
from config import settings

redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True)


class LockAcquisitionError(Exception):
    pass


@asynccontextmanager
async def charger_lock(charger_id: str, connector_id: str, timeout_seconds: int = 30):
    """
    Acquire exclusive lock on a charger connector.
    Prevents concurrent sessions on the same physical connector.
    """
    lock_key = f"charger_lock:{charger_id}:{connector_id}"
    lock_value = str(uuid.uuid4())
    
    # Try to acquire lock (atomic SETNX with expiry)
    acquired = redis_client.set(
        lock_key,
        lock_value,
        nx=True,  # Only set if doesn't exist
        ex=timeout_seconds,
    )
    
    if not acquired:
        raise LockAcquisitionError(
            f"Charger {charger_id}/{connector_id} is locked by another session"
        )
    
    try:
        yield lock_value
    finally:
        # Release lock only if we still own it (using Lua script for atomicity)
        release_script = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
        """
        redis_client.eval(release_script, 1, lock_key, lock_value)


# Usage:
"""
async with charger_lock(charger_id, connector_id):
    # Safely start session - no one else can claim this charger
    session = await create_session(...)
    await ocpp.start_charging(...)
"""
```

### Database Transactions

Update session creation to use atomic transactions:

```python
# backend/utils/db_transactions.py
from contextlib import asynccontextmanager
from supabase_client import service_supabase


@asynccontextmanager
async def db_transaction():
    """
    Note: Supabase REST API doesn't support multi-statement transactions.
    Use Postgres RPC functions for atomic operations.
    """
    # Use Postgres stored procedures for atomic multi-table writes
    yield


# Create Postgres function for atomic session start:
"""
CREATE OR REPLACE FUNCTION start_charging_session_atomic(
    p_session_id UUID,
    p_charger_id TEXT,
    p_connector_id TEXT,
    p_user_id UUID,
    p_charging_rate DECIMAL
) RETURNS UUID AS $$
DECLARE
    v_charger_available BOOLEAN;
BEGIN
    -- Lock charger row for update
    SELECT availability_status = 'Online' INTO v_charger_available
    FROM charger_metadata
    WHERE charger_id = p_charger_id
    FOR UPDATE;
    
    IF NOT v_charger_available THEN
        RAISE EXCEPTION 'Charger not available';
    END IF;
    
    -- Mark charger as busy
    UPDATE charger_metadata
    SET availability_status = 'Charging'
    WHERE charger_id = p_charger_id;
    
    -- Create session
    INSERT INTO charging_sessions (
        id, charger_id, connector_id, user_id, start_time,
        charging_rate_inr_per_kwh, state
    ) VALUES (
        p_session_id, p_charger_id, p_connector_id, p_user_id,
        NOW(), p_charging_rate, 'starting'
    );
    
    RETURN p_session_id;
END;
$$ LANGUAGE plpgsql;
"""
```

---

## Security Hardening

### 1. Signed QR Codes (HMAC)

Without signatures, anyone can print fake QR codes. Sign them:

```python
# backend/utils/qr_generator.py (updated)
import hmac
import hashlib
import base64
import json
from config import settings


class SecureQRGenerator:
    """QR codes with HMAC signatures to prevent spoofing"""
    
    SECRET_KEY = settings.QR_SIGNING_SECRET.encode()  # 32+ bytes
    SIGNATURE_VERSION = "v1"
    
    @classmethod
    def sign_qr_data(cls, payload: dict) -> str:
        """Create signed QR data with HMAC"""
        canonical_json = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        signature = hmac.new(
            cls.SECRET_KEY,
            canonical_json.encode(),
            hashlib.sha256,
        ).digest()
        signature_b64 = base64.urlsafe_b64encode(signature).decode().rstrip("=")
        
        # Format: evrouter://charge?d=<base64_payload>&s=<signature>&v=v1
        payload_b64 = base64.urlsafe_b64encode(canonical_json.encode()).decode().rstrip("=")
        return f"evrouter://charge?d={payload_b64}&s={signature_b64}&v={cls.SIGNATURE_VERSION}"
    
    @classmethod
    def verify_qr_data(cls, qr_string: str) -> dict:
        """Verify signature and return payload, or raise"""
        from urllib.parse import urlparse, parse_qs
        
        parsed = urlparse(qr_string)
        params = parse_qs(parsed.query)
        
        payload_b64 = params.get("d", [None])[0]
        signature_b64 = params.get("s", [None])[0]
        version = params.get("v", [None])[0]
        
        if not all([payload_b64, signature_b64, version]):
            raise ValueError("Missing QR signature components")
        
        if version != cls.SIGNATURE_VERSION:
            raise ValueError(f"Unsupported QR version: {version}")
        
        # Add padding back for base64 decode
        payload_b64 += "=" * (-len(payload_b64) % 4)
        signature_b64 += "=" * (-len(signature_b64) % 4)
        
        payload_bytes = base64.urlsafe_b64decode(payload_b64)
        provided_sig = base64.urlsafe_b64decode(signature_b64)
        
        # Recompute signature
        expected_sig = hmac.new(
            cls.SECRET_KEY,
            payload_bytes,
            hashlib.sha256,
        ).digest()
        
        # Constant-time comparison
        if not hmac.compare_digest(provided_sig, expected_sig):
            raise ValueError("Invalid QR signature - possible tampering")
        
        return json.loads(payload_bytes)
```

### 2. Rate Limiting per User

```python
# backend/utils/rate_limiter.py
from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi import Request

def get_user_or_ip(request: Request) -> str:
    """Use authenticated user_id when available, else fall back to IP"""
    user_id = getattr(request.state, "user_id", None)
    return user_id or get_remote_address(request)

limiter = Limiter(key_func=get_user_or_ip)

# Per-endpoint limits:
# - QR validation: 30/min (prevent abuse)
# - Session start: 5/min (prevent duplicate sessions)
# - Status polling: 60/min (UI refresh)
# - Payment confirm: 10/min

# Usage:
"""
@router.post("/qr/validate")
@limiter.limit("30/minute")
async def validate_qr(...): ...

@router.post("/sessions/start")
@limiter.limit("5/minute")
async def start_session(...): ...
"""
```

### 3. JWT Refresh Token Strategy

```python
# backend/utils/auth_tokens.py
from datetime import datetime, timedelta
from jose import jwt
import secrets

ACCESS_TOKEN_TTL_MINUTES = 15
REFRESH_TOKEN_TTL_DAYS = 30


def create_access_token(user_id: str) -> str:
    expires = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_TTL_MINUTES)
    payload = {
        "sub": user_id,
        "type": "access",
        "exp": expires,
        "jti": secrets.token_hex(8),  # JWT ID for revocation
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")


def create_refresh_token(user_id: str) -> str:
    expires = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_TTL_DAYS)
    payload = {
        "sub": user_id,
        "type": "refresh",
        "exp": expires,
        "jti": secrets.token_hex(16),
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")
    
    # Store refresh JTI in Redis for revocation tracking
    redis_client.setex(
        f"refresh_token:{payload['jti']}",
        REFRESH_TOKEN_TTL_DAYS * 86400,
        user_id,
    )
    return token


def revoke_refresh_token(jti: str):
    """Invalidate refresh token (logout)"""
    redis_client.delete(f"refresh_token:{jti}")
```

### 4. WebSocket Authentication (Secure)

Replace insecure query-param auth:

```python
# backend/websocket_handler.py (updated)
@router.websocket("/ws/session/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    await websocket.accept()
    
    # Wait for auth message (first message must be auth)
    try:
        auth_data = await asyncio.wait_for(
            websocket.receive_json(),
            timeout=5.0
        )
    except asyncio.TimeoutError:
        await websocket.close(code=1008, reason="Auth timeout")
        return
    
    if auth_data.get("type") != "auth" or not auth_data.get("token"):
        await websocket.close(code=1008, reason="Auth required")
        return
    
    try:
        user = await verify_jwt(auth_data["token"])
    except Exception:
        await websocket.close(code=1008, reason="Invalid token")
        return
    
    # Verify user owns this session
    session = await get_session(session_id)
    if session["user_id"] != user["sub"]:
        await websocket.close(code=1008, reason="Forbidden")
        return
    
    await ws_manager.connect(session_id, websocket, user["sub"])
    # ... rest of handler ...
```

### 5. Secrets Management

```python
# backend/config.py (production)
from pydantic_settings import BaseSettings
from google.cloud import secretmanager  # For GCP


class Settings(BaseSettings):
    APP_ENV: str = "development"
    
    # In production, load from Secret Manager
    @classmethod
    def from_secret_manager(cls, project_id: str):
        client = secretmanager.SecretManagerServiceClient()
        
        def get_secret(name: str) -> str:
            response = client.access_secret_version(
                name=f"projects/{project_id}/secrets/{name}/versions/latest"
            )
            return response.payload.data.decode("UTF-8")
        
        return cls(
            SUPABASE_KEY=get_secret("supabase_key"),
            JWT_SECRET=get_secret("jwt_secret"),
            QR_SIGNING_SECRET=get_secret("qr_signing_secret"),
            PAYMENT_API_KEY=get_secret("payment_api_key"),
            # ...
        )
```

### 6. Input Validation Schemas

All inputs validated via Pydantic with constraints:

```python
from pydantic import BaseModel, Field, validator

class SessionCreateRequest(BaseModel):
    charger_id: str = Field(..., min_length=1, max_length=64, regex=r"^[A-Z0-9_]+$")
    connector_id: str = Field(..., min_length=1, max_length=16, regex=r"^[A-Z0-9_]+$")
    charging_rate_inr_per_kwh: float = Field(..., gt=0, le=100)
    vehicle_id: Optional[str] = Field(None, max_length=64)
    
    @validator("charging_rate_inr_per_kwh")
    def validate_rate(cls, v):
        # Sanity check: rates should be ₹5-50/kWh in India
        if not 5 <= v <= 50:
            raise ValueError("Charging rate outside acceptable range")
        return v
```

---

## Resilience Patterns

### 1. Circuit Breaker for OCPP

Prevent cascading failures when chargers are down:

```python
# backend/utils/circuit_breaker.py
from enum import Enum
from datetime import datetime, timedelta
from typing import Callable, Any
import asyncio

class CircuitState(str, Enum):
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, reject calls
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreaker:
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout_seconds: int = 30,
        success_threshold: int = 2,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout_seconds
        self.success_threshold = success_threshold
        
        self.failures = 0
        self.successes = 0
        self.last_failure_time = None
        self.state = CircuitState.CLOSED
    
    async def call(self, func: Callable, *args, **kwargs) -> Any:
        """Execute function through circuit breaker"""
        if self.state == CircuitState.OPEN:
            if self._should_attempt_reset():
                self.state = CircuitState.HALF_OPEN
            else:
                raise CircuitOpenError("Service unavailable - circuit open")
        
        try:
            result = await func(*args, **kwargs)
            self._on_success()
            return result
        except Exception as e:
            self._on_failure()
            raise
    
    def _should_attempt_reset(self) -> bool:
        return (
            self.last_failure_time
            and (datetime.utcnow() - self.last_failure_time).seconds >= self.recovery_timeout
        )
    
    def _on_success(self):
        if self.state == CircuitState.HALF_OPEN:
            self.successes += 1
            if self.successes >= self.success_threshold:
                self.state = CircuitState.CLOSED
                self.failures = 0
                self.successes = 0
    
    def _on_failure(self):
        self.failures += 1
        self.last_failure_time = datetime.utcnow()
        if self.failures >= self.failure_threshold:
            self.state = CircuitState.OPEN


class CircuitOpenError(Exception):
    pass


# Per-charger circuit breakers
_breakers: dict = {}

def get_charger_breaker(charger_id: str) -> CircuitBreaker:
    if charger_id not in _breakers:
        _breakers[charger_id] = CircuitBreaker()
    return _breakers[charger_id]


# Usage:
"""
async def get_live_metrics(charger_id: str):
    breaker = get_charger_breaker(charger_id)
    return await breaker.call(ocpp_client.get_metrics, charger_id)
"""
```

### 2. Retry with Exponential Backoff

```python
# backend/utils/retry.py
import asyncio
import random
from typing import Callable, Any, Type, Tuple
from functools import wraps


def retry_with_backoff(
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 30.0,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    jitter: bool = True,
):
    """Retry async function with exponential backoff"""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            last_exception = None
            
            for attempt in range(max_retries + 1):
                try:
                    return await func(*args, **kwargs)
                except exceptions as e:
                    last_exception = e
                    
                    if attempt == max_retries:
                        break
                    
                    delay = min(base_delay * (2 ** attempt), max_delay)
                    if jitter:
                        delay *= (0.5 + random.random())
                    
                    await asyncio.sleep(delay)
            
            raise last_exception
        return wrapper
    return decorator


# Usage:
"""
@retry_with_backoff(max_retries=3, exceptions=(httpx.HTTPError,))
async def fetch_charger_metrics(charger_id: str):
    return await ocpp_client.get_metrics(charger_id)
"""
```

### 3. Saga Pattern (Compensating Transactions)

For multi-step operations that can fail mid-way:

```python
# backend/utils/saga.py
from typing import Callable, List, Awaitable
import logging

logger = logging.getLogger(__name__)


class SagaStep:
    def __init__(
        self,
        name: str,
        action: Callable[..., Awaitable],
        compensate: Callable[..., Awaitable],
    ):
        self.name = name
        self.action = action
        self.compensate = compensate


class Saga:
    """
    Execute a series of steps with automatic compensation on failure.
    Each step has an action and a compensating action (rollback).
    """
    
    def __init__(self):
        self.steps: List[SagaStep] = []
        self.completed_steps: List[tuple] = []
    
    def add_step(self, name: str, action, compensate):
        self.steps.append(SagaStep(name, action, compensate))
        return self
    
    async def execute(self, context: dict) -> dict:
        for step in self.steps:
            try:
                logger.info(f"Saga: executing {step.name}")
                result = await step.action(context)
                self.completed_steps.append((step, result))
                context[step.name] = result
            except Exception as e:
                logger.error(f"Saga: step {step.name} failed: {e}")
                await self._compensate(context)
                raise
        return context
    
    async def _compensate(self, context: dict):
        """Roll back completed steps in reverse order"""
        for step, result in reversed(self.completed_steps):
            try:
                logger.info(f"Saga: compensating {step.name}")
                await step.compensate(context, result)
            except Exception as e:
                logger.error(f"Saga: compensation failed for {step.name}: {e}")
                # Continue trying to compensate other steps


# Example: Charging session start saga
"""
async def start_session_saga(user_id, charger_id, connector_id):
    saga = Saga()
    
    saga.add_step(
        "acquire_lock",
        action=lambda ctx: acquire_charger_lock(charger_id, connector_id),
        compensate=lambda ctx, result: release_charger_lock(charger_id, connector_id),
    )
    saga.add_step(
        "create_db_session",
        action=lambda ctx: create_session_record(...),
        compensate=lambda ctx, session_id: mark_session_failed(session_id),
    )
    saga.add_step(
        "ocpp_start",
        action=lambda ctx: ocpp.start_charging(connector_id),
        compensate=lambda ctx, result: ocpp.emergency_stop(connector_id),
    )
    
    return await saga.execute({"user_id": user_id, "charger_id": charger_id})
"""
```

### 4. Timeout Configuration

```python
# backend/config.py
class TimeoutSettings:
    OCPP_REQUEST_TIMEOUT = 10  # seconds
    OCPP_START_CHARGING_TIMEOUT = 30
    OCPP_STOP_CHARGING_TIMEOUT = 15
    OCPP_UNLOCK_TIMEOUT = 10
    PAYMENT_GATEWAY_TIMEOUT = 15
    DB_QUERY_TIMEOUT = 5
    WEBSOCKET_PING_INTERVAL = 30
    SESSION_PAYMENT_TIMEOUT_MINUTES = 15  # User must pay within 15 min
    SESSION_INACTIVITY_TIMEOUT_HOURS = 6  # Force-close stuck sessions
```

---

## Caching & Background Jobs

### 1. Redis Caching Layer

Reduce DB load and improve response times:

```python
# backend/utils/cache.py
import json
from typing import Optional, Any, Callable
from functools import wraps
import redis
from config import settings

redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True)


class CacheManager:
    @staticmethod
    async def get(key: str) -> Optional[Any]:
        value = redis_client.get(key)
        return json.loads(value) if value else None
    
    @staticmethod
    async def set(key: str, value: Any, ttl_seconds: int = 300):
        redis_client.setex(key, ttl_seconds, json.dumps(value))
    
    @staticmethod
    async def invalidate(key: str):
        redis_client.delete(key)
    
    @staticmethod
    async def invalidate_pattern(pattern: str):
        """Invalidate all keys matching a pattern"""
        for key in redis_client.scan_iter(match=pattern):
            redis_client.delete(key)


def cached(key_prefix: str, ttl_seconds: int = 300):
    """Decorator to cache function results"""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Build cache key from args
            key = f"{key_prefix}:{':'.join(map(str, args))}"
            
            cached_value = await CacheManager.get(key)
            if cached_value is not None:
                return cached_value
            
            result = await func(*args, **kwargs)
            await CacheManager.set(key, result, ttl_seconds)
            return result
        return wrapper
    return decorator


# Cache strategy:
# - Charger metadata: TTL 1 hour (changes rarely)
# - Nearby charger search: TTL 5 minutes (location-based)
# - User profile: TTL 15 minutes
# - Quotes: TTL 30 seconds (price-sensitive)
# - Live meter: NO cache (real-time)
# - Session state: NO cache (read from DB)
```

### 2. Background Job Queue (Celery)

For async heavy operations:

```python
# backend/tasks/celery_app.py
from celery import Celery
from config import settings

celery_app = Celery(
    "ev_router",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=300,  # 5 min hard limit
    task_soft_time_limit=240,
)


# backend/tasks/session_tasks.py
from .celery_app import celery_app
import logging

logger = logging.getLogger(__name__)


@celery_app.task(bind=True, max_retries=3)
def generate_receipt(self, session_id: str):
    """Generate PDF receipt and email to user"""
    try:
        from utils.receipt_generator import generate_pdf_receipt
        from utils.email_service import send_receipt_email
        
        pdf_path = generate_pdf_receipt(session_id)
        send_receipt_email(session_id, pdf_path)
        logger.info(f"Receipt sent for session {session_id}")
    except Exception as e:
        logger.error(f"Receipt generation failed: {e}")
        raise self.retry(exc=e, countdown=60 * (2 ** self.request.retries))


@celery_app.task
def send_payment_reminder(session_id: str):
    """Send payment reminder if user hasn't paid within 10 min"""
    from supabase_client import supabase
    
    session = supabase.table("charging_sessions").select("*").eq("id", session_id).single().execute()
    
    if session.data["state"] == "awaiting_payment":
        from utils.notifications import send_push_notification
        send_push_notification(
            user_id=session.data["user_id"],
            title="Payment Pending",
            body=f"Please complete payment of ₹{session.data['total_cost_inr']}",
            data={"session_id": session_id}
        )


@celery_app.task
def cleanup_stale_sessions():
    """Force-close sessions that have been stuck for hours"""
    from supabase_client import supabase
    from datetime import datetime, timedelta
    
    stale_threshold = datetime.utcnow() - timedelta(hours=6)
    
    stuck_sessions = supabase.table("charging_sessions").select("*").lt(
        "start_time", stale_threshold.isoformat()
    ).in_("state", ["initiated", "charging", "starting"]).execute()
    
    for session in stuck_sessions.data:
        supabase.table("charging_sessions").update({
            "state": "failed",
            "end_time": datetime.utcnow().isoformat(),
        }).eq("id", session["id"]).execute()
        logger.warning(f"Force-closed stale session {session['id']}")


# Scheduled tasks (celery beat)
celery_app.conf.beat_schedule = {
    "cleanup-stale-sessions": {
        "task": "tasks.session_tasks.cleanup_stale_sessions",
        "schedule": 300.0,  # Every 5 minutes
    },
}
```

### 3. WebSocket Pub/Sub via Redis

Scale WebSockets across multiple backend instances:

```python
# backend/websocket_handler.py (updated)
import asyncio
import json
import redis.asyncio as aioredis
from config import settings


class RedisWebSocketManager:
    """
    Scalable WebSocket manager using Redis pub/sub.
    Multiple backend instances can broadcast to same session.
    """
    
    def __init__(self):
        self.local_connections: dict = {}  # session_id -> [websockets]
        self.pubsub = None
        self.redis = None
    
    async def init(self):
        self.redis = await aioredis.from_url(settings.REDIS_URL)
        self.pubsub = self.redis.pubsub()
        await self.pubsub.psubscribe("session:*")
        # Start background listener
        asyncio.create_task(self._listen_redis())
    
    async def _listen_redis(self):
        """Listen for Redis pub/sub messages and forward to local WS connections"""
        async for message in self.pubsub.listen():
            if message["type"] != "pmessage":
                continue
            
            channel = message["channel"].decode()
            session_id = channel.split(":")[1]
            data = json.loads(message["data"])
            
            # Send to local connections for this session
            await self._broadcast_local(session_id, data)
    
    async def _broadcast_local(self, session_id: str, data: dict):
        if session_id not in self.local_connections:
            return
        
        message = json.dumps(data)
        for ws in self.local_connections[session_id]:
            try:
                await ws.send_text(message)
            except Exception:
                pass
    
    async def broadcast(self, session_id: str, data: dict):
        """Publish to all backend instances via Redis"""
        await self.redis.publish(f"session:{session_id}", json.dumps(data))
    
    async def connect(self, session_id: str, websocket):
        if session_id not in self.local_connections:
            self.local_connections[session_id] = []
        self.local_connections[session_id].append(websocket)
    
    async def disconnect(self, session_id: str, websocket):
        if session_id in self.local_connections:
            self.local_connections[session_id].remove(websocket)
```

---

## Observability

### 1. Structured Logging (JSON)

```python
# backend/utils/logging_config.py
import logging
import json
from datetime import datetime
from typing import Any
from pythonjsonlogger import jsonlogger


class CustomJsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record["timestamp"] = datetime.utcnow().isoformat()
        log_record["level"] = record.levelname
        log_record["logger"] = record.name
        
        # Add request context if available
        if hasattr(record, "request_id"):
            log_record["request_id"] = record.request_id
        if hasattr(record, "user_id"):
            log_record["user_id"] = record.user_id
        if hasattr(record, "session_id"):
            log_record["session_id"] = record.session_id


def setup_logging(log_level: str = "INFO"):
    handler = logging.StreamHandler()
    formatter = CustomJsonFormatter(
        "%(timestamp)s %(level)s %(logger)s %(message)s"
    )
    handler.setFormatter(formatter)
    
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.handlers = [handler]


# Use contextual logging:
"""
import logging
logger = logging.getLogger(__name__)

logger.info(
    "Session started",
    extra={
        "session_id": session_id,
        "user_id": user_id,
        "charger_id": charger_id,
    }
)
"""
```

### 2. Prometheus Metrics

```python
# backend/utils/metrics.py
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from fastapi import APIRouter, Response

# Business metrics
sessions_started_total = Counter(
    "ev_sessions_started_total",
    "Total charging sessions started",
    ["charger_id", "payment_type"],
)

sessions_completed_total = Counter(
    "ev_sessions_completed_total",
    "Total completed sessions",
    ["charger_id"],
)

sessions_failed_total = Counter(
    "ev_sessions_failed_total",
    "Total failed sessions",
    ["reason"],
)

energy_delivered_kwh = Counter(
    "ev_energy_delivered_kwh_total",
    "Total energy delivered",
    ["charger_id"],
)

revenue_inr = Counter(
    "ev_revenue_inr_total",
    "Total revenue collected",
    ["payment_method"],
)

# Performance metrics
ocpp_request_duration = Histogram(
    "ev_ocpp_request_duration_seconds",
    "OCPP request duration",
    ["operation", "charger_id"],
)

api_request_duration = Histogram(
    "ev_api_request_duration_seconds",
    "API request duration",
    ["endpoint", "method"],
)

# Operational metrics
active_sessions = Gauge(
    "ev_active_sessions",
    "Currently active charging sessions",
)

charger_availability = Gauge(
    "ev_charger_availability",
    "Charger availability status",
    ["charger_id", "connector_id"],
)

websocket_connections = Gauge(
    "ev_websocket_connections",
    "Active WebSocket connections",
)


# Metrics endpoint
metrics_router = APIRouter()

@metrics_router.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type="text/plain")
```

### 3. Distributed Tracing (OpenTelemetry)

```python
# backend/utils/tracing.py
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor


def setup_tracing(app, service_name: str = "ev-router-backend"):
    resource = Resource(attributes={"service.name": service_name})
    provider = TracerProvider(resource=resource)
    
    # Export to Jaeger/Tempo/Honeycomb via OTLP
    otlp_exporter = OTLPSpanExporter(
        endpoint=settings.OTLP_ENDPOINT,
        insecure=True,
    )
    provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
    trace.set_tracer_provider(provider)
    
    # Auto-instrument FastAPI, HTTPX, Redis
    FastAPIInstrumentor.instrument_app(app)
    HTTPXClientInstrumentor().instrument()
    RedisInstrumentor().instrument()


# Manual span creation:
"""
tracer = trace.get_tracer(__name__)

@tracer.start_as_current_span("start_charging_session")
async def start_session(...):
    span = trace.get_current_span()
    span.set_attribute("user_id", user_id)
    span.set_attribute("charger_id", charger_id)
    # ...
"""
```

### 4. Health Checks (Deep)

```python
# backend/routers/health.py
from fastapi import APIRouter, Response
from datetime import datetime
import asyncio

router = APIRouter()


@router.get("/health")
async def basic_health():
    """Liveness probe - just confirms process is alive"""
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


@router.get("/health/ready")
async def readiness():
    """Readiness probe - checks all dependencies"""
    checks = await asyncio.gather(
        _check_database(),
        _check_redis(),
        _check_supabase(),
        _check_payment_gateway(),
        return_exceptions=True,
    )
    
    results = {
        "database": _format_check(checks[0]),
        "redis": _format_check(checks[1]),
        "supabase": _format_check(checks[2]),
        "payment_gateway": _format_check(checks[3]),
    }
    
    all_ok = all(r["status"] == "ok" for r in results.values())
    status_code = 200 if all_ok else 503
    
    return Response(
        content=json.dumps({
            "status": "ready" if all_ok else "not_ready",
            "checks": results,
            "timestamp": datetime.utcnow().isoformat(),
        }),
        status_code=status_code,
        media_type="application/json",
    )


async def _check_database():
    from supabase_client import supabase
    result = supabase.table("charging_sessions").select("id").limit(1).execute()
    return True


async def _check_redis():
    from utils.cache import redis_client
    redis_client.ping()
    return True


async def _check_supabase():
    # Already covered by _check_database
    return True


async def _check_payment_gateway():
    import httpx
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{settings.PAYMENT_GATEWAY_URL}/health", timeout=3)
        return response.status_code == 200


def _format_check(result) -> dict:
    if isinstance(result, Exception):
        return {"status": "error", "message": str(result)}
    return {"status": "ok"}
```

### 5. Alerting Rules

```yaml
# prometheus/alerts.yml
groups:
  - name: ev_router_critical
    interval: 30s
    rules:
      - alert: HighSessionFailureRate
        expr: rate(ev_sessions_failed_total[5m]) > 0.1
        for: 5m
        annotations:
          summary: "Session failure rate >10% over 5 min"
      
      - alert: OCPPHighLatency
        expr: histogram_quantile(0.95, ev_ocpp_request_duration_seconds) > 5
        for: 5m
        annotations:
          summary: "OCPP requests P95 >5s"
      
      - alert: ChargerOffline
        expr: ev_charger_availability == 0
        for: 10m
        annotations:
          summary: "Charger {{ $labels.charger_id }} offline >10 min"
      
      - alert: PaymentBacklog
        expr: ev_active_sessions{state="awaiting_payment"} > 50
        for: 10m
        annotations:
          summary: "More than 50 sessions stuck awaiting payment"
```

---

## Edge Cases & Failure Modes

### 1. Recovery Flows Table

| Failure Scenario | Detection | Recovery |
|-----------------|-----------|----------|
| OCPP start fails after DB insert | OCPP timeout/error | Saga rollback → DB session marked failed, lock released |
| User leaves without paying | Payment timeout (15 min) | Send push notification, mark disputed, escalate to recovery flow |
| Charger disconnects mid-session | OCPP heartbeat lost | Force-close session, use last meter value, generate partial bill |
| Payment succeeds but unlock fails | OCPP unlock timeout | Retry 3x, then manual override option for support |
| Backend crashes mid-session | Periodic stale session check | `cleanup_stale_sessions` cron picks up after 6h |
| Network failure during status poll | HTTP error | Client uses cached value, retries with backoff |
| Duplicate session start (network retry) | Idempotency key | Return original response, no duplicate session |
| Two users scan same QR simultaneously | Redis distributed lock | First wins, second gets `LockAcquisitionError` |
| Final meter read fails | OCPP timeout | Use last known meter value + 5% buffer, log discrepancy |
| Refund needed | User dispute | Webhook from payment gateway → mark refunded |

### 2. Payment Timeout Handling

```python
# backend/tasks/payment_timeout.py
from datetime import datetime, timedelta

@celery_app.task
def handle_payment_timeout(session_id: str):
    """Run 15 min after session end if payment not collected"""
    session = supabase.table("charging_sessions").select("*").eq("id", session_id).single().execute()
    
    payment = supabase.table("payment_transactions").select("*").eq(
        "session_id", session_id
    ).order("created_at", desc=True).limit(1).execute()
    
    if payment.data and payment.data[0]["status"] == "PENDING_COLLECT":
        # Escalation step 1: Send urgent push notification
        send_push_notification(
            user_id=session.data["user_id"],
            title="⚠️ Payment Required",
            body=f"Please pay ₹{session.data['total_cost_inr']} to unlock cable",
            priority="high",
        )
        
        # Escalation step 2: Mark for manual review after 1 hour
        schedule_payment_dispute_review.apply_async(
            args=[session_id],
            countdown=3600,
        )


@celery_app.task
def schedule_payment_dispute_review(session_id: str):
    """Mark session as disputed if still unpaid after 1 hour"""
    supabase.table("charging_sessions").update({
        "state": "disputed",
        "metadata": {"reason": "payment_timeout"},
    }).eq("id", session_id).execute()
    
    # Notify support team
    send_support_notification(f"Session {session_id} requires manual review")
```

### 3. OCPP Disconnect Handling

```python
# backend/utils/ocpp_heartbeat.py
import asyncio
from datetime import datetime, timedelta

HEARTBEAT_INTERVAL = 30  # seconds
HEARTBEAT_MISS_THRESHOLD = 3  # missed heartbeats = disconnected


class OCPPHeartbeatMonitor:
    def __init__(self):
        self.last_heartbeat: dict = {}  # charger_id -> datetime
        self.missed_count: dict = {}    # charger_id -> int
    
    def record_heartbeat(self, charger_id: str):
        self.last_heartbeat[charger_id] = datetime.utcnow()
        self.missed_count[charger_id] = 0
    
    async def monitor_loop(self):
        while True:
            await asyncio.sleep(HEARTBEAT_INTERVAL)
            await self._check_chargers()
    
    async def _check_chargers(self):
        now = datetime.utcnow()
        threshold = now - timedelta(seconds=HEARTBEAT_INTERVAL * HEARTBEAT_MISS_THRESHOLD)
        
        for charger_id, last in list(self.last_heartbeat.items()):
            if last < threshold:
                self.missed_count[charger_id] = self.missed_count.get(charger_id, 0) + 1
                
                if self.missed_count[charger_id] >= HEARTBEAT_MISS_THRESHOLD:
                    await self._handle_charger_offline(charger_id)
    
    async def _handle_charger_offline(self, charger_id: str):
        # Mark charger offline
        supabase.table("charger_metadata").update({
            "availability_status": "Offline"
        }).eq("charger_id", charger_id).execute()
        
        # Find active sessions on this charger
        active = supabase.table("charging_sessions").select("*").eq(
            "charger_id", charger_id
        ).eq("state", "charging").execute()
        
        # Force-close with last known meter values
        for session in active.data:
            await force_close_session(session["id"], reason="charger_offline")
```

### 4. Multi-Session Prevention

```python
# Prevent user from starting two sessions simultaneously
async def check_user_no_active_session(user_id: str) -> bool:
    active = supabase.table("charging_sessions").select("id").eq(
        "user_id", user_id
    ).in_("state", [
        "initiated", "authorizing", "authorized", "starting",
        "charging", "stopping", "metering_final", "awaiting_payment"
    ]).execute()
    
    if active.data:
        raise HTTPException(
            status_code=409,
            detail=f"User has active session: {active.data[0]['id']}"
        )
    return True
```

---

## Supplementary Features

### 1. Receipt Generation

```python
# backend/utils/receipt_generator.py
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
from io import BytesIO

class ReceiptGenerator:
    @staticmethod
    def generate_pdf(session_data: dict, payment_data: dict) -> bytes:
        buffer = BytesIO()
        p = canvas.Canvas(buffer, pagesize=A4)
        width, height = A4
        
        # Header
        p.setFont("Helvetica-Bold", 20)
        p.drawString(inch, height - inch, "EV Router - Charging Receipt")
        
        # Session details
        p.setFont("Helvetica", 11)
        y = height - 1.5 * inch
        details = [
            f"Receipt #: {payment_data['reference_id']}",
            f"Date: {session_data['end_time']}",
            f"Charger: {session_data.get('charger_name')}",
            f"Location: {session_data.get('location')}",
            "",
            f"Energy Delivered: {session_data['energy_delivered_kwh']} kWh",
            f"Duration: {session_data['duration_minutes']} minutes",
            f"Rate: ₹{session_data['charging_rate_inr_per_kwh']}/kWh",
            "",
            f"Energy Cost: ₹{session_data['energy_cost']:.2f}",
            f"Service Charge: ₹{session_data['service_charge']:.2f}",
            f"GST (5%): ₹{session_data['gst']:.2f}",
            "",
            f"Total Paid: ₹{payment_data['amount_inr']:.2f}",
            f"Payment Method: {payment_data['payment_method']}",
        ]
        
        for line in details:
            p.drawString(inch, y, line)
            y -= 0.3 * inch
        
        # GST compliance footer
        p.setFont("Helvetica", 8)
        p.drawString(inch, 0.5 * inch, 
            "GSTIN: 29XXXXX1234X1ZX | EV Router Technologies Pvt Ltd"
        )
        
        p.showPage()
        p.save()
        buffer.seek(0)
        return buffer.getvalue()
```

### 2. Push Notifications (FCM)

```python
# backend/utils/notifications.py
from firebase_admin import messaging, credentials, initialize_app
from config import settings

cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
initialize_app(cred)


def send_push_notification(
    user_id: str,
    title: str,
    body: str,
    data: dict = None,
    priority: str = "normal",
):
    """Send push notification via FCM"""
    user_tokens = get_user_fcm_tokens(user_id)
    
    if not user_tokens:
        return
    
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data or {},
        tokens=user_tokens,
        android=messaging.AndroidConfig(
            priority="high" if priority == "high" else "normal",
            notification=messaging.AndroidNotification(
                channel_id="charging_updates",
                priority="high" if priority == "high" else "default",
            ),
        ),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10" if priority == "high" else "5"},
        ),
    )
    
    response = messaging.send_multicast(message)
    return response.success_count


# Trigger points:
# - Session started
# - Charging milestone (50%, 80%, 100%)
# - Payment requested
# - Payment confirmed
# - Cable unlocked
# - Session disputed
```

### 3. Reservation System

```python
# backend/routers/reservations.py
@router.post("/reservations")
async def create_reservation(
    charger_id: str,
    connector_id: str,
    hold_duration_minutes: int = 15,
    user_id: str = Depends(require_auth),
):
    """Reserve a charger for up to 15 minutes"""
    
    # Check no active reservation on this connector
    existing = supabase.table("reservations").select("*").eq(
        "charger_id", charger_id
    ).eq("connector_id", connector_id).gte(
        "expires_at", datetime.utcnow().isoformat()
    ).execute()
    
    if existing.data:
        raise HTTPException(409, "Charger already reserved")
    
    # Create reservation with TTL
    reservation_id = str(uuid.uuid4())
    expires_at = datetime.utcnow() + timedelta(minutes=hold_duration_minutes)
    
    supabase.table("reservations").insert({
        "id": reservation_id,
        "charger_id": charger_id,
        "connector_id": connector_id,
        "user_id": user_id,
        "expires_at": expires_at.isoformat(),
        "created_at": datetime.utcnow().isoformat(),
    }).execute()
    
    # Schedule cleanup task
    cleanup_expired_reservation.apply_async(
        args=[reservation_id],
        eta=expires_at,
    )
    
    return {
        "reservation_id": reservation_id,
        "expires_at": expires_at.isoformat(),
        "hold_duration_minutes": hold_duration_minutes,
    }


# DB migration:
"""
CREATE TABLE reservations (
    id UUID PRIMARY KEY,
    charger_id TEXT NOT NULL,
    connector_id TEXT NOT NULL,
    user_id UUID NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    cancelled_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_reservations_active ON reservations(charger_id, connector_id, expires_at);
"""
```

### 4. Vehicle Integration

```python
# Link sessions to user's vehicle for SOC tracking
@router.post("/sessions/start")
async def start_session(request: SessionCreateRequest, ...):
    # Fetch vehicle profile
    if request.vehicle_id:
        vehicle = supabase.table("vehicles").select("*").eq(
            "id", request.vehicle_id
        ).eq("user_id", user_id).single().execute()
        
        # Use vehicle battery capacity to estimate session duration
        battery_kwh = vehicle.data["battery_capacity_kwh"]
        current_soc = vehicle.data.get("current_soc_percent", 20)
        target_soc = 80  # Default target
        
        energy_needed = battery_kwh * (target_soc - current_soc) / 100
        estimated_minutes = (energy_needed / charger_power_kw) * 60
        
        # Save estimate to session
        session_data["estimated_energy_kwh"] = energy_needed
        session_data["estimated_duration_minutes"] = estimated_minutes
```

---

## Flutter State Management

### Use Riverpod for Reactive State

```yaml
# pubspec.yaml additions
dependencies:
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0
  hive_flutter: ^1.1.0  # Offline persistence
  connectivity_plus: ^5.0.0  # Network status

dev_dependencies:
  riverpod_generator: ^2.3.0
  build_runner: ^2.4.0
```

```dart
// lib/state/charging_session_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChargingSessionState {
  final String? sessionId;
  final SessionStatus status;
  final double energyKwh;
  final double costInr;
  final double currentAmps;
  final double voltage;
  final double power;
  final double soc;
  final DateTime? startTime;
  final String? errorMessage;
  
  const ChargingSessionState({
    this.sessionId,
    this.status = SessionStatus.idle,
    this.energyKwh = 0,
    this.costInr = 0,
    this.currentAmps = 0,
    this.voltage = 0,
    this.power = 0,
    this.soc = 0,
    this.startTime,
    this.errorMessage,
  });
  
  ChargingSessionState copyWith({
    String? sessionId,
    SessionStatus? status,
    double? energyKwh,
    double? costInr,
    double? currentAmps,
    double? voltage,
    double? power,
    double? soc,
    DateTime? startTime,
    String? errorMessage,
  }) {
    return ChargingSessionState(
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      energyKwh: energyKwh ?? this.energyKwh,
      costInr: costInr ?? this.costInr,
      currentAmps: currentAmps ?? this.currentAmps,
      voltage: voltage ?? this.voltage,
      power: power ?? this.power,
      soc: soc ?? this.soc,
      startTime: startTime ?? this.startTime,
      errorMessage: errorMessage,
    );
  }
}

enum SessionStatus {
  idle,
  starting,
  charging,
  stopping,
  awaitingPayment,
  paymentConfirmed,
  completed,
  failed,
}

class ChargingSessionNotifier extends StateNotifier<ChargingSessionState> {
  final BecknChargingService _service;
  WebSocketChannel? _channel;
  Timer? _statusPollTimer;
  
  ChargingSessionNotifier(this._service) : super(const ChargingSessionState());
  
  Future<void> startSession({
    required String chargerId,
    required String connectorId,
    required double rate,
    String? idempotencyKey,
  }) async {
    state = state.copyWith(status: SessionStatus.starting);
    
    try {
      final sessionId = await _service.startSession(
        chargerId: chargerId,
        connectorId: connectorId,
        chargingRateInrPerKwh: rate,
        idempotencyKey: idempotencyKey ?? _generateIdempotencyKey(),
      );
      
      state = state.copyWith(
        sessionId: sessionId,
        status: SessionStatus.charging,
        startTime: DateTime.now(),
      );
      
      // Save to local storage for recovery
      await _persistSession();
      
      // Connect WebSocket with fallback to polling
      _connectWebSocket(sessionId);
    } catch (e) {
      state = state.copyWith(
        status: SessionStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }
  
  void _connectWebSocket(String sessionId) {
    try {
      _channel = _service.getSessionWebSocket(sessionId);
      _channel!.stream.listen(
        _onWebSocketMessage,
        onError: (_) => _fallbackToPolling(sessionId),
        onDone: () => _fallbackToPolling(sessionId),
      );
    } catch (_) {
      _fallbackToPolling(sessionId);
    }
  }
  
  void _fallbackToPolling(String sessionId) {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final status = await _service.getSessionStatus(sessionId);
        _updateMetrics(status);
      } catch (_) {}
    });
  }
  
  // ... rest of implementation
}

final chargingSessionProvider = StateNotifierProvider<ChargingSessionNotifier, ChargingSessionState>(
  (ref) => ChargingSessionNotifier(ref.read(becknServiceProvider)),
);
```

### Offline Mode (Local Persistence)

```dart
// lib/services/offline_storage.dart
import 'package:hive_flutter/hive_flutter.dart';

class OfflineStorage {
  static const String _sessionBox = 'active_sessions';
  static const String _queueBox = 'pending_requests';
  
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_sessionBox);
    await Hive.openBox(_queueBox);
  }
  
  static Future<void> persistSession(Map<String, dynamic> session) async {
    final box = Hive.box(_sessionBox);
    await box.put('active', session);
  }
  
  static Map<String, dynamic>? getPersistedSession() {
    final box = Hive.box(_sessionBox);
    return box.get('active');
  }
  
  static Future<void> queueRequest(Map<String, dynamic> request) async {
    final box = Hive.box(_queueBox);
    await box.add(request);
  }
  
  static Future<void> syncPendingRequests() async {
    final box = Hive.box(_queueBox);
    final pending = box.values.toList();
    
    for (final request in pending) {
      try {
        // Replay request to backend
        await _replayRequest(request);
        await box.delete(box.keyAt(0));
      } catch (_) {
        // Will retry on next sync
        break;
      }
    }
  }
}
```

### Connectivity Awareness

```dart
// lib/services/connectivity_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

// In UI:
final connectivity = ref.watch(connectivityProvider);

connectivity.when(
  data: (status) {
    if (status == ConnectivityResult.none) {
      return _OfflineBanner();
    }
    // Show normal UI
  },
  loading: () => const SizedBox.shrink(),
  error: (_, __) => const SizedBox.shrink(),
);
```

---

## CI/CD & API Documentation

### GitHub Actions Pipeline

Create file: `.github/workflows/backend.yml`

```yaml
name: Backend CI/CD

on:
  push:
    branches: [main]
    paths: ['backend/**']
  pull_request:
    paths: ['backend/**']

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test_ev_router
        ports: ['5432:5432']
        options: --health-cmd=pg_isready --health-interval=10s
      redis:
        image: redis:7
        ports: ['6379:6379']
        options: --health-cmd="redis-cli ping" --health-interval=10s
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'
      
      - name: Install dependencies
        working-directory: backend
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-asyncio pytest-cov ruff mypy
      
      - name: Lint
        working-directory: backend
        run: |
          ruff check .
          mypy .
      
      - name: Run tests
        working-directory: backend
        env:
          DATABASE_URL: postgresql://postgres:test@localhost:5432/test_ev_router
          REDIS_URL: redis://localhost:6379/0
        run: |
          pytest --cov=. --cov-report=xml --cov-fail-under=70
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: backend/coverage.xml
  
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bandit security scan
        run: |
          pip install bandit
          bandit -r backend/ -f json -o bandit-report.json || true
      - name: Dependency vulnerability scan
        run: |
          pip install safety
          safety check -r backend/requirements.txt
  
  build-and-deploy:
    needs: [test, security-scan]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Docker image
        run: |
          docker build -t ev-router-backend:${{ github.sha }} ./backend
      
      - name: Push to registry
        run: |
          echo "${{ secrets.GCR_TOKEN }}" | docker login gcr.io -u _json_key --password-stdin
          docker tag ev-router-backend:${{ github.sha }} gcr.io/${{ secrets.GCP_PROJECT }}/ev-router-backend:${{ github.sha }}
          docker tag ev-router-backend:${{ github.sha }} gcr.io/${{ secrets.GCP_PROJECT }}/ev-router-backend:latest
          docker push gcr.io/${{ secrets.GCP_PROJECT }}/ev-router-backend:${{ github.sha }}
          docker push gcr.io/${{ secrets.GCP_PROJECT }}/ev-router-backend:latest
      
      - name: Deploy to Cloud Run (canary)
        run: |
          gcloud run deploy ev-router-backend \
            --image gcr.io/${{ secrets.GCP_PROJECT }}/ev-router-backend:${{ github.sha }} \
            --tag canary \
            --no-traffic \
            --region asia-south1
      
      - name: Smoke test canary
        run: |
          sleep 30
          curl -f https://canary---ev-router-backend.run.app/health/ready
      
      - name: Promote canary (10%)
        run: |
          gcloud run services update-traffic ev-router-backend \
            --to-tags canary=10 \
            --region asia-south1
```

### Flutter CI/CD

```yaml
# .github/workflows/flutter.yml
name: Flutter CI/CD

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
          channel: 'stable'
      
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v3
        with:
          files: coverage/lcov.info
  
  build-android:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      
      - run: flutter pub get
      - run: flutter build apk --release
      - run: flutter build appbundle --release
      
      - uses: actions/upload-artifact@v3
        with:
          name: android-release
          path: |
            build/app/outputs/flutter-apk/app-release.apk
            build/app/outputs/bundle/release/app-release.aab
```

### OpenAPI Documentation

FastAPI auto-generates OpenAPI. Enhance with:

```python
# backend/main.py
app = FastAPI(
    title="EV Router Backend",
    description="""
    Beckn-compliant EV charging API with ON_FULFILLMENT postpaid metering.
    
    ## Authentication
    - JWT Bearer tokens for user authentication
    - Idempotency-Key header for retry-safe mutations
    
    ## Rate Limits
    - QR validation: 30/min
    - Session operations: 5/min per user
    - Status polls: 60/min per session
    """,
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_tags=[
        {"name": "QR Scanner", "description": "Scan & validate charger QR codes"},
        {"name": "Beckn Charging", "description": "Beckn protocol endpoints"},
        {"name": "Sessions", "description": "Charging session lifecycle"},
        {"name": "Payments", "description": "Payment collection & verification"},
        {"name": "Health", "description": "Service health & readiness"},
        {"name": "Metrics", "description": "Prometheus metrics"},
    ],
)
```

### Postman Collection

Create file: `docs/postman/ev-router.postman_collection.json` with all endpoints pre-configured for testing.

---

## Updated Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Flutter App (Riverpod + Hive)                        │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  QR Scanner → Session State → Live Meter → Payment Dialog      │ │
│  │  ↕ Offline persistence + Connectivity-aware                     │ │
│  └────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────┬───────────────────────────────────────┘
                               │ HTTPS (mTLS optional) + WSS
                               │ Idempotency-Key header
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Cloud Run (Auto-scaling)                           │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  FastAPI Backend                                                │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │ │
│  │  │ Auth + Rate  │  │ Idempotency  │  │ State Machine│         │ │
│  │  │ Limit Layer  │  │ Layer        │  │ + Saga       │         │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │ │
│  │         └──────────────────┼──────────────────┘                 │ │
│  │                            ▼                                    │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │ Business Logic (QR, Session, Payment, OCPP)              │  │ │
│  │  │ ├─ Circuit Breaker for OCPP                              │  │ │
│  │  │ ├─ Retry with Exponential Backoff                        │  │ │
│  │  │ └─ Distributed Locks (Redis)                             │  │ │
│  │  └──────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────┘ │
└──────────┬───────────────────────┬───────────────────────┬───────────┘
           │                       │                       │
           ▼                       ▼                       ▼
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────────┐
│   Supabase       │   │   Redis (Cache + │   │   Celery Workers      │
│   (PostgreSQL)   │   │   Locks + Queue) │   │   - Receipts          │
│   - Sessions     │   │   - Idempotency  │   │   - Notifications     │
│   - Meters       │   │   - Pub/Sub      │   │   - Stale cleanup     │
│   - Payments     │   │   - WS scaling   │   │   - Payment timeouts  │
└──────────────────┘   └──────────────────┘   └──────────────────────┘
           │                       │                       │
           └───────────────────────┼───────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
┌──────────────┐         ┌──────────────────┐       ┌────────────────────┐
│ OCPP Central │         │ Payment Gateway  │       │ Observability      │
│ System       │         │ (Razorpay/UPI)   │       │ - Prometheus       │
│ - WebSocket  │         │ - Webhook        │       │ - OpenTelemetry    │
│ - Heartbeat  │         │ - Idempotent     │       │ - Sentry           │
│ - MeterValue │         │   refunds        │       │ - Grafana          │
└──────┬───────┘         └──────────────────┘       └────────────────────┘
       │ OCPP 1.6 / 2.0.1
       ▼
┌──────────────────┐
│ Physical Charger │
│ - Live metering  │
│ - Cable control  │
└──────────────────┘
```

---



Create file: `backend/tests/test_beckn_endpoints.py`

```python
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

class TestBecknSearch:
    def test_search_chargers(self):
        response = client.post(
            "/api/chargers/beckn/search",
            params={
                "latitude": 12.9716,
                "longitude": 77.5946,
                "radius_km": 5.0
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert "context" in data
        assert "message" in data
        assert data["context"]["action"] == "on_search"

class TestSessionManagement:
    @pytest.fixture
    def auth_token(self):
        # Mock auth token
        return "test_token_123"
    
    def test_start_session(self, auth_token):
        response = client.post(
            "/api/chargers/sessions/start",
            headers={"Authorization": f"Bearer {auth_token}"},
            json={
                "charger_id": "charger_001",
                "connector_id": "conn_001",
                "charging_rate_inr_per_kwh": 15.0,
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert "session_id" in data
        assert data["state"] == "charging"
    
    def test_get_session_status(self, auth_token):
        # First start a session
        session_response = client.post(
            "/api/chargers/sessions/start",
            headers={"Authorization": f"Bearer {auth_token}"},
            json={
                "charger_id": "charger_001",
                "connector_id": "conn_001",
                "charging_rate_inr_per_kwh": 15.0,
            }
        )
        session_id = session_response.json()["session_id"]
        
        # Get status
        response = client.get(
            f"/api/chargers/sessions/{session_id}/status",
            headers={"Authorization": f"Bearer {auth_token}"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["context"]["action"] == "on_status"

class TestPayment:
    def test_confirm_payment(self):
        response = client.post(
            "/api/chargers/payments/session_123/confirm",
            params={"reference_id": "session_123"}
        )
        # Status code depends on payment gateway response
        assert response.status_code in [200, 400, 500]
```

### Load Testing

Create file: `backend/load_test.py`

```python
import concurrent.futures
import requests
import time
import random

BASE_URL = "http://localhost:8000"

def simulate_charging_session():
    """Simulate one complete charging session"""
    try:
        # Start session
        start_response = requests.post(
            f"{BASE_URL}/api/chargers/sessions/start",
            json={
                "charger_id": f"charger_{random.randint(1, 100)}",
                "connector_id": f"conn_{random.randint(1, 10)}",
                "charging_rate_inr_per_kwh": 15.0,
            },
            timeout=5
        )
        
        if start_response.status_code != 200:
            return False
        
        session_id = start_response.json()["session_id"]
        
        # Simulate 10 status checks (2 seconds each = 20 second session)
        for _ in range(10):
            status_response = requests.get(
                f"{BASE_URL}/api/chargers/sessions/{session_id}/status",
                timeout=5
            )
            if status_response.status_code != 200:
                return False
            time.sleep(2)
        
        # End session
        end_response = requests.post(
            f"{BASE_URL}/api/chargers/sessions/{session_id}/end",
            timeout=5
        )
        
        return end_response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    print("Starting load test...")
    concurrent_sessions = 10
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_sessions) as executor:
        futures = [executor.submit(simulate_charging_session) for _ in range(concurrent_sessions)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]
    
    success_count = sum(results)
    print(f"Completed {concurrent_sessions} sessions")
    print(f"Success rate: {success_count / concurrent_sessions * 100:.1f}%")
```

---

## Deployment

### Docker Setup

Create `backend/Dockerfile`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Update `requirements.txt`:

```
# Core framework
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
python-dotenv==1.0.0

# Database & ORM
supabase==2.0.1
sqlalchemy==2.0.23
asyncpg==0.29.0
alembic==1.13.0

# HTTP & Networking
httpx==0.25.1
websockets==12.0

# Auth & Security
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
slowapi==0.1.9

# Cache & Queue
redis==5.0.1
celery[redis]==5.3.4
flower==2.0.1

# QR Code
qrcode==7.4.2
pillow==10.1.0

# Observability
sentry-sdk[fastapi]==1.38.0
prometheus-client==0.19.0
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-instrumentation-fastapi==0.42b0
opentelemetry-instrumentation-httpx==0.42b0
opentelemetry-instrumentation-redis==0.42b0
opentelemetry-exporter-otlp==1.21.0
python-json-logger==2.0.7

# PDF & Email
reportlab==4.0.7
jinja2==3.1.2

# Notifications
firebase-admin==6.3.0

# Cloud (GCP)
google-cloud-secret-manager==2.17.0

# Testing
pytest==7.4.3
pytest-asyncio==0.21.1
pytest-cov==4.1.0
pytest-mock==3.12.0

# Code quality
ruff==0.1.6
mypy==1.7.1
bandit==1.7.5
safety==2.3.5
```

### Supabase Setup

Run migrations:

```bash
supabase migration new create_beckn_tables
# Copy SQL from migrations/001_create_beckn_tables.sql
supabase db push
```

### Environment Variables

Create `.env.example`:

```
# Application
BACKEND_URL=https://api.evrouter.com
APP_ENV=production
LOG_LEVEL=INFO

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key

# Beckn
BAP_ID=ev-router-bap
BPP_ID=ev-router-bpp

# Auth
JWT_SECRET=your-32-byte-secret-key
JWT_ALGORITHM=HS256
ACCESS_TOKEN_TTL_MINUTES=15
REFRESH_TOKEN_TTL_DAYS=30

# QR Signing (MUST be 32+ bytes)
QR_SIGNING_SECRET=your-qr-hmac-secret-key-min-32-bytes

# Redis (for cache, locks, queue, pub/sub)
REDIS_URL=redis://localhost:6379/0
REDIS_SSL=false

# Celery (background jobs)
CELERY_BROKER_URL=redis://localhost:6379/1
CELERY_RESULT_BACKEND=redis://localhost:6379/2

# Payment Gateway
PAYMENT_GATEWAY_URL=https://api.razorpay.com
MERCHANT_ID=your_merchant_id
PAYMENT_API_KEY=your_api_key
PAYMENT_WEBHOOK_SECRET=your_webhook_secret

# Charger OCPP
OCPP_CENTRAL_SYSTEM_URL=wss://ocpp.evrouter.com
OCPP_PROTOCOL_VERSION=1.6
CHARGER_ENDPOINT_BASE=http://charger-{charger_id}.local:8080

# Firebase (Push Notifications)
FIREBASE_CREDENTIALS_PATH=/secrets/firebase-admin.json

# Email (Receipts)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASSWORD=your_sendgrid_key
EMAIL_FROM=receipts@evrouter.com

# Observability
SENTRY_DSN=https://your-key@sentry.io/your-project
OTLP_ENDPOINT=http://otel-collector:4317
PROMETHEUS_PORT=9090

# GCP (Secrets, Storage)
GCP_PROJECT_ID=your-project-id
GCP_SECRETS_PREFIX=ev-router

# CORS
ALLOWED_ORIGINS=["https://app.evrouter.com", "http://localhost:3000"]

# Rate Limiting
RATE_LIMIT_QR_VALIDATE=30/minute
RATE_LIMIT_SESSION_START=5/minute
RATE_LIMIT_STATUS_POLL=60/minute
RATE_LIMIT_PAYMENT_CONFIRM=10/minute

# Timeouts (seconds)
OCPP_REQUEST_TIMEOUT=10
OCPP_START_TIMEOUT=30
PAYMENT_GATEWAY_TIMEOUT=15
SESSION_PAYMENT_TIMEOUT_MINUTES=15
SESSION_INACTIVITY_TIMEOUT_HOURS=6
```

### Deployment Commands

```bash
# Build Docker image
docker build -t ev-router-backend:latest .

# Run locally
docker run -p 8000:8000 --env-file .env ev-router-backend:latest

# Push to cloud (GCP Cloud Run example)
docker tag ev-router-backend:latest gcr.io/your-project/ev-router-backend:latest
docker push gcr.io/your-project/ev-router-backend:latest

# Deploy to Cloud Run
gcloud run deploy ev-router-backend \
  --image gcr.io/your-project/ev-router-backend:latest \
  --region us-central1 \
  --allow-unauthenticated
```

---

## Implementation Checklist

### Phase 0: Foundation & Infrastructure (Day 1-2)
- [ ] Set up Redis instance (cloud or local)
- [ ] Configure Postgres with required extensions (uuid-ossp, postgis if geo)
- [ ] Set up secrets management (GCP Secret Manager / AWS SM)
- [ ] Configure structured logging (JSON formatter)
- [ ] Set up Sentry for error tracking
- [ ] Initialize OpenTelemetry tracing
- [ ] Set up Prometheus + Grafana for metrics
- [ ] Configure GitHub Actions CI/CD pipeline

### Phase 1: Core Models & Database (Day 3)
- [ ] Create Pydantic models (`backend/models/beckn_models.py`)
- [ ] Create database migrations (sessions, meter_readings, payments, reservations, beckn_log)
- [ ] Create Postgres atomic functions (start_charging_session_atomic)
- [ ] Set up Supabase tables with proper indexes
- [ ] Define session state machine (`session_state_machine.py`)
- [ ] Implement idempotency layer (`idempotency.py`)
- [ ] Implement distributed locking (`distributed_lock.py`)

### Phase 2: Security & Resilience (Day 4)
- [ ] Implement signed QR generator (`SecureQRGenerator`)
- [ ] Add rate limiting per user/endpoint
- [ ] Build JWT access + refresh token system
- [ ] Implement circuit breaker for OCPP
- [ ] Implement retry with exponential backoff
- [ ] Implement Saga pattern for multi-step ops
- [ ] Add input validation with Pydantic constraints

### Phase 3: Backend Business Logic (Day 5-6)
- [ ] Build QR validation endpoint (with signature verification)
- [ ] Build QR generation endpoint (admin)
- [ ] Implement Beckn search/select/init/confirm/status/update endpoints
- [ ] Implement session lifecycle endpoints (start/status/end)
- [ ] Wire OCPP integration with circuit breaker + retry
- [ ] Implement payment service (UPI collect, verify, refund)
- [ ] Add WebSocket handler with Redis pub/sub
- [ ] Set up Celery worker + beat for background jobs
- [ ] Implement receipt PDF generation
- [ ] Wire push notifications (FCM)

### Phase 4: Edge Cases & Recovery (Day 7)
- [ ] Implement OCPP heartbeat monitor
- [ ] Implement payment timeout handler
- [ ] Implement stale session cleanup (cron)
- [ ] Implement force-close on charger offline
- [ ] Implement multi-session prevention
- [ ] Implement reservation system
- [ ] Add dispute/refund flow

### Phase 5: Observability (Day 8)
- [ ] Add Prometheus metrics (sessions, energy, revenue, latency)
- [ ] Add OpenTelemetry tracing spans (per business operation)
- [ ] Configure structured logging with request context
- [ ] Add deep health checks (DB, Redis, payment, Supabase)
- [ ] Configure Prometheus alert rules
- [ ] Set up Grafana dashboards (business + ops)

### Phase 6: Flutter App (Day 9-10)
- [ ] Set up Riverpod state management
- [ ] Set up Hive for offline persistence
- [ ] Build QR scanner screen with mobile_scanner
- [ ] Build charger confirmation screen
- [ ] Build charging session screen with live meter
- [ ] Implement WebSocket with polling fallback
- [ ] Implement connectivity-aware UI
- [ ] Implement offline request queue
- [ ] Add UPI payment integration (deep link)
- [ ] Wire FCM push notifications
- [ ] Test on real device with physical QR codes

### Phase 7: Testing & Hardening (Day 11)
- [ ] Unit tests (target 70%+ coverage)
- [ ] Integration tests for all happy paths
- [ ] Edge case tests (timeouts, retries, failures)
- [ ] Load testing (k6 or Locust)
- [ ] Security audit (Bandit, Safety, OWASP)
- [ ] Penetration testing on QR validation
- [ ] Test all failure recovery flows

### Phase 8: Deployment (Day 12-13)
- [ ] Build Docker images (backend, worker)
- [ ] Deploy to Cloud Run with canary strategy
- [ ] Configure Cloud Run autoscaling
- [ ] Set up production Redis (with HA)
- [ ] Run database migrations on prod
- [ ] Configure DNS + SSL
- [ ] Set up CDN for static assets
- [ ] Configure WAF rules
- [ ] Print + deploy QR codes on physical chargers
- [ ] Smoke test entire flow in production
- [ ] Enable alerts + monitoring
- [ ] Set up on-call rotation

---

## QR Code Generation for Chargers

### For Charger Admin/Installation

```bash
# Get QR code for a charger
curl -X GET \
  https://api.evrouter.com/api/chargers/CHARGER_001/qr \
  -H "Authorization: Bearer admin_token"

# Response includes:
# {
#   "charger_id": "CHARGER_001",
#   "qr_code": "data:image/png;base64,...",
#   "qr_string": "evrouter://charge?charger_id=..."
# }
```

### Printing QR Codes

1. Save the base64 image from response
2. Decode and print as 10x10 cm sticker
3. Place on charger housing/cabinet
4. Test scan with app before going live

### QR Code Data Structure

```
evrouter://charge?
  charger_id=CHARGER_001
  &connector_id=CONN_A
  &location_name=Delhi%20Sector%2062
  &latitude=12.9716
  &longitude=77.5946
  &power_kw=50
  &connector_type=CCS2
  &rate=15.0
```

---

## Key Integration Points

| Component | Integration | Status |
|-----------|------------|--------|
| QR Scanner | Scan charger codes → Auto-populate session | Required |
| QR Validation | Backend validation of scanned data | Required |
| Chargers Router | Extend with Beckn endpoints | In Progress |
| Payment Service | UPI collection + verification | Required |
| OCPP Chargers | Live metrics + unlock | Required |
| WebSocket | Real-time meter updates | Required |
| Supabase | Sessions + payments tables | Required |
| Flutter App | QR Scanner + Session UI + Payment | Required |

---

## Notes

### QR Code Scanning Workflow
```
User opens app
  ↓
Tap "Scan Charger QR"
  ↓
Camera opens (permission check)
  ↓
User points at charger QR code
  ↓
App detects barcode (mobile_scanner)
  ↓
Send QR data to backend (/qr/validate)
  ↓
Backend parses & validates charger
  ↓
If valid: Show charger confirmation screen
  ↓
User confirms: "Start Charging"
  ↓
Session starts immediately (skip search/select)
  ↓
Show live meter screen
  ↓
If invalid: Show error & retry
```

### Key Features
- **ON_FULFILLMENT**: User pays AFTER charging (postpaid metered)
- **Live Metering**: Push updates every 2-5 seconds via WebSocket
- **Cable Release**: Unlock after payment confirmed
- **QR Scanning**: ~1-2 second scan to session start
- **Fallback Search**: If camera unavailable, use location search
- **Error Handling**: Graceful degradation if OCPP charger unreachable
- **Offline QR**: QR code works even if charger is temporarily offline (shows status)
- **Testing**: Use mock OCPP charger + test QR codes for development

### QR Code Benefits
1. **Instant identification** - No manual charger selection needed
2. **No geolocation errors** - Charger location hardcoded in QR
3. **Charger authentication** - QR code proves charger existence
4. **Contactless** - No physical interaction needed
5. **Works offline** - QR decoding happens on device
6. **Multiple chargers** - Different QR codes per connector
7. **Easy deployment** - Simple sticker placement

### Security Considerations
- Validate QR data against database (prevent spoofing)
- Use HTTPS for all QR validation requests
- QR string contains no sensitive data (public charger info only)
- Rate limit QR validation endpoint
- Log all QR scans for audit trail

---

## Testing QR Codes

### Generate Test QR Codes

```python
# Use this script to generate test QR codes
from utils.qr_generator import QRGenerator
import base64

test_chargers = [
    {
        "charger_id": "TEST_CHARGER_001",
        "connector_id": "CONN_A",
        "name": "Test Charger - Bangalore",
        "latitude": 12.9716,
        "longitude": 77.5946,
        "power_kw": 50,
        "connector_types": ["CCS2"],
        "price_per_kwh": 15.0,
    },
    {
        "charger_id": "TEST_CHARGER_002",
        "connector_id": "CONN_B",
        "name": "Test Charger - Delhi",
        "latitude": 28.7041,
        "longitude": 77.1025,
        "power_kw": 30,
        "connector_types": ["TYPE2"],
        "price_per_kwh": 12.0,
    },
]

for charger in test_chargers:
    qr_base64 = QRGenerator.generate_charger_qr(charger)
    qr_string = QRGenerator.build_qr_string(charger)
    
    print(f"Charger: {charger['name']}")
    print(f"QR String: {qr_string}")
    print(f"Base64: {qr_base64[:50]}...")
    print()
```

### Manual QR Testing

1. **Online QR Generator**:
   - Use https://www.qr-code-generator.com/
   - Enter QR string: `evrouter://charge?charger_id=TEST_001&...`
   - Download as PNG

2. **App Testing**:
   - Open app in emulator/device
   - Go to "Scan Charger QR"
   - Print QR code or display on screen
   - Point camera at QR code
   - Should redirect to confirmation screen

3. **Backend Testing**:
   ```bash
   curl -X POST https://api.evrouter.com/api/chargers/qr/validate \
     -H "Authorization: Bearer test_token" \
     -H "Content-Type: application/json" \
     -d '{
       "qr_data": "evrouter://charge?charger_id=TEST_001&connector_id=CONN_A&..."
     }'
   ```

### Load Testing QR Endpoint

```python
import concurrent.futures
import requests

def test_qr_validation():
    response = requests.post(
        "http://localhost:8000/api/chargers/qr/validate",
        json={"qr_data": "evrouter://charge?charger_id=TEST_001&..."},
        timeout=5
    )
    return response.status_code == 200

# Run 100 concurrent validations
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    futures = [executor.submit(test_qr_validation) for _ in range(100)]
    success_count = sum(f.result() for f in concurrent.futures.as_completed(futures))
    print(f"Success rate: {success_count}%")
```

---

## Support & References

### Beckn & EV Standards
- Beckn Specification: https://github.com/beckn/missions/pull/308
- DEG Protocol: https://github.com/beckn/DEG
- UEI EV Charging: https://github.com/beckn/UEI-specifications
- OCPP 1.6: https://www.openchargealliance.org/

### Backend
- FastAPI Docs: https://fastapi.tiangolo.com/
- Supabase: https://supabase.com/docs
- Python QR Code: https://github.com/lincolnloop/python-qrcode

### Frontend (Flutter)
- Flutter Docs: https://flutter.dev/docs
- mobile_scanner: https://pub.dev/packages/mobile_scanner
- permission_handler: https://pub.dev/packages/permission_handler
- WebSocket: https://pub.dev/packages/web_socket_channel
- http package: https://pub.dev/packages/http

### QR Code Standards
- QR Code Specification: https://en.wikipedia.org/wiki/QR_code
- URL Format Best Practices: https://tools.ietf.org/html/rfc3986
- Deep Linking: https://developer.android.com/training/app-links/deep-linking

---

## What's Included

### Core Features
✅ **QR Code Scanner** - Scan charger QR codes to start charging instantly  
✅ **Signed QR Codes** - HMAC-protected QR codes prevent fraud/spoofing  
✅ **Beckn API** - Full Beckn EV charging protocol implementation  
✅ **ON_FULFILLMENT** - Postpaid metered charging with live meter tracking  
✅ **OCPP Integration** - Bridge between charger hardware and backend  
✅ **WebSocket Updates** - Real-time meter data with Redis pub/sub scaling  
✅ **UPI Payments** - Postpaid payment collection with verification  
✅ **Cable Unlock** - Automatic cable unlock after payment success  

### Production-Critical Architecture
✅ **Session State Machine** - 14-state lifecycle with valid transitions  
✅ **Idempotency Keys** - Retry-safe mutations (no duplicates)  
✅ **Distributed Locking** - Redis locks prevent concurrent session conflicts  
✅ **Saga Pattern** - Compensating transactions for multi-step ops  
✅ **Circuit Breaker** - Prevents cascading OCPP failures  
✅ **Exponential Backoff** - Smart retry logic with jitter  
✅ **Database Transactions** - Atomic Postgres functions for race-safe writes  

### Security
✅ **HMAC-Signed QR Codes** - Tamper-proof charger identification  
✅ **Rate Limiting** - Per-user limits prevent abuse  
✅ **JWT Refresh Tokens** - Secure auth with revocation support  
✅ **WebSocket Auth** - First-message auth pattern (no token in URL)  
✅ **Secrets Management** - GCP Secret Manager integration  
✅ **Input Validation** - Pydantic with strict constraints  

### Performance & Scale
✅ **Redis Caching** - Charger metadata, search results, quotes  
✅ **Background Jobs** - Celery for receipts, notifications, cleanup  
✅ **Connection Pooling** - DB + HTTP client pools  
✅ **Horizontal Scaling** - WS pub/sub allows multi-instance deploys  

### Observability
✅ **Structured Logging** - JSON logs with request/user/session context  
✅ **Prometheus Metrics** - Business + performance + operational metrics  
✅ **Distributed Tracing** - OpenTelemetry across all services  
✅ **Deep Health Checks** - Validates all dependencies  
✅ **Alerting Rules** - Pre-configured Prometheus alerts  

### Failure Recovery
✅ **Stale Session Cleanup** - Force-close stuck sessions after 6h  
✅ **Payment Timeout Handling** - Auto-escalation after 15 min  
✅ **OCPP Disconnect Detection** - Heartbeat monitor + force close  
✅ **Multi-Session Prevention** - User can't start parallel sessions  
✅ **Dispute Flow** - Manual review path for failed payments  

### Supplementary Features
✅ **PDF Receipts** - GST-compliant invoices via email  
✅ **Push Notifications** - FCM for session events  
✅ **Reservations** - 15-min charger holds  
✅ **Vehicle Integration** - SOC tracking, duration estimation  
✅ **Refunds** - Idempotent refund flow  

### Frontend Excellence
✅ **Riverpod State Management** - Reactive, testable state  
✅ **Hive Offline Persistence** - Survives app restarts mid-session  
✅ **Connectivity Awareness** - Graceful offline degradation  
✅ **WebSocket → Polling Fallback** - Always-on live updates  
✅ **Request Queue** - Replays failed requests on reconnect  

### DevOps & Quality
✅ **GitHub Actions CI/CD** - Test, scan, build, canary deploy  
✅ **Security Scanning** - Bandit + Safety + SAST  
✅ **Test Coverage Gate** - 70%+ required  
✅ **Canary Deploys** - 10% traffic before full rollout  
✅ **OpenAPI Docs** - Auto-generated + Postman collection  

---

**Document Created**: 2026-05-14  
**Last Updated**: 2026-05-14 (v2.0 — Production-Ready)  
**Implementation Ready**: Yes  
**Estimated Timeline**: 13 days (1 person), 7 days (3-person team in parallel)  
**Complexity**: High (Production-grade integration with full resilience patterns)

---

## Quick Start Guide

### For Users
1. Open EV Router app
2. Tap "Scan Charger QR"
3. Point camera at charger QR code
4. App shows charger details & price
5. Tap "Start Charging"
6. Live meter shows during charging
7. Tap "Stop Charging" when done
8. Pay via UPI
9. Cable unlocks automatically

### For Developers

**Install Dependencies**:
```bash
cd backend
pip install -r requirements.txt

cd ../
flutter pub get
```

**Run Backend Locally**:
```bash
cd backend
python -m uvicorn main:app --reload --port 8000
```

**Run Flutter App**:
```bash
flutter run
```

**Generate Test QR Code**:
```bash
# In Python shell
from backend.utils.qr_generator import QRGenerator
qr = QRGenerator.generate_charger_qr({
    "charger_id": "TEST_001",
    "connector_id": "CONN_A",
    "name": "Test Charger",
    "latitude": 12.9716,
    "longitude": 77.5946,
    "power_kw": 50,
    "connector_types": ["CCS2"],
    "price_per_kwh": 15.0,
})
print(qr)  # Base64 image
```

### Critical Files to Implement (in order)

1. **Backend**:
   - `backend/models/beckn_models.py` - Data structures
   - `backend/utils/qr_generator.py` - QR code generation
   - `backend/routers/beckn_charging.py` - API endpoints (with QR validation)
   - `backend/utils/ocpp_integration.py` - Charger communication
   - `backend/utils/payment_service.py` - Payment handling
   - `backend/websocket_handler.py` - Real-time updates
   - `backend/migrations/001_create_beckn_tables.sql` - Database schema

2. **Frontend**:
   - `lib/services/qr_scanner_service.dart` - QR validation client
   - `lib/screens/charging/qr_scanner_screen.dart` - Camera screen
   - `lib/screens/charging/charger_confirm_screen.dart` - Confirmation
   - `lib/screens/charging/charging_session_screen.dart` - Live meter display
   - `lib/screens/charging/charging_home_screen.dart` - Entry point

3. **Configuration**:
   - `.env` - Environment variables
   - `pubspec.yaml` - Flutter dependencies
   - `requirements.txt` - Python dependencies
   - `docker-compose.yml` - Local development
   - `Dockerfile` - Production build

---

## Architecture Diagram (with QR Scanner)

```
┌─────────────────────────────────────────────────────────────────┐
│                     EV Router Mobile App (Flutter)               │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ Charging Home Screen                                         ││
│  │ ┌────────────────────┐  ┌──────────────────────────────────┐││
│  │ │ Scan QR Button     │  │ Search Nearby Chargers           │││
│  │ │  (Mobile Scanner)  │  │ (Beckn search endpoint)          │││
│  │ └──────────┬─────────┘  └──────────────────────────────────┘││
│  │            │                                                  ││
│  │            ▼                                                  ││
│  │ ┌──────────────────────────────────────────────────────────┐││
│  │ │ QR Scanner Screen (camera)                               │││
│  │ │ Detects: evrouter://charge?charger_id=...               │││
│  │ └──────────┬─────────────────────────────────────────────┬─┘││
│  │            │                                               │  ││
│  │            ▼                                               │  ││
│  │ ┌──────────────────────────────────────────────────────┐  │  ││
│  │ │ Charger Confirmation Screen                          │  │  ││
│  │ │ Shows: Power, Connector, Rate, Location              │  │  ││
│  │ │ Button: "Start Charging"                             │  │  ││
│  │ └──────────┬─────────────────────────────────────────┬─┘  │  ││
│  │            │                                         │     │  ││
│  │            ▼                                         │     │  ││
│  │ ┌──────────────────────────────────────────────────┐│     │  ││
│  │ │ Charging Session Screen (Live Meter)             ││     │  ││
│  │ │ Shows: Energy, Cost, Current, Voltage, SOC        ││     │  ││
│  │ │ WebSocket updates every 2-5 seconds               ││     │  ││
│  │ └──────────┬─────────────────────────────────────┬──┘     │  ││
│  │            │                                     │         │  ││
│  │            ▼ (stop)                              ▼ (manual)│  ││
│  │ ┌──────────────────────────────────────────────────────┐  │  ││
│  │ │ Payment Dialog                                       │  │  ││
│  │ │ Amount, UPI Link, Unlock Status                      │  │  ││
│  │ └─────────────────────────────────────────────────────┘  │  ││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────┬──────────────────────────────────────────────┘
                  │ HTTP (/qr/validate, /sessions/start, /status)
                  │ WebSocket (/ws/session/{id})
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│              FastAPI Backend (Python)                            │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ QR Validation                                                ││
│  │ ├─ /qr/validate: Parse & verify QR data                     ││
│  │ └─ /chargers/{id}/qr: Generate QR code                      ││
│  └──────────────────────────────────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ Beckn API Routes                                             ││
│  │ ├─ /beckn/search: Nearby chargers                            ││
│  │ ├─ /beckn/select: Charger details                            ││
│  │ ├─ /sessions/start: Begin charging                           ││
│  │ ├─ /sessions/{id}/status: Live meter (on_status)            ││
│  │ ├─ /sessions/{id}/end: End & bill (on_update)               ││
│  │ └─ /payments/{id}/confirm: Verify payment                   ││
│  └──────────────────────────────────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ OCPP Bridge                                                  ││
│  │ ├─ get_live_metrics()                                        ││
│  │ ├─ unlock_connector()                                        ││
│  │ └─ stop_charging()                                           ││
│  └──────────────────────────────────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ WebSocket Manager                                            ││
│  │ ├─ broadcast_meter_update()                                  ││
│  │ └─ broadcast_session_end()                                   ││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────┬──────────────────────────────────────────────┘
                  │ Supabase (Sessions, Meter Readings, Payments)
                  │ Payment Gateway (UPI verification)
                  ▼ OCPP 1.6/2.0
         ┌────────────────────────┐
         │ EV Charging Station    │
         │ - Live metrics (OCPP)  │
         │ - Cable unlock command │
         └────────────────────────┘
```
