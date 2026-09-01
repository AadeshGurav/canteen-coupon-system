import os
import urllib.parse

import qrcode
from reportlab.lib.pagesizes import A5
from reportlab.pdfgen import canvas

from app.core.config import settings


def generate_upi_qr(amount: float, note: str, topup_id: str, upi_id: str, upi_payee_name: str) -> str | None:
    """Generate a UPI payment QR using the standard upi:// URI scheme.
    Returns None if no UPI ID is configured (cash-only setups). upi_id/
    upi_payee_name come from the admin-editable settings document (see
    app/routers/settings.py), not env config — the admin can set these
    without a restart."""
    if not upi_id:
        return None

    params = {
        "pa": upi_id,  # payee address
        "pn": upi_payee_name,  # payee name
        "am": f"{amount:.2f}",
        "cu": "INR",
        "tn": note,
    }
    upi_uri = "upi://pay?" + urllib.parse.urlencode(params)

    os.makedirs(settings.qr_output_dir, exist_ok=True)
    path = os.path.join(settings.qr_output_dir, f"upi_{topup_id}.png")
    img = qrcode.make(upi_uri)
    img.save(path)
    return path


def generate_bill_pdf(
    topup_id: str,
    member_name: str,
    member_type: str,
    lunch_units: int,
    breakfast_units: int,
    brunch_units: int,
    amount: float,
    payment_method: str,
    new_balances: dict,
) -> str:
    """The UPI payment QR is deliberately not on this bill — it's shown to
    the admin in a dashboard modal at the moment of payment (see
    GET /topups/{id}/upi-qr) instead, since the bill is a record of the
    transaction and outlives the pending-payment moment the QR is for."""
    os.makedirs(settings.bills_output_dir, exist_ok=True)
    path = os.path.join(settings.bills_output_dir, f"bill_{topup_id}.pdf")

    c = canvas.Canvas(path, pagesize=A5)
    _, height = A5

    y = height - 40
    c.setFont("Helvetica-Bold", 14)
    c.drawString(30, y, settings.app_name)
    y -= 25
    c.setFont("Helvetica", 10)
    c.drawString(30, y, f"Bill ID: {topup_id}")
    y -= 15
    c.drawString(30, y, f"Member: {member_name} ({member_type})")
    y -= 25

    c.setFont("Helvetica-Bold", 11)
    c.drawString(30, y, "Units purchased:")
    y -= 15
    c.setFont("Helvetica", 10)
    c.drawString(40, y, f"Lunch: {lunch_units}   Breakfast: {breakfast_units}   Brunch: {brunch_units}")
    y -= 20

    c.setFont("Helvetica-Bold", 11)
    c.drawString(30, y, f"Amount: Rs. {amount:.2f}  ({payment_method.upper()})")
    y -= 25

    c.setFont("Helvetica-Bold", 11)
    c.drawString(30, y, "New balances:")
    y -= 15
    c.setFont("Helvetica", 10)
    c.drawString(
        40,
        y,
        f"Lunch: {new_balances.get('lunch', 0)}   "
        f"Breakfast: {new_balances.get('breakfast', 0)}   "
        f"Brunch: {new_balances.get('brunch', 0)}",
    )

    c.showPage()
    c.save()
    return path
