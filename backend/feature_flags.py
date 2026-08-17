import logging

from fastapi import HTTPException

from config import settings

logger = logging.getLogger(__name__)


async def require_beckn_enabled():
    """FastAPI dependency — gates all Beckn endpoints behind the feature flag."""
    if not settings.BECKN_CHARGING_ENABLED:
        raise HTTPException(status_code=404, detail="Feature not available")
