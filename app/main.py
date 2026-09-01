import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import ensure_indexes, get_global_settings
from app.core.logging_config import configure_logging
from app.routers import (
    expenses,
    members,
    menu,
    menu_categories,
    refunds,
    scan,
    topups,
)
from app.routers import settings as settings_router

configure_logging()
logger = logging.getLogger(__name__)

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


@app.exception_handler(Exception)
async def log_unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
    """Any exception not already turned into a clean HTTPException lands here —
    logged with full context so the admin can debug from the log file alone,
    without exposing internals to whoever's using the browser (see PRD §7/§8)."""
    logger.exception("unhandled_exception method=%s path=%s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Something went wrong. Check the server logs."})


@app.on_event("startup")
async def on_startup():
    await ensure_indexes()
    await get_global_settings()
    logger.info("startup_complete app_name=%s", settings.app_name)


@app.get("/health")
async def health():
    return {"status": "ok"}
