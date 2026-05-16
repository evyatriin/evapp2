import os
from dotenv import load_dotenv

load_dotenv()


def _clean_env(value: str) -> str:
    cleaned = value.strip()
    if (
        len(cleaned) >= 2 and
        ((cleaned.startswith('"') and cleaned.endswith('"')) or
         (cleaned.startswith("'") and cleaned.endswith("'")))
    ):
        cleaned = cleaned[1:-1].strip()
    return cleaned


def _parse_allowed_origins(value: str) -> list[str]:
    cleaned = _clean_env(value)
    if not cleaned:
        return ["*"]

    origins = [_clean_env(origin) for origin in cleaned.split(",") if _clean_env(origin)]
    return origins or ["*"]


class Settings:
    SUPABASE_URL = _clean_env(os.getenv("SUPABASE_URL", ""))
    SUPABASE_KEY = _clean_env(os.getenv("SUPABASE_KEY", ""))
    SUPABASE_SERVICE_ROLE_KEY = _clean_env(os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""))
    GOOGLE_MAPS_API_KEY = _clean_env(os.getenv("GOOGLE_MAPS_API_KEY", ""))
    OPENCHARGEMAP_API_KEY = _clean_env(os.getenv("OPENCHARGEMAP_API_KEY", ""))
    HERE_API_KEY = _clean_env(os.getenv("HERE_API_KEY", ""))
    APP_ENV = _clean_env(os.getenv("APP_ENV", "development"))
    ALLOWED_ORIGINS = _parse_allowed_origins(os.getenv("ALLOWED_ORIGINS", "*"))
    PORT = int(_clean_env(os.getenv("PORT", "8080")))

    # Elevation API settings
    OPEN_ELEVATION_API_URL = "https://api.open-elevation.com/api/v1/lookup"
    ELEVATION_SAMPLE_INTERVAL_KM = float(_clean_env(os.getenv("ELEVATION_SAMPLE_INTERVAL_KM", "0.5")))
    ELEVATION_API_TIMEOUT_SECONDS = int(_clean_env(os.getenv("ELEVATION_API_TIMEOUT_SECONDS", "30")))
    ELEVATION_ENABLED = _clean_env(os.getenv("ELEVATION_ENABLED", "true")).lower() == "true"

    # ── Beckn EV Charging (disabled by default; set BECKN_CHARGING_ENABLED=true to activate) ──
    BECKN_CHARGING_ENABLED = _clean_env(os.getenv("BECKN_CHARGING_ENABLED", "false")).lower() == "true"

    # QR code HMAC signing secret — must be 32+ bytes in production
    QR_SIGNING_SECRET = _clean_env(os.getenv("QR_SIGNING_SECRET", "dev-qr-secret-key-change-in-prod-32b"))

    # Redis — optional; Beckn features degrade gracefully without it
    REDIS_URL = _clean_env(os.getenv("REDIS_URL", ""))

    # Beckn BAP/BPP identifiers
    BAP_ID = _clean_env(os.getenv("BAP_ID", "ev-router-bap"))
    BPP_ID = _clean_env(os.getenv("BPP_ID", "ev-router-bpp"))
    BACKEND_URL = _clean_env(os.getenv("BACKEND_URL", "http://localhost:8080"))

    # Beckn payment settings
    PLATFORM_MERCHANT_UPI = _clean_env(os.getenv("PLATFORM_MERCHANT_UPI", "evrouter@paytm"))

    # OCPP settings
    OCPP_REQUEST_TIMEOUT = int(_clean_env(os.getenv("OCPP_REQUEST_TIMEOUT", "10")))
    OCPP_START_TIMEOUT = int(_clean_env(os.getenv("OCPP_START_TIMEOUT", "30")))

    # Session lifecycle limits
    SESSION_PAYMENT_TIMEOUT_MINUTES = int(_clean_env(os.getenv("SESSION_PAYMENT_TIMEOUT_MINUTES", "15")))
    SESSION_INACTIVITY_TIMEOUT_HOURS = int(_clean_env(os.getenv("SESSION_INACTIVITY_TIMEOUT_HOURS", "6")))

settings = Settings()
