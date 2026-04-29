from contextlib import asynccontextmanager
import logging
import os
import time

import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.httpx import HttpxIntegration
from fastapi import FastAPI, Request
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
from config import settings

sentry_sdk.init(
    dsn=os.getenv("SENTRY_DSN", ""),
    integrations=[FastApiIntegration(), HttpxIntegration()],
    environment=settings.APP_ENV,
    traces_sample_rate=0.05,
    profiles_sample_rate=0.05,
)

limiter = Limiter(key_func=get_remote_address)

_SKIP_METRICS = {"/", "/health", "/ready", "/api/admin/dashboard"}


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

app = FastAPI(title="EV Router Backend", lifespan=lifespan)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(_MetricsMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(places.router, prefix="/api/places", tags=["Places"])
app.include_router(routing.router, prefix="/api/route", tags=["Routing"])
app.include_router(chargers.router, prefix="/api/chargers", tags=["Chargers"])
app.include_router(vehicles.router, prefix="/api/vehicles", tags=["Vehicles"])
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(routes.router, prefix="/api/routes", tags=["Saved Routes"])
app.include_router(sos.router, prefix="/api/sos", tags=["SOS"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])
app.include_router(gamification.router, prefix="/api/gamification", tags=["Gamification"])
app.include_router(news.router, prefix="/api/news", tags=["News"])
app.include_router(content.router, prefix="/api/content", tags=["Content"])

@app.get("/")
def read_root():
    return {
        "message": "EV Router Backend is running",
        "environment": settings.APP_ENV,
    }


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/ready")
def readiness_check():
    return {
        "status": "ready",
        "supabase_configured": bool(settings.SUPABASE_URL and settings.SUPABASE_KEY),
        "here_configured": bool(settings.HERE_API_KEY),
        "google_maps_configured": bool(settings.GOOGLE_MAPS_API_KEY),
    }
