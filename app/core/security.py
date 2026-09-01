"""FastAPI dependencies for authentication and role-based access.

Roles, per docs/PRD.md §4: `admin` (everything), `counter` (scan + top-ups —
staffs the counter and handles payment), `scanner` (scan only — a shared
kiosk device with nothing else on it worth protecting)."""

from typing import Literal

from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.services.auth_service import get_session

Role = Literal["admin", "counter", "scanner"]

# auto_error=False: a missing header should produce our own clear 401
# message below, not FastAPI's generic "Not authenticated".
_bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Security(_bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not logged in.")
    session = await get_session(credentials.credentials)
    if session is None:
        raise HTTPException(status_code=401, detail="Session expired or invalid — please log in again.")
    return session


def require_role(*allowed_roles: Role):
    """Dependency factory: `Depends(require_role("admin", "counter"))`."""

    async def _check(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in allowed_roles:
            raise HTTPException(
                status_code=403,
                detail=f"Your role ({user['role']}) doesn't have access to this action.",
            )
        return user

    return _check
