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

settings = Settings()
