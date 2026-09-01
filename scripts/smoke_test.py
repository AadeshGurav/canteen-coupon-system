"""End-to-end smoke test for a *running* stack — exercises the same flow
verified manually during development: log in, create a member, credit a
balance, open a meal window, scan (accept), scan again (rejected as a
duplicate).

Stdlib-only on purpose — this is a CI/ops helper, not part of the app, so it
shouldn't need its own dependency install step.

Usage:
    docker compose up -d --build --wait
    python scripts/smoke_test.py [base_url] [admin_username] [admin_password]
    # base_url defaults to http://localhost:8080
    # credentials default to admin / whatever INITIAL_ADMIN_PASSWORD the
    # stack was started with (see .env) — pass them explicitly if different.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
ADMIN_USERNAME = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("SMOKE_TEST_ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("SMOKE_TEST_ADMIN_PASSWORD", "")

_auth_token: str | None = None


def call(method: str, path: str, body: dict | None = None, *, authenticated: bool = True) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if authenticated:
        if _auth_token is None:
            raise AssertionError("call() used authenticated=True before login() ran")
        headers["Authorization"] = f"Bearer {_auth_token}"

    request = urllib.request.Request(f"{BASE_URL}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise AssertionError(f"{method} {path} -> HTTP {error.code}: {error.read().decode()}") from error


def login() -> None:
    global _auth_token
    if not ADMIN_PASSWORD:
        raise AssertionError(
            "No admin password to log in with — pass one as the 3rd argument, or set "
            "SMOKE_TEST_ADMIN_PASSWORD to match whatever INITIAL_ADMIN_PASSWORD the stack used."
        )
    response = call(
        "POST", "/auth/login", {"username": ADMIN_USERNAME, "password": ADMIN_PASSWORD}, authenticated=False
    )
    _auth_token = response["token"]


def check(condition: bool, description: str) -> None:
    if not condition:
        raise AssertionError(f"FAILED: {description}")
    print(f"  ok: {description}")


def main() -> None:
    print(f"Running smoke test against {BASE_URL}\n")

    health = call("GET", "/health", authenticated=False)
    check(health.get("status") == "ok", "/health reports ok")

    login()
    check(_auth_token is not None, "admin login succeeds and returns a session token")

    member = call(
        "POST",
        "/members",
        {"type": "student", "name": "CI Smoke Test", "class_name": "1A", "roll_number": "0"},
    )
    check(
        member["balances"] == {"lunch": 0, "breakfast": 0, "brunch": 0}, "new member starts at zero balance"
    )
    check(bool(member.get("qr_code_id")), "member was issued a QR code")

    member = call("POST", f"/members/{member['_id']}/credit", {"breakfast_units": 1})
    check(member["balances"]["breakfast"] == 1, "credit applied to the right balance")

    # Force the breakfast window open right now so the scan below is deterministic.
    now = datetime.now(timezone.utc)
    call(
        "PATCH",
        "/settings",
        {
            "meal_windows": {
                "breakfast": {
                    "start": now.strftime("%H:%M"),
                    "end": (now + timedelta(minutes=30)).strftime("%H:%M"),
                }
            }
        },
    )

    result = call("POST", "/scan", {"qr_code_id": member["qr_code_id"]})
    check(result["result"] == "accepted", f"scan accepted (got: {result})")
    check(result["remaining_balance"] == 0, "balance deducted by exactly one unit")

    duplicate = call("POST", "/scan", {"qr_code_id": member["qr_code_id"]})
    check(duplicate["result"] == "rejected_already_scanned", "second scan same meal/day is rejected")

    unknown = call("POST", "/scan", {"qr_code_id": "does-not-exist"})
    check(unknown["result"] == "rejected_unknown_code", "unknown QR code is rejected")

    print("\nAll smoke checks passed.")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, urllib.error.URLError, OSError) as error:
        print(f"\nSMOKE TEST FAILED: {error}", file=sys.stderr)
        sys.exit(1)
