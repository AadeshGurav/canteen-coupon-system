#!/usr/bin/env bash
#
# Optional (but strongly recommended) — generates a locally-trusted TLS
# certificate via mkcert and activates nginx's :443 server block.
#
# Why this exists at all: browsers only allow camera access (getUserMedia,
# which the scanner page needs) in a "secure context" — HTTPS, or literally
# localhost — and that rule applies even on a fully private, offline LAN.
# Without this, the scanner's camera permission prompt never appears; see
# docs/PRD.md §7 and docs/USER_GUIDE.md's troubleshooting section.
#
# `make up` alone still brings up a working app on plain :80 — this only
# adds :443. Safe to skip if you're not using the scanner from a browser
# yet; safe to re-run.
#
# Usage:
#   scripts/setup_tls.sh                 # interactive, asks before installing anything
#   scripts/setup_tls.sh --yes           # skip confirmation prompts
#
# Config: MDNS_HOSTNAME (same variable `make mdns-setup` uses, default
# "canteen") — the cert is issued for <MDNS_HOSTNAME>.local plus this
# machine's current LAN IP and localhost, so it works whether a device
# reaches this host by name or by raw IP. Read from .env if set there, per
# CLAUDE.md §7 ("config lives in config, not in code").

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CERTS_DIR="$REPO_ROOT/nginx/certs"
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

if [ -f "$REPO_ROOT/.env" ] && [ -z "${MDNS_HOSTNAME:-}" ]; then
  ENV_VALUE="$(grep -E '^MDNS_HOSTNAME=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  [ -n "$ENV_VALUE" ] && MDNS_HOSTNAME="$ENV_VALUE"
fi
MDNS_HOSTNAME="${MDNS_HOSTNAME:-canteen}"

HTTPS_PORT="443"
if [ -f "$REPO_ROOT/.env" ]; then
  ENV_PORT="$(grep -E '^HTTPS_PORT=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  [ -n "$ENV_PORT" ] && HTTPS_PORT="$ENV_PORT"
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

detect_lan_ip() {
  # Best-effort — an extra SAN on the cert, not a hard requirement, since
  # the .local name is the primary address this is meant to support.
  case "$(uname -s)" in
    Linux)  hostname -I 2>/dev/null | awk '{print $1}' ;;
    Darwin) ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null ;;
    *)      echo "" ;;
  esac
}

install_mkcert_linux() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  MKCERT_ARCH="amd64" ;;
    aarch64) MKCERT_ARCH="arm64" ;;
    *) fail "Unsupported architecture ($ARCH) for automatic mkcert install. Install mkcert manually from https://github.com/FiloSottile/mkcert and re-run." ;;
  esac

  if command -v apt-get >/dev/null 2>&1; then
    confirm "Install libnss3-tools (needed so Firefox/Chrome on this machine trust the generated CA)?" \
      && (sudo apt-get update -qq && sudo apt-get install -y libnss3-tools || echo "⚠ libnss3-tools install failed — continuing anyway, nginx/curl don't need it.")
  fi

  TMP_BIN="$(mktemp)"
  echo "Downloading mkcert for linux/$MKCERT_ARCH..."
  curl -fsSL -o "$TMP_BIN" "https://dl.filippo.io/mkcert/latest?for=linux/$MKCERT_ARCH" \
    || fail "Could not download mkcert. Check your internet connection (this is a one-time download, not needed again after)."
  chmod +x "$TMP_BIN"
  sudo mv "$TMP_BIN" /usr/local/bin/mkcert \
    || fail "Could not install mkcert to /usr/local/bin — check sudo access."
}

install_mkcert_macos() {
  if command -v brew >/dev/null 2>&1; then
    brew install mkcert nss || fail "brew install mkcert failed — see the output above."
  else
    fail "Homebrew isn't installed. Install it from https://brew.sh, or install mkcert manually from https://github.com/FiloSottile/mkcert, then re-run."
  fi
}

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert isn't installed."
  confirm "Install it now?" || fail "Can't generate a trusted certificate without mkcert. Re-run with --yes, or install it yourself and re-run."
  case "$(uname -s)" in
    Linux)  install_mkcert_linux ;;
    Darwin) install_mkcert_macos ;;
    *) fail "Unsupported OS ($(uname -s)) for automatic mkcert install. See https://github.com/FiloSottile/mkcert for manual instructions." ;;
  esac
fi
echo "✓ mkcert is available"

# Installs (or confirms) mkcert's local CA into this machine's trust
# stores — the admin laptop itself needs no further manual step.
mkcert -install || fail "mkcert -install failed — see the output above."
echo "✓ local CA trusted on this machine"

mkdir -p "$CERTS_DIR"
LAN_IP="$(detect_lan_ip)"
CERT_HOSTS=("${MDNS_HOSTNAME}.local" "localhost" "127.0.0.1")
[ -n "$LAN_IP" ] && CERT_HOSTS+=("$LAN_IP")

echo "Generating certificate for: ${CERT_HOSTS[*]}"
mkcert -cert-file "$CERTS_DIR/tls.pem" -key-file "$CERTS_DIR/tls-key.pem" "${CERT_HOSTS[@]}" \
  || fail "mkcert failed to generate the certificate — see the output above."
echo "✓ wrote $CERTS_DIR/tls.pem and tls-key.pem"

CAROOT="$(mkcert -CAROOT)"
if [ -f "$CAROOT/rootCA.pem" ]; then
  cp "$CAROOT/rootCA.pem" "$CERTS_DIR/rootCA.pem"
  echo "✓ copied the root CA to $CERTS_DIR/rootCA.pem — this is the file to install on each phone (see docs/USER_GUIDE.md §2.3)"
else
  echo "⚠ Couldn't find rootCA.pem under $CAROOT — mkcert -install above should have created it."
fi

cp "$REPO_ROOT/nginx/conf.d/canteen-tls.conf.example" "$REPO_ROOT/nginx/conf.d/canteen-tls.conf"
echo "✓ activated nginx/conf.d/canteen-tls.conf"

echo ""
echo "Done. Restart nginx to pick this up:"
echo "  docker compose restart nginx"
echo ""
echo "Then, from another device on the same network:"
if [ "$HTTPS_PORT" = "443" ]; then
  echo "  https://${MDNS_HOSTNAME}.local/static/scanner.html"
else
  echo "  https://${MDNS_HOSTNAME}.local:${HTTPS_PORT}/static/scanner.html"
fi
echo ""
echo "That device will show a certificate warning until you install"
echo "$CERTS_DIR/rootCA.pem on it — see docs/USER_GUIDE.md §2.3 for the"
echo "one-time steps on iOS and Android. No root/jailbreak needed."
