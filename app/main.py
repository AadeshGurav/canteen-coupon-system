import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pymongo.errors import OperationFailure

from app.core.config import settings
from app.core.database import ensure_indexes, get_global_settings
from app.core.logging_config import configure_logging
from app.routers import (
    auth,
    expenses,
    ingredients,
    members,
    menu,
    menu_categories,
    notifications,
    purchase_schedule,
    recipes,
    refunds,
    scan,
    topups,
    users,
)
from app.routers import settings as settings_router
from app.services.auth_service import bootstrap_initial_admin

configure_logging()
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await ensure_indexes()
    except OperationFailure as exc:
        if exc.code == 18:  # AuthenticationFailed
            # The single most common deploy-time failure, and the raw
            # pymongo traceback gives no hint what's actually wrong: Mongo
            # only applies MONGO_INITDB_ROOT_PASSWORD the FIRST time its
            # data directory is initialized, so editing MONGO_ROOT_PASSWORD
            # in .env after the stack has ever run once does nothing to the
            # password already stored in the mongo_data volume — every boot
            # after that fails here. Surfacing this by name (PRD §7:
            # "clear, specific errors", not a generic failure) turns a
            # confusing crash into a one-line fix.
            print(
                "FATAL: MongoDB authentication failed. This almost always means "
                "MONGO_ROOT_PASSWORD in .env doesn't match the password already "
                "stored in the mongo_data volume from an earlier run — Mongo only "
                "applies MONGO_INITDB_ROOT_PASSWORD the first time its data "
                "directory is initialized, so changing .env afterward doesn't "
                "change what's already stored. Fix: either restore the "
                "MONGO_ROOT_PASSWORD this volume was first created with, or, if "
                "this data can be discarded, run `docker compose down -v` to wipe "
                "the volume and reinitialize cleanly with the current .env.",
                flush=True,
            )
        raise
    await get_global_settings()
    await bootstrap_initial_admin()
    logger.info("startup_complete app_name=%s", settings.app_name)
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Local network only — this stays wide open on CORS since every client
# (scanner phone, admin laptop) is on the same trusted LAN.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(members.router)
app.include_router(scan.router)
app.include_router(topups.router)
app.include_router(menu.router)
app.include_router(menu_categories.router)
app.include_router(expenses.router)
app.include_router(refunds.router)
app.include_router(settings_router.router)
app.include_router(ingredients.router)
app.include_router(recipes.router)
app.include_router(purchase_schedule.router)
app.include_router(notifications.router)


@app.exception_handler(Exception)
async def log_unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
    """Any exception not already turned into a clean HTTPException lands here —
    logged with full context so the admin can debug from the log file alone,
    without exposing internals to whoever's using the browser (see PRD §7/§8)."""
    logger.exception("unhandled_exception method=%s path=%s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Something went wrong. Check the server logs."})


@app.get("/health")
async def health():
    return {"status": "ok"}
