import os
import uuid

import qrcode

from app.core.config import settings


def generate_qr_code_id() -> str:
    """Generate a new unique code id for a member. This is stored permanently
    and reused for reprints — losing a card never means creating a new one."""
    return uuid.uuid4().hex[:12]


def render_qr_image(qr_code_id: str) -> str:
    """Render (or re-render) the QR image for a given code id and return its file path.
    Safe to call repeatedly for reprints since the code id itself never changes."""
    os.makedirs(settings.qr_output_dir, exist_ok=True)
    path = os.path.join(settings.qr_output_dir, f"{qr_code_id}.png")
    img = qrcode.make(qr_code_id)
    img.save(path)
    return path
