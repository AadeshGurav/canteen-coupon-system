from fastapi import APIRouter, Depends

from app.core.database import scans
from app.core.security import require_role
from app.schemas.scan import ReversalRequest, ScanRequest, ScanResult
from app.services.scan_service import process_scan, reverse_scan

router = APIRouter(prefix="/scan", tags=["scan"])


@router.post(
    "", response_model=ScanResult, dependencies=[Depends(require_role("admin", "counter", "scanner"))]
)
async def scan(payload: ScanRequest):
    """Called by the browser-based scanner page every time a QR/barcode is read.
    Returns a clear accept/reject result the counter operator acts on immediately."""
    return await process_scan(payload.qr_code_id, payload.meal_type_override)


@router.post("/reverse", dependencies=[Depends(require_role("admin"))])
async def reverse(payload: ReversalRequest):
    """Undo a mistaken scan within the configured reversal window (default 10 min)."""
    return await reverse_scan(payload.scan_id, payload.reversed_by)


@router.get("", dependencies=[Depends(require_role("admin"))])
async def list_scans(member_id: str | None = None, limit: int = 200):
    """Recent scan history, most recent first — backs the admin's scan log/audit
    view and lets the admin find a scan_id to reverse."""
    query = {"member_id": member_id} if member_id else {}
    docs = await scans.find(query).sort("scanned_at", -1).to_list(length=min(limit, 1000))
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs
