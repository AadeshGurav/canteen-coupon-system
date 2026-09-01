# Canteen Coupon System

A unit-based meal coupon system for a school canteen — replaces paper tracking of
student and staff meal entitlements with QR-code scanning, configurable balances,
and admin-managed billing. Built for a single campus, single canteen pilot.

Full requirements: [`docs/PRD.md`](docs/PRD.md)
For canteen staff/admin day-to-day usage: [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)

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
  by cash or by scanning a generated UPI QR code — and get a PDF bill automatically.
- Print or reprint a member's QR code. Reprinting never issues a new code, so a
  lost card can't create a duplicate record.
- Set a **grace allowance** — how many meals, if any, a member can take on credit
  before being turned away — globally or per member.
- Plan the weekly/monthly menu (admin-only planning tool, not shown to students
  or staff).
- Track expenses (groceries, tables, etc.) against revenue to see a simple
  profit picture.
- Undo a scan by mistake within a configurable time window (default 10 minutes).
- Adjust meal serving times, grace allowance, and the reversal window from
  settings — none of this is hardcoded, so it can be tuned without a code change.

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
| Top-ups & billing | Cash or UPI QR, automatic PDF bill generation, manual UPI payment confirmation |
| Reversal | Undo a mistaken scan within a configurable window, restores the unit |
| Grace tracking | Any meal given on the grace allowance is flagged (`via_grace`) on the scan record and shown as a badge on the scanner screen |
| Menu planning | Admin-only calendar/log of what's served, per date, per meal, tagged with admin-managed menu categories (e.g. Jain, Normal, Staff) |
| Refunds | Admin records a refund (units + amount + reason) when a member leaves; deducts the balance immediately, payout itself is handled outside the app |
| Expenses | Log spend, see revenue vs. expense summary |
| Settings | Meal windows, grace allowance, reversal window — all DB-backed, all editable at runtime |
| Admin dashboard | Browser UI (`/static/admin/`) covering every admin action above — member CRUD, top-ups/billing, scan log & reversal, menu planning, expenses, refunds, settings — no more driving the API by hand through `/docs` |

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
  core/       — config (env vars), MongoDB connection/index setup, logging setup
  schemas/    — Pydantic request/response models
  services/   — core business logic
    scan_service.py     — meal window detection, one-scan-per-day lock,
                           grace allowance check, balance deduction, reversal
    qr_service.py        — permanent, reprintable QR code generation
    billing_service.py   — UPI QR (upi://pay URI) + PDF bill generation
  routers/    — HTTP endpoints (members, scan, topups, menu, menu_categories, expenses, refunds, settings)
  utils/
    meal_window.py       — resolves current meal type from DB-backed settings,
                            handles the Saturday-brunch-only rule
    object_id.py          — shared "parse this string as a Mongo id or 400" helper
static/
  scanner.html — counter-facing scanner page (plain JS, no framework)
  admin/       — admin dashboard: member CRUD, top-ups/billing, scan log &
                 reversal, menu planning, expenses, refunds, settings — one
                 plain HTML page per area, sharing css/admin.css and
                 js/api.js + js/nav.js (no build step, no framework)
tests/
  test_meal_window.py  — meal/window resolution, pure-function unit tests
  test_scan_service.py — the accept/reject/reversal decision tree, against
                          in-memory fake collections (tests/fakes.py) — no
                          MongoDB needed to run these
docs/
  PRD.md         — full product requirements (read this before building features)
  USER_GUIDE.md  — day-to-day usage doc for the admin/counter operator
```

### Running locally

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# MongoDB must be running locally (or point MONGO_URI at another instance)
cp .env.example .env  # then fill in UPI_ID etc.

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

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
"the highest-frequency, highest-stakes part of the system."

### Logging

Every scan decision, top-up, refund, member change, and settings update is
logged to both the console and a rotating file at `<LOGS_DIR>/app.log`
(default `logs/app.log`, 5MB × 5 files). Any unhandled exception is caught,
logged with a full traceback, and turned into a clean generic error for the
client — this is meant to be the admin's primary debugging tool when
something goes wrong and the developer isn't the one looking at it (see
`docs/PRD.md` §7).

### Key design decisions

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
  manually confirms receipt via `POST /topups/{id}/confirm-payment`.

### Not yet built (flagged for a later pass — see `docs/PRD.md` §9)

- Auth for the admin endpoints (currently open — fine for a LAN-only pilot, but
  must be locked down before any handoff or exposure beyond the local network).
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
