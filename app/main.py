from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import ensure_indexes
from app.routers import (
    members,
    scan,
    topups,
    menu,
    menu_categories,
    expenses,
    refunds,
    settings as settings_router,
)

app = FastAPI(title=settings.app_name)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Local network only — this stays wide open on CORS since every client
# (scanner phone, admin laptop) is on the same trusted LAN.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(members.router)
app.include_router(scan.router)
app.include_router(topups.router)
app.include_router(menu.router)
app.include_router(menu_categories.router)
app.include_router(expenses.router)
app.include_router(refunds.router)
app.include_router(settings_router.router)


@app.on_event("startup")
async def on_startup():
    await ensure_indexes()
    await get_global_settings_safe()


async def get_global_settings_safe():
    from app.core.database import get_global_settings
    await get_global_settings()


@app.get("/health")
async def health():
    return {"status": "ok"}
