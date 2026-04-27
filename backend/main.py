from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import (
    places,
    routing,
    chargers,
    community,
    vehicles,
    auth,
    routes,
    chat,
    sos,
    users,
    admin,
    gamification,
    news,
    content,
)
from config import settings


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
app.include_router(community.router, prefix="/api/community", tags=["Community"])
app.include_router(vehicles.router, prefix="/api/vehicles", tags=["Vehicles"])
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(routes.router, prefix="/api/routes", tags=["Saved Routes"])
app.include_router(chat.router, prefix="/api/chat", tags=["Chat"])
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
