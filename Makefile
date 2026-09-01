.PHONY: env up down restart build logs ps shell-app shell-mongo clean mdns-setup

# Zero-touch setup: copies the example env on first run only, never
# overwrites an existing .env (CLAUDE.md §9 "zero-touch setup").
env:
	@test -f .env || (cp .env.example .env && echo "Created .env — edit MONGO_ROOT_PASSWORD before deploying.")

up: env
	docker compose up -d --build

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

# Stops and removes containers + networks, but keeps volumes (data, bills,
# QR codes, logs) — use `docker compose down -v` yourself if you actually
# want to wipe those too.
clean: down
