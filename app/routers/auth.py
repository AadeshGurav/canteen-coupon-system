import logging

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import get_current_user
from app.schemas.user import LoginRequest, LoginResponse
from app.services.auth_service import authenticate, create_session, delete_session

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)


@router.post("/login", response_model=LoginResponse)
async def login(payload: LoginRequest):
    user = await authenticate(payload.username, payload.password)
    if user is None:
        # Deliberately identical message for "no such user" and "wrong
        # password" — see authenticate()'s docstring.
        logger.warning("auth.login_failed username=%s", payload.username)
        raise HTTPException(status_code=401, detail="Incorrect username or password.")

    token = await create_session(user)
    logger.info("auth.login_succeeded username=%s role=%s", user["username"], user["role"])
    return LoginResponse(token=token, username=user["username"], role=user["role"])


@router.post("/logout")
async def logout(user: dict = Depends(get_current_user)):
    await delete_session(user["_id"])
    logger.info("auth.logout username=%s", user["username"])
    return {"success": True}


@router.get("/me")
async def me(user: dict = Depends(get_current_user)):
    return {"username": user["username"], "role": user["role"]}
