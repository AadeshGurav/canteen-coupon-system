# Canteen Coupon System

[![CI](https://github.com/AadeshGurav/canteen-coupon-system/actions/workflows/ci.yml/badge.svg)](https://github.com/AadeshGurav/canteen-coupon-system/actions/workflows/ci.yml)
[![Publish Docker image](https://github.com/AadeshGurav/canteen-coupon-system/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/AadeshGurav/canteen-coupon-system/actions/workflows/docker-publish.yml)

A unit-based meal coupon system for a school canteen — replaces paper tracking of
student and staff meal entitlements with QR-code scanning, configurable balances,
and admin-managed billing. Built for a single campus, single canteen pilot.

Full requirements: [`docs/PRD.md`](docs/PRD.md)
For canteen staff/admin day-to-day usage: [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)
What's actually tested, in plain English: [`docs/TESTING.md`](docs/TESTING.md)

---

## 1. What this does (non-technical overview)

**For students and staff:** each person gets a printed QR code. At the canteen
counter, they scan it, the system checks whether they have a meal unit available,
and either confirms ("go ahead, collect your lunch") or rejects it, instantly.

**For the admin (the canteen contractor):**
- Add, edit, or remove students and staff as **member entities** — the same kind
  of record for both, just priced differently.
- Each member entity has three separate balances: **lunch units**, **breakfast
  units**, and **brunch units** (brunch only applies on Saturdays, when there's a
  single combined meal instead of separate breakfast and lunch).
- Top up a member's balance when a parent (for a student) or a staff member pays —
  by cash or by scanning a generated UPI QR code shown in a pop-up — and get a PDF
  bill automatically, with the amount computed from per-unit prices, never typed
  in by hand.
- Print or reprint a member's QR code. Reprinting never issues a new code, so a
  lost card can't create a duplicate record.
- Set a **grace allowance** — how many meals, if any, a member can take on credit
  before being turned away — globally or per member.
- Plan the menu on an interactive month calendar (admin-only planning tool, not
  shown to students or staff).
- Track expenses (groceries, tables, etc.) against revenue to see a simple
  profit picture.
- Undo a scan by mistake within a configurable time window (default 10 minutes).
- Adjust meal serving times, unit prices, grace allowance, timezone, branding, and
  the reversal window from settings — none of this is hardcoded, so it can be
  tuned without a code change.
- Manage login accounts and roles (admin/counter/scanner) for everyone else who
  uses the system.

**Roles:** every page requires signing in. **Admin** has full access;
**counter** can scan and record top-ups; **scanner** can only scan. See
`docs/PRD.md` §4 for the full breakdown.

**What it's not:** this doesn't hold or move real money. It tracks meal
*entitlements*, not a cash wallet. UPI is used only to generate a payment QR code —
there's no payment gateway integration, so the admin confirms UPI payments manually
once they see the money land in their own account.

## 2. Features at a glance

| Area | What's included |
|---|---|
| Member management | Full CRUD for student & staff entities, plus `POST /members/bulk` for paper-to-digital migration (each row succeeds/fails independently) |
| QR codes | Generate on creation, print, reprint (same code, never duplicated) |
| Scanning | Single shared scanner page (phone browser), instant accept/reject, one scan per meal window |
| Balances | Separate lunch / breakfast / brunch unit counts, grace allowance (global + per-member override), **no automatic resets ever** — only scans, reversals, top-ups, and refunds change a balance |
| Top-ups & billing | Cash or UPI QR (shown in a pop-up, not on the bill), automatic PDF bill generation, amount auto-calculated from unit prices, manual UPI payment confirmation |
| Reversal | Undo a mistaken scan within a configurable window, restores the unit |
| Grace tracking | Any meal given on the grace allowance is flagged (`via_grace`) on the scan record and shown as a badge on the scanner screen; the Members page shows how many grace units each member has left |
| Menu planning | Admin-only interactive month calendar of what's served, per date, per meal, tagged with admin-managed menu categories (e.g. Jain, Normal, Staff) |
| Refunds | Admin records a refund (units, pre-filled from the member's actual balance; amount auto-calculated from unit prices) when a member leaves; deducts the balance immediately, payout itself is handled outside the app |
| Expenses | Log spend, see revenue vs. expense summary |
| Auth & roles | Login required everywhere; admin/counter/scanner roles with distinct permissions; admin-managed Users page for account CRUD |
| Settings | Meal windows, unit prices, grace allowance, timezone (dropdown of every IANA zone), UPI details, branding, reversal window — all DB-backed, all editable at runtime |
| Admin dashboard | Browser UI (`/static/admin/`) covering every admin action above — member CRUD, top-ups/billing, scan log & reversal, menu planning, expenses, refunds, settings, users — no more driving the API by hand through `/docs` |

---

## 3. Technical overview

**Stack:** Python (FastAPI, async) · MongoDB (via Motor) · plain HTML/JS for the
scanner page and the admin dashboard (no frontend framework) · ReportLab for PDF
bills · `qrcode` for QR generation.

**Why this stack:** small single-canteen pilot, not a high-scale system — FastAPI
gives free request validation and async support without Django-level scaffolding;
MongoDB suits the somewhat variable shape of member records; the scanner page is
deliberately framework-free since it needs to sit open on a phone browser for
hours without memory bloat. The admin dashboard follows the same no-framework,
no-build-step approach for consistency and to keep the whole thing runnable from
a single `uvicorn` process with zero tooling beyond a browser.

### Project layout

```
app/
  core/       — config (env vars), MongoDB connection/index setup, logging
                setup, security.py (auth dependencies: get_current_user,
                require_role)
  schemas/    — Pydantic request/response models
  services/   — core business logic
    scan_service.py     — meal window detection, one-scan-per-day lock,
                           grace allowance check, balance deduction, reversal
    qr_service.py        — permanent, reprintable QR code generation
    billing_service.py   — UPI QR (upi://pay URI) + PDF bill generation
    auth_service.py       — password hashing, session create/validate/delete,
                            initial-admin bootstrap
  routers/    — HTTP endpoints (auth, users, members, scan, topups, menu,
                menu_categories, expenses, refunds, settings)
  utils/
    meal_window.py       — resolves current meal type from DB-backed settings,
                            handles the Saturday-brunch-only rule
    object_id.py          — shared "parse this string as a Mongo id or 400" helper
static/
  scanner.html — counter-facing scanner page (plain JS, no framework), with
                 its own lightweight login screen (§ auth above)
  admin/       — admin dashboard: login, member CRUD, top-ups/billing, scan
                 log & reversal, menu planning (interactive month calendar),
                 expenses, refunds, settings, users — one plain HTML page
                 per area, sharing css/admin.css and js/api.js + js/nav.js
                 (no build step, no framework)
tests/
  test_meal_window.py  — meal/window resolution, pure-function unit tests
  test_scan_service.py — the accept/reject/reversal decision tree, against
                          in-memory fake collections (tests/fakes.py) — no
                          MongoDB needed to run these
docs/
  PRD.md         — full product requirements (read this before building features)
  USER_GUIDE.md  — day-to-day usage doc for the admin/counter operator
nginx/
  nginx.conf         — gzip, security headers, rate-limit zone definitions
  proxy_params.conf  — shared reverse-proxy headers/timeouts
  conf.d/canteen.conf — the actual server block + rate limits, TLS notes
Dockerfile            — multi-stage build for the app image (see "Production
                         deployment" below)
docker-compose.yml    — the three-container stack: nginx, app, mongo
gunicorn_conf.py      — production ASGI process config (workers, timeouts)
Makefile              — `make up` / `make down` / `make logs` / etc.
scripts/
  smoke_test.py       — end-to-end check against a *running* stack, used
                        locally and by ci.yml (see "CI/CD" below)
.github/
  workflows/ci.yml             — lint, test, docker build+scan+smoke test
  workflows/docker-publish.yml — builds + publishes the image to GHCR
  dependabot.yml               — weekly dependency/base-image/action updates
```

### Running locally

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# MongoDB must be running locally (or point MONGO_URI at another instance)
cp .env.example .env

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The very first startup bootstraps one admin account from
`INITIAL_ADMIN_USERNAME`/`INITIAL_ADMIN_PASSWORD` in `.env` (a random password
is generated and logged if left blank) — sign in with that, then add every
other account from the dashboard's **Users** page. Then open **Settings** and
set the canteen's timezone, unit prices, and UPI details — those live in the
database, not `.env` (see "Key design decisions" below).

Then, on the counter phone (same local network), open:
`http://<host-device-ip-or-dns-name>:8000/static/scanner.html`

And for the admin, on any device on the local network:
`http://<host-device-ip-or-dns-name>:8000/static/admin/index.html`

Interactive API docs: `http://<host>:8000/docs`

### Running tests

```bash
pip install -r requirements-dev.txt
pytest
```

Tests run entirely against in-memory fakes (`tests/fakes.py`) — no MongoDB
required. Coverage focuses on `app/services/scan_service.py` and
`app/utils/meal_window.py`, since the PRD calls the scan accept/reject flow
"the highest-frequency, highest-stakes part of the system." See
[`docs/TESTING.md`](docs/TESTING.md) for what every test actually verifies,
in plain English — the same summary is posted to every CI run's job summary
automatically.

### Logging

Every scan decision, top-up, refund, member change, and settings update is
logged to both the console and a rotating file at `<LOGS_DIR>/app.log`
(default `logs/app.log`, 5MB × 5 files). Any unhandled exception is caught,
logged with a full traceback, and turned into a clean generic error for the
client — this is meant to be the admin's primary debugging tool when
something goes wrong and the developer isn't the one looking at it (see
`docs/PRD.md` §7).

### Production deployment (Docker)

A three-container stack — **nginx** (edge/reverse proxy) → **app** (this
FastAPI service, run under gunicorn) → **mongo** — wired together by
`docker-compose.yml`. One command brings the whole thing up:

```bash
make up          # copies .env.example -> .env on first run, then builds + starts everything
```

Before deploying for real, open `.env` and set a real `MONGO_ROOT_PASSWORD`
(`openssl rand -base64 24` is a good way to generate one) and `HTTP_PORT` if
80 is already taken on the host. Everything else has a sane default. Once
it's up, open the Settings page in the admin dashboard and set the
canteen's timezone (e.g. `Asia/Kolkata`) and UPI details — left at the
default `UTC` timezone, meal windows will be checked against UTC time
instead of the canteen's own clock.

```bash
make logs         # follow logs from all three containers
make ps           # container + healthcheck status
make down         # stop and remove containers (volumes/data are kept)
```

Then, from any device on the local network:
- Scanner: `http://<host>:<HTTP_PORT>/static/scanner.html`
- Admin dashboard: `http://<host>:<HTTP_PORT>/static/admin/index.html`

#### Network topology

```
                 ┌──────────┐
   host:80  ───▶ │  nginx   │
                 └────┬─────┘
                      │ edge network
                 ┌────┴─────┐
                 │   app    │
                 └────┬─────┘
                      │ internal network
                 ┌────┴─────┐
                 │  mongo   │
                 └──────────┘
```

Two separate bridge networks, not one flat one:
- **`edge`** — nginx ↔ app only. `app` has no `ports:` entry, so it's
  reachable only through nginx, never directly from the host.
- **`internal`** — app ↔ mongo only, declared `internal: true`. Docker gives
  this network no outbound route at all; nginx never joins it. Even if the
  app container were compromised, this is the standard "database only
  reachable from the one service that needs it" isolation, not just a
  host-firewall rule that could be misconfigured.

Only nginx publishes a port to the host (`${HTTP_PORT:-80}`).

#### Images and why

- **App image:** multi-stage build on `python:3.12-slim-bookworm` — a
  builder stage with `build-essential` (for any Pillow/reportlab
  dependency that doesn't ship a prebuilt wheel for the host architecture)
  produces a venv that's copied, alone, into a compiler-free final stage.
  Runs as a non-root user, ships a stdlib-only `HEALTHCHECK` (no curl/wget
  added just for that). Alpine would be smaller but risks slow/broken
  builds for Pillow's native dependencies on musl libc — `slim` is the
  better size/reliability trade-off for this stack.
- **nginx:** `nginx:1.27-alpine` — no compiled dependencies of its own, so
  alpine's size wins outright here.
- **mongo:** the official `mongo:7` image, unmodified.

#### What's in nginx

`nginx/nginx.conf` + `nginx/conf.d/canteen.conf`: gzip, security headers
(`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`), and two
separate rate-limit zones — a generous one for the admin dashboard, and a
tighter one specifically on `/scan`, since that endpoint is machine-driven
(one call per QR read) and a burst there is more likely a stuck retry than
a real user. `nginx/conf.d/canteen.conf` documents how to add TLS (mount a
cert/key, add a `listen 443 ssl` server block) when this needs to leave a
fully trusted LAN.

#### Volumes (survive `make down`, removed only by `docker compose down -v`)

| Volume | What |
|---|---|
| `mongo_data` | The database itself |
| `bills_data` | Generated PDF bills (`generated_bills/`) |
| `qr_data` | Generated QR/UPI images (`generated_qr/`) |
| `app_logs` | `logs/app.log` — the same rotating log described above, now persisted across container restarts/rebuilds |

#### Updating

```bash
git pull
docker compose up -d --build   # rebuilds only the app image; mongo/nginx are untouched
```

Each service has a `HEALTHCHECK`, and `depends_on: condition: service_healthy`
means app won't start serving until mongo is actually ready, and nginx won't
start routing until the app is — no manual "wait and retry" step needed on a
fresh `make up`.

#### Still not covered here

Docker isolates the network path; the app itself now also requires a login
(see "Key design decisions" below) for every route except the health check
and the public branding endpoint the login page needs before a session
exists. Still don't put this stack on the open internet without adding TLS
(see `nginx/conf.d/canteen.conf`) first — auth alone isn't a substitute for
encrypting credentials in transit.

### CI/CD

Two workflows under `.github/workflows/`:

- **`ci.yml`** — runs on every push and pull request. Three parallel jobs:
  `lint` (black + ruff), `test` (pytest with coverage), and `docker` (builds
  the production image, scans it with [Trivy](https://github.com/aquasecurity/trivy)
  and fails the build on any CRITICAL/HIGH vulnerability with a fix
  available, then brings up the full nginx+app+mongo stack with
  `docker compose up --wait` and runs `scripts/smoke_test.py` through nginx
  — the same member → credit → scan flow described above, now run on every
  change instead of by hand).
- **`docker-publish.yml`** — on a push to `main` or a `v*.*.*` tag: builds
  for `linux/amd64` + `linux/arm64`, runs the same Trivy gate, and publishes
  to `ghcr.io/aadeshgurav/canteen-coupon-system` tagged by branch, semver
  (on a tag), short commit SHA, and `latest` (default branch only).

**Dependabot** (`.github/dependabot.yml`) opens weekly PRs for Python
dependencies, the Docker base images (`Dockerfile` + `docker-compose.yml`'s
`mongo`/`nginx` tags), and the GitHub Actions versions pinned in these
workflows — so a CVE fix doesn't quietly go stale the way the
`python-multipart`/`fastapi` pins did before this pipeline existed to catch it
(see the git history on `requirements.txt` for what that scan actually found).

To pull a published image directly instead of building locally, point
`docker-compose.yml`'s `app` service at `image: ghcr.io/aadeshgurav/canteen-coupon-system:latest`
instead of `build: .` (requires `docker login ghcr.io` if the package is
private, which it is by default alongside this repo).

### Key design decisions

- **All timestamps are timezone-aware UTC, never naive.** `app/core/database.py`
  sets `tz_aware=True` on the Motor client and every "now" in application code
  is `datetime.now(timezone.utc)`, never `datetime.utcnow()`. This isn't just
  style — a naive ISO timestamp with no UTC offset is parsed by a browser's
  `Date` constructor as *local* time, which was silently misdisplaying every
  scan/top-up timestamp in the admin dashboard by the admin's own UTC offset.
- **Meal windows are local time, not UTC.** `local_timezone` (an IANA name
  like `Asia/Kolkata`, default `UTC`) — set on the Settings page, stored in
  the database, not an env var — tells the server what "07:00" in a meal
  window actually means. Internally everything runs on UTC (`to_local()` in
  `app/utils/meal_window.py` converts only where local wall-clock time
  actually matters — resolving the current meal and the Saturday-brunch-only
  day of week); stored timestamps stay UTC.
- **Timezone and UPI details are admin settings, not env config.**
  `local_timezone`, `upi_id`, and `upi_payee_name` live in the same
  DB-backed settings document as grace allowance and meal windows —
  editable from the Settings page with no restart, same as everything else
  an admin might reasonably need to change (CLAUDE.md §7).
- **Meal windows are configurable, not hardcoded.** Breakfast/lunch/brunch start
  and end times live in the `settings` document in MongoDB
  (`app/core/database.py::get_global_settings`) and are editable via
  `PATCH /settings` — never edit source to change serving hours.
- **One scan per meal per day**, enforced by checking for an existing
  non-reversed accepted scan for that member/meal within the calendar day —
  not a fixed cooldown timer, so it naturally resets each day with no
  scheduled job needed, and not the meal's configured clock window, so a
  counter operator's `meal_type_override` (for edge cases) can't accidentally
  defeat the lock by falling outside that window's normal hours.
- **Grace allowance**: global default in `settings`, with an optional per-member
  override (`grace_allowance_override`) for exceptions.
- **QR codes never change.** `qr_code_id` is generated once at member creation
  and reused for every reprint, so a lost card can never create a duplicate
  member entity.
- **A member with any history can't be hard-deleted.** `DELETE /members/{id}`
  checks for scans/top-ups/refunds first and refuses (409) if any exist —
  deleting would orphan those records' `member_id` references. Deactivate via
  `PATCH {"status": "inactive"}` instead; that's what the dashboard exposes.
- **Balances never auto-reset.** No month-end, term-end, or scheduled reset
  logic exists anywhere in this codebase, intentionally. A balance only moves
  because of a scan, a reversal, a top-up, or a refund.
- **Grace-allowance scans are flagged.** If a scan only succeeded because of
  the grace allowance (balance went negative), the scan record stores
  `via_grace: true` and the scanner page shows a "GRACE" badge, so it's
  obvious at a glance who's eating on credit.
- **Menu categories are admin-managed, not hardcoded.** Categories like Jain,
  Normal, or Staff are CRUD records in `menu_categories`, not a fixed enum —
  the admin can add/rename/remove them as the canteen's offering changes.
- **Refunds don't move money.** `POST /refunds` deducts the specified units
  from a member's balance and logs the amount/reason — the actual payout
  (cash, transfer, etc.) is handled by the admin outside the app.
- **UPI payments**: plain `upi://pay` QR, no payment gateway. Cash top-ups are
  marked `confirmed` immediately; UPI top-ups start `pending` until the admin
  manually confirms receipt via `POST /topups/{id}/confirm-payment`. The QR
  itself is served from `GET /topups/{id}/upi-qr` and shown in a dashboard
  pop-up at the moment of payment — never printed on the bill PDF.
- **Auth: stdlib hashing + opaque server-side sessions, not JWT.** Passwords
  are hashed with `hashlib.pbkdf2_hmac` (260k iterations); sessions are
  random tokens (`secrets.token_urlsafe`) stored in a `sessions` collection
  with a MongoDB TTL index for auto-expiry (`SESSION_TTL_HOURS`) — no new
  dependency (no `passlib`/`bcrypt`/`PyJWT`) for what's a small, well-scoped
  amount of logic at this system's scale (CLAUDE.md §10), and revoking a
  session is just deleting a row instead of needing a blocklist.
- **Three roles**: `admin` (everything), `counter` (scan + top-ups/billing),
  `scanner` (scan only) — enforced server-side via `require_role(...)`
  dependencies on every router, and mirrored in the dashboard's nav/UI so a
  role never sees a button the API would reject anyway.
- **Top-up/refund amounts are always server-computed**, from `unit_prices` in
  `settings` × the units requested — never accepted as client input — so a
  tampered request body can't record an arbitrary amount.
- **The initial admin password, if auto-generated, is printed to stdout, not
  logged.** `logger.warning` would persist it into the rotating
  `logs/app.log` file indefinitely; a one-time `print()` reaches the same
  console without ever touching a log a later operator or aggregator might
  read (CLAUDE.md §7: "credentials... never logged").

### Not yet built (flagged for a later pass — see `docs/PRD.md` §9)

- Elasticsearch-backed searchable action log (scans/top-ups currently live only
  in MongoDB; planned once the core flow is validated in the pilot).
- WhatsApp bill delivery (explicitly deferred).
- Automated UPI payment confirmation via a payment gateway webhook.
- Multi-campus support.

---

## 4. Contributing to this repo

- **Keep docs in sync.** Update this README and `docs/USER_GUIDE.md` whenever a
  change affects setup, configuration, or usage — in the same change, not as a
  follow-up.
- **Commit in small, focused increments** with clear messages describing what
  changed and why.

See `docs/PRD.md` §10 for the full engineering standards this repo follows.
