import logging

from supabase import create_client, Client
from config import settings

logger = logging.getLogger(__name__)

def _create_supabase_client(key: str) -> Client:
    if not settings.SUPABASE_URL or not key:
        logger.warning("Supabase credentials not found.")
        return None
    try:
        return create_client(settings.SUPABASE_URL, key)
    except Exception as e:
        logger.warning("Failed to initialize Supabase client: %s", e)
        return None

def get_supabase() -> Client:
    return _create_supabase_client(settings.SUPABASE_KEY)

def get_service_supabase() -> Client:
    return _create_supabase_client(settings.SUPABASE_SERVICE_ROLE_KEY)

public_supabase = get_supabase()
service_supabase = get_service_supabase()
supabase = service_supabase or public_supabase
