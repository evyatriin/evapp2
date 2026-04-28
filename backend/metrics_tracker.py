"""
Fire-and-forget metrics tracker using a background thread pool.
All functions return immediately; Supabase writes happen off the hot path.
"""

import logging
from concurrent.futures import ThreadPoolExecutor

logger = logging.getLogger(__name__)
_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="metrics")


def _rpc(fn: str, params: dict) -> None:
    try:
        from supabase_client import service_supabase
        service_supabase.rpc(fn, params).execute()
    except Exception as exc:
        logger.debug("metrics %s silently failed: %s", fn, exc)


def track_api_call(endpoint: str, method: str, status_code: int, duration_ms: int) -> None:
    _pool.submit(_rpc, "track_api_call", {
        "p_endpoint": endpoint,
        "p_method": method,
        "p_status_code": status_code,
        "p_duration_ms": duration_ms,
    })


def track_external_api(service: str, success: bool = True) -> None:
    _pool.submit(_rpc, "track_external_api_call", {
        "p_service": service,
        "p_success": success,
    })


def track_user_event(event_type: str) -> None:
    """event_type: 'signup' or 'login'"""
    _pool.submit(_rpc, "track_user_event", {"p_event_type": event_type})
