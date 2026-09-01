from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import get_current_user
from app.services.notification_service import (
    dismiss_notification,
    generate_due_notifications,
    list_active_for_role,
)
from app.utils.object_id import parse_object_id

# Every logged-in role can see and dismiss its own notifications — this
# isn't an admin-only feature, it's the reminder surface counter/scanner
# staff act on directly (§ auth roles in docs/PRD.md §4).
router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("")
async def list_notifications(user: dict = Depends(get_current_user)):
    """Lazily computes anything newly due (see notification_service's module
    docstring for why this happens here instead of a scheduled job), then
    returns whatever's currently active and undismissed for this user."""
    await generate_due_notifications(datetime.now(timezone.utc))
    return await list_active_for_role(user["role"], user["username"])


@router.post("/{notification_id}/dismiss")
async def dismiss(notification_id: str, user: dict = Depends(get_current_user)):
    object_id = parse_object_id(notification_id, "notification")
    dismissed = await dismiss_notification(object_id, user["username"])
    if not dismissed:
        raise HTTPException(status_code=404, detail="Notification not found.")
    return {"success": True}
