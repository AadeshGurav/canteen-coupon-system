# Testing — what's actually verified

This is a plain-English map of the automated test suite, for anyone deciding
whether to trust this system without reading test code. For the live,
per-commit result (pass/fail, right now, for the exact code on `main`), see
the **"Unit tests (pytest)"** job on the latest run of the
[CI workflow](https://github.com/AadeshGurav/canteen-coupon-system/actions/workflows/ci.yml)
— its job summary lists every test below by name, with a ✅/❌/⏭️ next to
each one. That summary is generated automatically
(`scripts/generate_test_summary.py`) from the exact same test run reported
here, so it can't drift out of sync with what actually ran.

Every test in this suite runs against real logic — no mocked-out business
rules — using either in-memory fake MongoDB collections (`tests/fakes.py`,
for speed and no external dependency) or, for one race-condition test, a
real MongoDB instance.

## The scan decision — the highest-stakes flow in the system

`tests/test_scan_service.py` — every branch of the accept/reject decision a
counter operator's screen shows, tested independently:

- An unknown QR code is rejected with a clear reason.
- An inactive member's code is rejected, not silently accepted.
- Scanning outside any configured meal window is rejected.
- A successful scan deducts exactly one unit of the right meal type.
- A member can't be scanned twice for the same meal on the same day — and
  this lock holds even when a counter operator manually overrides the meal
  type, so it can't be used to bypass the one-scan-per-day rule.
- Running out of units is rejected — unless grace allowance applies.
- Grace allowance lets a balance go negative down to its configured floor,
  and no further; a per-member override takes precedence over the global
  default.
- Reversing a scan restores the unit and marks it reversed (not deleted, so
  the audit trail survives) — reversing the same scan twice is rejected, and
  reversal outside the configured time window is rejected.
- Every scan timestamp is stored timezone-aware, never ambiguous local time.

## Meal-window and timezone resolution

`tests/test_meal_window.py` — the logic that decides "what meal is being
served right now, in the canteen's own local time":

- Saturday is correctly detected, and only Saturday resolves to brunch.
- Weekday scans correctly resolve to breakfast/lunch/no-meal based on the
  clock.
- All local-time conversion is verified against UTC edge cases, including
  the moment where UTC and the canteen's local calendar day disagree (late
  evening UTC can already be "tomorrow" locally) — a real bug class for any
  system with users outside UTC.

## Authentication and sessions

`tests/test_auth_service.py` — the login system backing every role:

- Correct credentials authenticate; wrong password, unknown username, and a
  deactivated account all fail the same way (no difference in behavior an
  attacker could use to tell which case they hit).
- Two hashes of the same password are never identical (salted), and a
  corrupted/malformed stored hash fails closed rather than throwing.
- A created session is retrievable; an unknown token, an expired session,
  and a deleted session are all correctly rejected.
- The one-time initial admin account is created only when no users exist yet
  — running startup again afterward is a no-op, not a duplicate account.

`tests/test_database_integration.py` — the multi-worker race this system
actually runs under (gunicorn spawns several worker processes that can all
hit "create the first admin" or "create the settings document" at the same
instant on a fresh database): verified against a real MongoDB instance that
concurrent first-time calls never crash a worker or create duplicates. This
test self-skips (shown as ⏭️ in CI) when no reachable MongoDB is configured,
since it needs the real thing, not a fake, to prove a race condition is
actually closed.

## Input validation

`tests/test_schemas.py` and `tests/test_settings.py` — every boundary a
person could hit through the API or the dashboard forms:

- A student can't carry a staff ID, and staff can't carry a class/roll
  number — the two member types stay cleanly separated.
- Negative credit units and blank names are rejected before they ever reach
  the database.
- A menu entry needs at least one category and at least one item.
- A top-up or a refund needs at least one non-zero unit — a request for zero
  units is rejected server-side even if a UI bug ever let one through.
- Settings updates reject an invalid IANA timezone name.

## What's deliberately not covered here

- End-to-end HTTP request/response cycles through the real FastAPI app are
  covered by `scripts/smoke_test.py`, run in CI against the actual running
  Docker stack (see the **"Docker build, vulnerability scan, compose smoke
  test"** job) — login, member creation, a top-up, and a scan, through nginx,
  against a real MongoDB. This is deliberately a smoke test (one full happy
  path), not a second copy of the unit test suite.
- Frontend JavaScript has no automated test suite yet — it's plain,
  framework-free JS with no build step, verified manually against the live
  stack before each change ships (see commit history for what was checked).
