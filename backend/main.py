from contextlib import asynccontextmanager
import asyncio
import logging
import os
import time

import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.httpx import HttpxIntegration
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from routers import (
    places,
    routing,
    chargers,
    vehicles,
    auth,
    routes,
    sos,
    users,
    admin,
    gamification,
    news,
    content,
)
# Beckn EV charging router — always imported so /feature-flags endpoint is available,
# but individual routes gate themselves behind settings.BECKN_CHARGING_ENABLED
from routers import beckn_charging
from config import settings
from supabase_client import service_supabase

sentry_sdk.init(
    dsn=os.getenv("SENTRY_DSN", ""),
    integrations=[FastApiIntegration(), HttpxIntegration()],
    environment=settings.APP_ENV,
    traces_sample_rate=0.05,
    profiles_sample_rate=0.05,
)

limiter = Limiter(key_func=get_remote_address)

_SKIP_METRICS = {"/", "/health", "/ready", "/reset-password", "/api/admin/dashboard"}


class _MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path in _SKIP_METRICS or request.url.path.startswith("/api/admin/metrics"):
            return await call_next(request)
        start = time.monotonic()
        response = await call_next(request)
        duration_ms = int((time.monotonic() - start) * 1000)
        from metrics_tracker import track_api_call
        track_api_call(request.url.path, request.method, response.status_code, duration_ms)
        return response


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield


logging.basicConfig(
    level=getattr(
        logging,
        str(getattr(settings, "LOG_LEVEL", "INFO")).upper(),
        logging.INFO,
    ),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

_is_prod = settings.APP_ENV == "production"
app = FastAPI(
    title="EVraahein Backend",
    description=(
        "EV routing, charging discovery, OBD telemetry, and Beckn EV charging API. "
        "Docs are available in non-production environments only."
    ),
    version="1.0.0",
    contact={"name": "EVraahein Support", "email": "pidaparthy@gmail.com"},
    license_info={"name": "Proprietary"},
    docs_url=None if _is_prod else "/docs",
    redoc_url=None if _is_prod else "/redoc",
    openapi_url=None if _is_prod else "/openapi.json",
    lifespan=lifespan,
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(_MetricsMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

app.include_router(places.router, prefix="/api/places", tags=["Places"])
app.include_router(routing.router, prefix="/api/route", tags=["Routing"])
app.include_router(chargers.router, prefix="/api/chargers", tags=["Chargers"])
app.include_router(vehicles.router, prefix="/api/vehicles", tags=["Vehicles"])
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(routes.router, prefix="/api/routes", tags=["Saved Routes"])
if settings.FEATURE_SOS_ENABLED:
    app.include_router(sos.router, prefix="/api/sos", tags=["SOS"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])
app.include_router(gamification.router, prefix="/api/gamification", tags=["Gamification"])
app.include_router(news.router, prefix="/api/news", tags=["News"])
app.include_router(content.router, prefix="/api/content", tags=["Content"])
# Beckn EV charging — mounted at /api/chargers so /feature-flags is at /api/chargers/feature-flags
app.include_router(beckn_charging.router, prefix="/api/chargers", tags=["Beckn Charging"])

@app.get("/")
def read_root():
    return {
        "message": "EV Router Backend is running",
        "environment": settings.APP_ENV,
    }


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/reset-password")
async def reset_password_landing():
    return await auth.password_reset_page()


@app.get("/ready")
async def readiness_check():
    missing = []
    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        missing.append("supabase")
    if not settings.SUPABASE_SERVICE_ROLE_KEY:
        missing.append("supabase_service_role")
    if not settings.HERE_API_KEY:
        missing.append("here")
    if not settings.GOOGLE_MAPS_API_KEY:
        missing.append("google_maps")
    if missing:
        raise HTTPException(
            status_code=503,
            detail=f"Missing production configuration: {', '.join(missing)}",
        )
    if not service_supabase:
        raise HTTPException(status_code=503, detail="Database client is unavailable")
    try:
        await asyncio.wait_for(
            asyncio.to_thread(
                lambda: service_supabase.table("profiles")
                .select("id")
                .limit(1)
                .execute()
            ),
            timeout=5,
        )
    except Exception as error:
        logging.getLogger(__name__).warning("Readiness database check failed: %s", error)
        raise HTTPException(status_code=503, detail="Database is unavailable") from error
    return {
        "status": "ready",
        "database": "connected",
    }
