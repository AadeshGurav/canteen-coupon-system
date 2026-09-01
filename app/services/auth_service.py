"""Password hashing and session management — stdlib only (hashlib/hmac/
secrets), no new dependency for what's otherwise a small amount of logic
(CLAUDE.md §10: "every new dependency is a decision, not a default").

Sessions are opaque random tokens stored server-side (a `sessions`
collection), not signed/self-contained tokens like a JWT — simpler to reason
about and revoke (delete the row) at this system's scale, and MongoDB's own
TTL index (see app/core/database.py) expires them without a scheduled job."""

import hashlib
import hmac
import logging
import secrets
from datetime import datetime, timedelta, timezone

from pymongo.errors import DuplicateKeyError

from app.core.config import settings
from app.core.database import sessions, users

logger = logging.getLogger(__name__)

_PBKDF2_ITERATIONS = 260_000


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), _PBKDF2_ITERATIONS)
    return f"{salt}${digest.hex()}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        salt, digest_hex = stored_hash.split("$", 1)
    except ValueError:
        return False
    candidate = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), _PBKDF2_ITERATIONS)
    return hmac.compare_digest(candidate.hex(), digest_hex)


async def authenticate(username: str, password: str) -> dict | None:
    """Returns the user document on success, None on any failure — a caller
    never needs to distinguish "no such user" from "wrong password" (that
    distinction is exactly what lets an attacker enumerate usernames)."""
    user = await users.find_one({"username": username})
    if user is None:
        return None
    if user.get("status") != "active":
        return None
    if not verify_password(password, user["password_hash"]):
        return None
    return user


async def create_session(user: dict) -> str:
    token = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)
    await sessions.insert_one(
        {
            "_id": token,
            "user_id": str(user["_id"]),
            "username": user["username"],
            "role": user["role"],
            "created_at": now,
            "expires_at": now + timedelta(hours=settings.session_ttl_hours),
        }
    )
    return token


async def get_session(token: str) -> dict | None:
    session = await sessions.find_one({"_id": token})
    if session is None:
        return None
    # Belt-and-suspenders: the TTL index reaps expired sessions in the
    # background (typically within ~60s of expiry, not instantly), so a
    # request landing in that window must not be treated as authenticated.
    if session["expires_at"] <= datetime.now(timezone.utc):
        return None
    return session


async def delete_session(token: str) -> None:
    await sessions.delete_one({"_id": token})


async def bootstrap_initial_admin() -> None:
    """Create one admin account if the users collection is completely
    empty — otherwise there'd be no way to log in and create the first
    user. If INITIAL_ADMIN_PASSWORD isn't set, a random one is generated
    and logged at WARNING level (never silently) so it's impossible to miss
    but still meant to be changed immediately via the Users page.

    gunicorn runs multiple worker processes, each running this at startup
    independently (same reasoning as get_global_settings's race fix) — on a
    genuinely fresh database, more than one worker can see zero users and
    try to create the same username at once. The count_documents check
    above is just a fast path for every startup after the first; the actual
    race safety is catching DuplicateKeyError below, so only the worker
    that actually won gets to log its password as the real one."""
    if await users.count_documents({}, limit=1):
        return

    password = settings.initial_admin_password or secrets.token_urlsafe(12)
    now = datetime.now(timezone.utc)
    try:
        await users.insert_one(
            {
                "username": settings.initial_admin_username,
                "password_hash": hash_password(password),
                "role": "admin",
                "status": "active",
                "created_at": now,
                "updated_at": now,
            }
        )
    except DuplicateKeyError:
        return  # another worker won this race and already created it

    if settings.initial_admin_password:
        logger.info("auth.bootstrap_admin_created username=%s", settings.initial_admin_username)
    else:
        # Deliberately NOT logger.warning(): the root logger's handlers
        # (see app/core/logging_config.py) include a RotatingFileHandler,
        # which would persist this plaintext password into logs/app.log
        # indefinitely — a straight violation of "credentials are never
        # logged" (CLAUDE.md §7). A one-time plain print() reaches the same
        # console an operator watches on first boot without ever touching
        # the log file.
        print(
            f"auth.bootstrap_admin_created username={settings.initial_admin_username} "
            f"password={password} — no INITIAL_ADMIN_PASSWORD was set, so this was "
            "generated. Log in and change it from the Users page now. This password "
            "will not be shown again and is not written to any log file.",
            flush=True,
        )
