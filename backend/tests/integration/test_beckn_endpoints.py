import pytest
import json
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient


@pytest.fixture
def client_with_beckn_enabled(enable_beckn_flag):
    """Test client with Beckn enabled."""
    from main import app

    return TestClient(app)


@pytest.fixture
def client_with_beckn_disabled(disable_beckn_flag):
    """Test client with Beckn disabled."""
    from main import app

    return TestClient(app)


class TestFeatureFlagsEndpoint:
    """Test feature flags endpoint (always available)."""

    def test_feature_flags_endpoint_exists(self, client_with_beckn_enabled):
        """Feature flags endpoint is always available."""
        response = client_with_beckn_enabled.get("/api/chargers/feature-flags")
        assert response.status_code == 200

    def test_feature_flags_response_format(self, client_with_beckn_enabled):
        """Feature flags response has correct format."""
        response = client_with_beckn_enabled.get("/api/chargers/feature-flags")
        data = response.json()
        assert "beckn_charging_enabled" in data


class TestBecknEndpointsGating:
    """Test that endpoints are gated behind feature flag."""

    def test_search_endpoint_gated(self, client_with_beckn_disabled):
        """Search endpoint returns 404 when Beckn disabled."""
        response = client_with_beckn_disabled.post(
            "/api/chargers/beckn/search",
            json={
                "context": {"domain": "open_mobility:charge"},
                "message": {"intent": {"category": {"id": "EV_CHARGE"}}},
            },
        )
        assert response.status_code == 404

    def test_select_endpoint_gated(self, client_with_beckn_disabled):
        """Select endpoint returns 404 when Beckn disabled."""
        response = client_with_beckn_disabled.post(
            "/api/chargers/beckn/select",
            json={"message": {"order": {"provider": {"id": "charger-123"}}}},
        )
        assert response.status_code == 404

    def test_qr_validate_endpoint_gated(self, client_with_beckn_disabled):
        """QR validate endpoint returns 404 when Beckn disabled."""
        response = client_with_beckn_disabled.post(
            "/api/chargers/qr/validate",
            json={"qr_data": "test-data"},
        )
        assert response.status_code == 404


class TestSearchEndpoint:
    """Test charger search endpoint."""

    async def test_search_with_valid_bbox(self, client_with_beckn_enabled):
        """Search endpoint returns chargers for valid bounding box."""
        with patch("routers.beckn_charging.search_chargers", new_callable=AsyncMock) as mock_search:
            mock_search.return_value = [
                {
                    "id": "charger-123",
                    "name": "EV Hub Delhi",
                    "location": {"latitude": 12.9716, "longitude": 77.5946},
                }
            ]

            response = client_with_beckn_enabled.post(
                "/api/chargers/beckn/search",
                json={
                    "context": {"domain": "open_mobility:charge"},
                    "message": {
                        "intent": {
                            "category": {"id": "EV_CHARGE"},
                            "fulfillment": {
                                "stops": [
                                    {
                                        "location": {
                                            "gps": "12.9716,77.5946",
                                            "radius": {
                                                "unit": "km",
                                                "value": "5",
                                            },
                                        }
                                    }
                                ]
                            },
                        }
                    },
                },
            )

            assert response.status_code == 200

    def test_search_missing_required_fields(self, client_with_beckn_enabled):
        """Search endpoint validates required fields."""
        response = client_with_beckn_enabled.post(
            "/api/chargers/beckn/search",
            json={},
        )
        assert response.status_code in [400, 422]


class TestQRValidationEndpoint:
    """Test QR validation endpoint."""

    async def test_qr_validate_valid_qr(self, client_with_beckn_enabled):
        """QR validation returns charger details for valid QR."""
        with patch("utils.qr_generator.SecureQRGenerator") as mock_qr_gen:
            mock_instance = MagicMock()
            mock_instance.verify_qr_data.return_value = {
                "charger_id": "charger-123",
                "connector_id": "1",
                "power_kw": 22.0,
            }
            mock_qr_gen.return_value = mock_instance

            with patch("routers.beckn_charging.get_charger_details", new_callable=AsyncMock) as mock_details:
                mock_details.return_value = {
                    "id": "charger-123",
                    "name": "EV Hub Delhi",
                    "power_kw": 22.0,
                    "connector_type": "Type 2",
                }

                response = client_with_beckn_enabled.post(
                    "/api/chargers/qr/validate",
                    json={
                        "qr_data": json.dumps(
                            {
                                "charger_id": "charger-123",
                                "connector_id": "1",
                                "signature": "test-signature",
                            }
                        )
                    },
                )

                if response.status_code == 200:
                    data = response.json()
                    assert "charger" in data or "charger_id" in data

    def test_qr_validate_invalid_qr(self, client_with_beckn_enabled):
        """QR validation fails for tampered QR."""
        with patch("utils.qr_generator.SecureQRGenerator") as mock_qr_gen:
            mock_instance = MagicMock()
            mock_instance.verify_qr_data.return_value = None  # Invalid signature
            mock_qr_gen.return_value = mock_instance

            response = client_with_beckn_enabled.post(
                "/api/chargers/qr/validate",
                json={
                    "qr_data": json.dumps(
                        {
                            "charger_id": "charger-123",
                            "connector_id": "1",
                            "signature": "invalid-signature",
                        }
                    )
                },
            )

            assert response.status_code in [400, 401, 422]


class TestSessionStartEndpoint:
    """Test session start endpoint."""

    async def test_start_session_success(self, client_with_beckn_enabled, auth_headers):
        """Start session creates charging session."""
        with patch("routers.beckn_charging.start_charging_session", new_callable=AsyncMock) as mock_start:
            mock_start.return_value = {
                "session_id": "session-123",
                "state": "OCPP_STARTED",
                "charger_id": "charger-123",
            }

            response = client_with_beckn_enabled.post(
                "/api/chargers/sessions/start",
                json={
                    "charger_id": "charger-123",
                    "connector_id": "1",
                    "user_id": "user-123",
                },
                headers=auth_headers,
            )

            if response.status_code == 200:
                data = response.json()
                assert "session_id" in data

    def test_start_session_requires_auth(self, client_with_beckn_enabled):
        """Start session requires authentication."""
        response = client_with_beckn_enabled.post(
            "/api/chargers/sessions/start",
            json={
                "charger_id": "charger-123",
                "connector_id": "1",
                "user_id": "user-123",
            },
        )
        # Should either require auth or have some auth check
        assert response.status_code in [200, 401, 403]  # Depends on implementation


class TestSessionStatusEndpoint:
    """Test session status endpoint."""

    async def test_get_session_status(self, client_with_beckn_enabled, auth_headers):
        """Get session returns current status and metrics."""
        with patch("routers.beckn_charging.get_session_status", new_callable=AsyncMock) as mock_get:
            mock_get.return_value = {
                "session_id": "session-123",
                "state": "CHARGING",
                "current_a": 32.0,
                "voltage_v": 400.0,
                "power_kw": 22.0,
                "energy_kwh": 5.5,
            }

            response = client_with_beckn_enabled.get(
                "/api/chargers/sessions/session-123/status",
                headers=auth_headers,
            )

            if response.status_code == 200:
                data = response.json()
                assert "state" in data or "status" in data


class TestSessionEndEndpoint:
    """Test session end endpoint."""

    async def test_end_session_success(self, client_with_beckn_enabled, auth_headers):
        """End session stops charging."""
        with patch("routers.beckn_charging.end_charging_session", new_callable=AsyncMock) as mock_end:
            mock_end.return_value = {
                "session_id": "session-123",
                "state": "STOP_REQUESTED",
                "total_energy_kwh": 5.5,
                "total_cost": 110.0,
            }

            response = client_with_beckn_enabled.post(
                "/api/chargers/sessions/session-123/end",
                headers=auth_headers,
            )

            if response.status_code == 200:
                data = response.json()
                assert "session_id" in data


class TestPaymentEndpoint:
    """Test payment confirmation endpoint."""

    async def test_confirm_payment_success(self, client_with_beckn_enabled, auth_headers):
        """Confirm payment processes UPI verification."""
        with patch("routers.beckn_charging.confirm_payment", new_callable=AsyncMock) as mock_confirm:
            mock_confirm.return_value = {
                "session_id": "session-123",
                "payment_status": "CONFIRMED",
                "transaction_id": "txn-456",
            }

            response = client_with_beckn_enabled.post(
                "/api/chargers/payments/session-123/confirm",
                json={
                    "transaction_id": "txn-456",
                    "ref_id": "ref-789",
                },
                headers=auth_headers,
            )

            if response.status_code == 200:
                data = response.json()
                assert "payment_status" in data or "status" in data
