from fastapi.testclient import TestClient

import main
from auth_utils import get_authenticated_user
from routers.chargers import _normalize_station_row
from routers import auth as auth_router


client = TestClient(main.app)


def test_health_is_public():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_protected_user_endpoint_rejects_missing_token():
    response = client.get("/api/auth/user")

    assert response.status_code == 401


def test_sos_routes_are_disabled_by_default():
    paths = {route.path for route in main.app.routes}

    assert "/api/sos/alert" not in paths


def test_gamification_routes_have_single_prefix():
    paths = {route.path for route in main.app.routes}

    assert "/api/gamification/leaderboard" in paths
    assert "/api/gamification/gamification/leaderboard" not in paths


def test_authorization_error_is_not_converted_to_server_error():
    async def authenticated_user():
        return {
            "user_id": "signed-in-user",
            "email": "user@example.com",
            "metadata": {},
        }

    main.app.dependency_overrides[get_authenticated_user] = authenticated_user
    try:
        response = client.get("/api/chargers/my-stations/another-user")
    finally:
        main.app.dependency_overrides.clear()

    assert response.status_code == 403


def test_signup_requires_legal_consent():
    response = client.post(
        "/api/auth/signup",
        json={
            "email": "new-user@example.com",
            "password": "ExamplePassword123!",
            "name": "New User",
            "terms_accepted": False,
        },
    )

    assert response.status_code == 400
    assert "accept" in response.json()["detail"].lower()


def test_admin_catalog_routes_are_registered_and_protected():
    paths = {route.path for route in main.app.routes}

    assert "/api/admin/vehicle-templates" in paths
    assert "/api/admin/content/sections" in paths
    assert "/api/admin/content/resources" in paths

    response = client.get("/api/admin/vehicle-templates")

    assert response.status_code == 401


def test_password_reset_page_is_public_and_production_ready():
    response = client.get("/reset-password")

    assert response.status_code == 200
    assert "Reset Password" in response.text
    assert "__SUPABASE_URL__" not in response.text
    assert "localhost:3000" not in response.text


def test_password_reset_email_uses_configured_redirect(monkeypatch):
    calls = []

    class _FakeAuth:
        def reset_password_for_email(self, email, options):
            calls.append({"email": email, "options": options})

    class _FakeSupabase:
        auth = _FakeAuth()

    redirect_url = "https://example.com/reset-password"
    monkeypatch.setattr(auth_router, "public_supabase", _FakeSupabase())
    monkeypatch.setattr(auth_router.settings, "PASSWORD_RESET_REDIRECT_URL", redirect_url)

    response = client.post(
        "/api/auth/reset-password",
        json={"email": "user@example.com"},
    )

    assert response.status_code == 200
    assert response.json() == {"status": "success"}
    assert calls == [
        {
            "email": "user@example.com",
            "options": {"redirect_to": redirect_url},
        }
    ]


def test_legacy_charger_null_aggregates_are_normalized():
    normalized = _normalize_station_row(
        {
            "average_rating": None,
            "total_reviews": None,
            "total_checkins": None,
        }
    )

    assert normalized["average_rating"] == 0.0
    assert normalized["total_reviews"] == 0
    assert normalized["total_checkins"] == 0
