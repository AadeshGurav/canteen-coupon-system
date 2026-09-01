import logging
import logging.handlers
import os

from app.core.config import settings


def configure_logging() -> None:
    """Application-level logging: every scan decision, top-up, refund, and
    admin action logs here — this is the admin's own debugging tool, so it
    has to be readable without reproducing the issue (see docs/PRD.md §7)."""
    root_logger = logging.getLogger()
    if root_logger.handlers:
        return  # already configured (e.g. --reload re-importing this module)

    os.makedirs(settings.logs_dir, exist_ok=True)
    log_path = os.path.join(settings.logs_dir, "app.log")

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )

    file_handler = logging.handlers.RotatingFileHandler(log_path, maxBytes=5_000_000, backupCount=5)
    file_handler.setFormatter(formatter)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)

    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
