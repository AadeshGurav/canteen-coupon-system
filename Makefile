.PHONY: env up start down restart build logs ps shell-app shell-mongo clean mdns-setup tls-setup

# Zero-touch setup: copies the example env on first run only, never
# overwrites an existing .env (CLAUDE.md §9 "zero-touch setup").
env:
	@test -f .env || (cp .env.example .env && echo "Created .env — edit MONGO_ROOT_PASSWORD before deploying.")

# Builds, then starts. Use this the first time, or any time app code/
# dependencies changed (Dockerfile, requirements.txt, app/, static/) — it
# rebuilds the image every time, which is correct there but wasteful for a
# plain restart with no code changes; use `make start` for that instead.
up: env
	docker compose up -d --build

# Starts the existing images without rebuilding — the fast path for "just
# bring the stack back up" (reboot, `make down` earlier, etc.) when nothing
# in the image has changed. Falls back to building only if no image exists
# yet, same as a bare `docker compose up` would.
start: env
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

build:
	docker compose build

logs:
	docker compose logs -f

ps:
	docker compose ps

shell-app:
	docker compose exec app /bin/sh

shell-mongo:
	docker compose exec mongo mongosh -u "$$(grep MONGO_ROOT_USER .env | cut -d= -f2)" -p "$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2)" --authenticationDatabase admin

# Optional, not part of `make up`. Publishes this machine as <hostname>.local
# on the local network (mDNS) so devices on a phone hotspot can reach it by
# name instead of an IP that can change every time the hotspot restarts —
# see docs/PRD.md's local-network hosting notes and scripts/setup_mdns.sh
# for the full explanation. Safe to skip; safe to re-run.
mdns-setup:
	@bash scripts/setup_mdns.sh

# Optional but strongly recommended, not part of `make up`. Generates a
# locally-trusted TLS certificate (mkcert) and activates nginx's :443
# block — required for the scanner page's camera to work at all, since
# browsers only allow camera access in a secure context (HTTPS or
# localhost), even on a private LAN. See scripts/setup_tls.sh and
# docs/USER_GUIDE.md §2.3 for the one-time per-device trust step this
# needs on each phone. Safe to re-run; run `make restart` (or
# `docker compose restart nginx`) after to pick up a newly generated cert.
tls-setup:
	@bash scripts/setup_tls.sh

# Stops and removes containers + networks, but keeps volumes (data, bills,
# QR codes, logs) — use `docker compose down -v` yourself if you actually
# want to wipe those too.
clean: down
