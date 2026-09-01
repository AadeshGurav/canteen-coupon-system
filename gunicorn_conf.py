"""Gunicorn config for running the app in production, under uvicorn's ASGI
worker class. Every tunable here reads from an env var with a sane default
for this deployment's actual scale (a single-canteen pilot) — see
CLAUDE.md §7 "config lives in config, not in code"."""

import os

bind = f"0.0.0.0:{os.getenv('APP_PORT', '8000')}"
worker_class = "uvicorn.workers.UvicornWorker"

# This is a single-campus pilot behind nginx, not a high-traffic service —
# a small fixed worker count is plenty and keeps memory use predictable on
# whatever laptop/small box it's deployed on. Override via env if needed.
workers = int(os.getenv("GUNICORN_WORKERS", "2"))

timeout = int(os.getenv("GUNICORN_TIMEOUT", "60"))
graceful_timeout = 30
keepalive = 5

# Recycle workers periodically to bound the impact of any slow memory leak
# over a long-running deployment (jitter avoids all workers restarting at once).
max_requests = int(os.getenv("GUNICORN_MAX_REQUESTS", "1000"))
max_requests_jitter = 50

# Log to stdout/stderr — `docker compose logs` and the json-file driver's
# rotation (configured in docker-compose.yml) are the source of truth for
# process-level logs; app-level logs still go to logs/app.log separately.
accesslog = "-"
errorlog = "-"
loglevel = os.getenv("LOG_LEVEL", "info")
