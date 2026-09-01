#!/usr/bin/env bash
#
# Optional convenience script — publishes this machine on the local network
# as `<hostname>.local` via mDNS, so devices on a phone hotspot (whose DHCP
# server and subnet can't be pinned without rooting the phone — see
# docs/PRD.md's local-network hosting notes) can reach it by name instead
# of chasing a changing IP.
#
# Nothing here is required for the app to run — `make up` alone is a
# complete setup. This only adds a friendlier, more stable address on top.
# Safe to skip, safe to re-run.
#
# Usage:
#   scripts/setup_mdns.sh                 # interactive, asks before changing anything
#   scripts/setup_mdns.sh --yes           # skip the confirmation prompt
#   MDNS_HOSTNAME=front-counter scripts/setup_mdns.sh
#
# Config: MDNS_HOSTNAME (default: canteen) — read from the environment, or
# from .env if present, per CLAUDE.md §7 ("config lives in config, not in
# code"). Never hardcode a hostname below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--yes]" >&2
      exit 1
      ;;
  esac
done

# Pick up MDNS_HOSTNAME from .env if it's set there and not already exported,
# so this behaves consistently with how the rest of the project reads config.
if [ -f "$REPO_ROOT/.env" ] && [ -z "${MDNS_HOSTNAME:-}" ]; then
  ENV_VALUE="$(grep -E '^MDNS_HOSTNAME=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  if [ -n "$ENV_VALUE" ]; then
    MDNS_HOSTNAME="$ENV_VALUE"
  fi
fi
MDNS_HOSTNAME="${MDNS_HOSTNAME:-canteen}"

HTTP_PORT="80"
if [ -f "$REPO_ROOT/.env" ]; then
  ENV_PORT="$(grep -E '^HTTP_PORT=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  if [ -n "$ENV_PORT" ]; then
    HTTP_PORT="$ENV_PORT"
  fi
fi

fail() {
  # Errors are specific, not generic — CLAUDE.md §8.
  echo "✗ $1" >&2
  exit 1
}

confirm() {
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  read -r -p "$1 [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

print_result_url() {
  echo ""
  echo "Done. From another device on the same network, try:"
  if [ "$HTTP_PORT" = "80" ]; then
    echo "  http://${MDNS_HOSTNAME}.local/static/scanner.html"
    echo "  http://${MDNS_HOSTNAME}.local/static/admin/index.html"
  else
    echo "  http://${MDNS_HOSTNAME}.local:${HTTP_PORT}/static/scanner.html"
    echo "  http://${MDNS_HOSTNAME}.local:${HTTP_PORT}/static/admin/index.html"
  fi
  echo ""
  echo "If the phone hotspot's subnet changes (Android randomizes it on every"
  echo "restart since Android 11), this name keeps working without redoing"
  echo "anything — that's the whole point."
}

setup_linux() {
  if ! command -v systemctl >/dev/null 2>&1; then
    fail "systemctl not found — this script's Linux path assumes systemd (e.g. Ubuntu). Set up Avahi manually if you're on something else."
  fi

  if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    echo "avahi-daemon isn't running yet."
    if ! command -v avahi-daemon >/dev/null 2>&1; then
      confirm "Install avahi-daemon now (sudo apt install avahi-daemon avahi-utils)?" \
        || fail "Can't publish a .local name without Avahi. Re-run with --yes, or install it yourself and re-run."
      sudo apt-get update -qq && sudo apt-get install -y avahi-daemon avahi-utils \
        || fail "avahi-daemon install failed — check apt's output above."
    fi
    sudo systemctl enable --now avahi-daemon \
      || fail "Could not start avahi-daemon via systemctl."
  fi
  echo "✓ avahi-daemon is running"

  CURRENT_HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname)"
  if [ "$CURRENT_HOSTNAME" != "$MDNS_HOSTNAME" ]; then
    confirm "Set this machine's hostname to '$MDNS_HOSTNAME' (currently '$CURRENT_HOSTNAME')? This is a system-wide change, not app-specific." \
      || fail "Left hostname unchanged — re-run with a different MDNS_HOSTNAME, or --yes to accept this one."
    sudo hostnamectl set-hostname "$MDNS_HOSTNAME" \
      || fail "hostnamectl failed to set the hostname."
  fi
  echo "✓ hostname is '$MDNS_HOSTNAME'"

  if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw allow 5353/udp >/dev/null 2>&1 || true
    echo "✓ opened 5353/udp (mDNS) in ufw"
  fi

  if command -v avahi-resolve >/dev/null 2>&1; then
    sleep 1
    if avahi-resolve -n "${MDNS_HOSTNAME}.local" >/dev/null 2>&1; then
      echo "✓ ${MDNS_HOSTNAME}.local resolves locally"
    else
      echo "⚠ ${MDNS_HOSTNAME}.local didn't resolve yet — this can take a few seconds after a hostname change; try again shortly."
    fi
  fi
}

setup_macos() {
  CURRENT_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || echo "")"
  if [ "$CURRENT_HOSTNAME" != "$MDNS_HOSTNAME" ]; then
    confirm "Set this Mac's Bonjour hostname to '$MDNS_HOSTNAME' (currently '${CURRENT_HOSTNAME:-unset}')?" \
      || fail "Left Bonjour hostname unchanged — re-run with a different MDNS_HOSTNAME, or --yes to accept this one."
    sudo scutil --set LocalHostName "$MDNS_HOSTNAME" \
      || fail "scutil failed to set the local hostname."
  fi
  echo "✓ Bonjour hostname is '$MDNS_HOSTNAME' (mDNSResponder ships with macOS — nothing to install)"

  if command -v dns-sd >/dev/null 2>&1; then
    sleep 1
    if timeout 3 dns-sd -q "${MDNS_HOSTNAME}.local" 2>/dev/null | grep -q "${MDNS_HOSTNAME}.local"; then
      echo "✓ ${MDNS_HOSTNAME}.local resolves locally"
    else
      echo "⚠ Couldn't confirm resolution in 3s — this is often just timing; try 'ping ${MDNS_HOSTNAME}.local' in a moment."
    fi
  fi
}

case "$(uname -s)" in
  Linux)  setup_linux ;;
  Darwin) setup_macos ;;
  *)
    fail "Unsupported OS ($(uname -s)). This script covers Linux (systemd + Avahi) and macOS (Bonjour). On Windows, install Bonjour Print Services from Apple and set the computer name manually instead."
    ;;
esac

print_result_url
