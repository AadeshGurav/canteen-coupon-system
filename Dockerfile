# syntax=docker/dockerfile:1

# --- Builder: compiles/installs deps into a venv, never shipped itself ---
FROM python:3.12-slim-bookworm AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# build-essential only exists in this stage — Pillow/reportlab ship prebuilt
# wheels for this platform in the common case, but keep a fallback so the
# build doesn't break on a platform without one (e.g. an arm host with no
# matching wheel yet).
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Final: slim runtime image, no compiler, no package manager cache ---
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    APP_PORT=8000

# Non-root by default — least privilege for the app process (CLAUDE.md §7).
RUN groupadd --system canteen \
    && useradd --system --gid canteen --home-dir /app --shell /usr/sbin/nologin canteen

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app ./app
COPY static ./static
COPY gunicorn_conf.py .

# These are volume mount points in production (see docker-compose.yml) —
# created and owned here so a fresh named volume inherits the right owner.
RUN mkdir -p generated_bills generated_qr logs \
    && chown -R canteen:canteen /app

USER canteen

EXPOSE 8000

# No curl/wget in this image on purpose (stays slim) — a stdlib request is
# enough to hit the app's own /health endpoint. 127.0.0.1, not "localhost":
# see the nginx healthcheck comment in docker-compose.yml for why relying on
# hostname resolution order here would be fragile even though this
# particular client (urllib) happens to fall back correctly.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/health', timeout=3)" || exit 1

CMD ["gunicorn", "app.main:app", "-c", "gunicorn_conf.py"]
