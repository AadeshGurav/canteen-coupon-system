from fastapi import APIRouter

from app.schemas.scan import ScanRequest, ScanResult, ReversalRequest
from app.services.scan_service import process_scan, reverse_scan

router = APIRouter(prefix="/scan", tags=["scan"])


@router.post("", response_model=ScanResult)
async def scan(payload: ScanRequest):
    """Called by the browser-based scanner page every time a QR/barcode is read.
    Returns a clear accept/reject result the counter operator acts on immediately."""
    return await process_scan(payload.qr_code_id, payload.meal_type_override)


@router.post("/reverse")
async def reverse(payload: ReversalRequest):
    """Undo a mistaken scan within the configured reversal window (default 10 min)."""
    return await reverse_scan(payload.scan_id, payload.reversed_by)
