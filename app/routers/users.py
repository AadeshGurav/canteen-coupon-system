import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pymongo.errors import DuplicateKeyError

from app.core.database import users
from app.core.security import require_role
from app.schemas.user import UserCreate, UserUpdate
from app.services.auth_service import hash_password
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/users", tags=["users"])
logger = logging.getLogger(__name__)


def _serialize(doc: dict) -> dict:
    doc = dict(doc)
    doc["_id"] = str(doc["_id"])
    doc.pop("password_hash", None)  # never send this back, not even to an admin
    return doc


@router.post("")
async def create_user(payload: UserCreate, current_user: dict = Depends(require_role("admin"))):
    now = datetime.now(timezone.utc)
    doc = {
        "username": payload.username,
        "password_hash": hash_password(payload.password),
        "role": payload.role,
        "status": "active",
        "created_at": now,
        "updated_at": now,
    }
    try:
        result = await users.insert_one(doc)
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"Username '{payload.username}' is already taken.")

    created = await users.find_one({"_id": result.inserted_id})
    logger.info(
        "user.created username=%s role=%s by=%s", payload.username, payload.role, current_user["username"]
    )
    return _serialize(created)


@router.get("")
async def list_users(current_user: dict = Depends(require_role("admin"))):
    docs = await users.find().sort("username", 1).to_list(length=500)
    return [_serialize(d) for d in docs]


@router.patch("/{user_id}")
async def update_user(user_id: str, payload: UserUpdate, current_user: dict = Depends(require_role("admin"))):
    oid = parse_object_id(user_id, "user")
    updates = {}
    if payload.password is not None:
        updates["password_hash"] = hash_password(payload.password)
    if payload.role is not None:
        updates["role"] = payload.role
    if payload.status is not None:
        if str(oid) == current_user["user_id"] and payload.status == "inactive":
            raise HTTPException(status_code=400, detail="You can't deactivate your own account.")
        updates["status"] = payload.status
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    updates["updated_at"] = datetime.now(timezone.utc)
    result = await users.update_one({"_id": oid}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="User not found.")

    logger.info(
        "user.updated user_id=%s fields=%s by=%s", user_id, list(updates.keys()), current_user["username"]
    )
    doc = await users.find_one({"_id": oid})
    return _serialize(doc)


@router.delete("/{user_id}")
async def delete_user(user_id: str, current_user: dict = Depends(require_role("admin"))):
    oid = parse_object_id(user_id, "user")
    if str(oid) == current_user["user_id"]:
        raise HTTPException(status_code=400, detail="You can't delete your own account.")

    result = await users.delete_one({"_id": oid})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="User not found.")
    logger.warning("user.deleted user_id=%s by=%s", user_id, current_user["username"])
    return {"success": True}
