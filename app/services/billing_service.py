import os
import urllib.parse

import qrcode
from reportlab.lib.pagesizes import A5
from reportlab.pdfgen import canvas

from app.core.config import settings


def generate_upi_qr(amount: float, note: str, topup_id: str) -> str | None:
    """Generate a UPI payment QR using the standard upi:// URI scheme.
    Returns None if no UPI ID is configured (cash-only setups)."""
    if not settings.upi_id:
        return None

    params = {
        "pa": settings.upi_id,  # payee address
        "pn": settings.upi_payee_name,  # payee name
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
    upi_qr_path: str | None,
) -> str:
    os.makedirs(settings.bills_output_dir, exist_ok=True)
    path = os.path.join(settings.bills_output_dir, f"bill_{topup_id}.pdf")

    c = canvas.Canvas(path, pagesize=A5)
    width, height = A5

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
    y -= 30

    if upi_qr_path and os.path.exists(upi_qr_path):
        c.drawString(30, y, "Scan to pay via UPI:")
        c.drawImage(upi_qr_path, 30, y - 110, width=100, height=100)

    c.showPage()
    c.save()
    return path
