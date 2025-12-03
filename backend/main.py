from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import places, routing, chargers, community, vehicles, auth, routes, chat, sos, users, admin
# from routers import news  # Uncomment to enable EV news API

app = FastAPI(title="EV Router Backend")

# Allow all origins for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
# app.include_router(news.router, prefix="/api/news", tags=["News"])  # Uncomment to enable EV news API

@app.get("/")
def read_root():
    return {"message": "EV Router Backend is running"}
