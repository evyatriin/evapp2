import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from main import app
from config import settings
from models.beckn_models import ChargingSession, SessionStateEnum


@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def client():
    """FastAPI test client."""
    return TestClient(app)


@pytest.fixture
def mock_redis():
    """Mock Redis client."""
    mock = AsyncMock()
    mock.get = AsyncMock(return_value=None)
    mock.set = AsyncMock()
    mock.delete = AsyncMock()
    mock.exists = AsyncMock(return_value=False)
    mock.hgetall = AsyncMock(return_value={})
    mock.hset = AsyncMock()
    mock.expire = AsyncMock()
    mock.publish = AsyncMock()
    return mock


@pytest.fixture
def mock_supabase():
    """Mock Supabase client."""
    mock = MagicMock()
    mock.table = MagicMock(return_value=MagicMock())
    return mock


@pytest.fixture
def sample_charging_session():
    """Sample charging session for testing."""
    return ChargingSession(
        session_id="test-session-123",
        charger_id="charger-456",
        user_id="user-789",
        state=SessionStateEnum.INITIATED,
        connector_id="1",
        power_kw=22.0,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )


@pytest.fixture
def sample_qr_payload():
    """Sample QR payload for testing."""
    return {
        "charger_id": "charger-456",
        "connector_id": "1",
        "power_kw": 22.0,
        "connector_type": "Type 2",
        "latitude": 12.9716,
        "longitude": 77.5946,
    }


@pytest.fixture
def mock_ocpp_manager():
    """Mock OCPP manager."""
    mock = AsyncMock()
    mock.start_charging = AsyncMock(return_value=True)
    mock.stop_charging = AsyncMock(return_value=True)
    mock.get_live_metrics = AsyncMock(
        return_value={
            "current_a": 32.0,
            "voltage_v": 400.0,
            "power_kw": 22.0,
            "energy_kwh": 5.5,
        }
    )
    mock.unlock_connector = AsyncMock(return_value=True)
    return mock


@pytest.fixture
def mock_payment_service():
    """Mock payment service."""
    mock = AsyncMock()
    mock.generate_upi_deeplink = AsyncMock(return_value="upi://pay?...")
    mock.verify_payment = AsyncMock(return_value=True)
    mock.refund_payment = AsyncMock(return_value=True)
    return mock


@pytest.fixture(autouse=True)
def reset_mocks(mock_redis, mock_supabase, mock_ocpp_manager, mock_payment_service):
    """Reset all mocks before each test."""
    mock_redis.reset_mock()
    mock_supabase.reset_mock()
    mock_ocpp_manager.reset_mock()
    mock_payment_service.reset_mock()


@pytest.fixture
def auth_headers():
    """Sample JWT authorization headers."""
    return {"Authorization": "Bearer test-jwt-token-12345"}


@pytest.fixture
def enable_beckn_flag(monkeypatch):
    """Enable Beckn charging feature flag for testing."""
    monkeypatch.setattr("config.settings.BECKN_CHARGING_ENABLED", True)


@pytest.fixture
def disable_beckn_flag(monkeypatch):
    """Disable Beckn charging feature flag for testing."""
    monkeypatch.setattr("config.settings.BECKN_CHARGING_ENABLED", False)
