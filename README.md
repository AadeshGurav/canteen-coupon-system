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
| Member management | Full CRUD for student & staff entities, bulk-friendly for paper-to-digital migration |
| QR codes | Generate on creation, print, reprint (same code, never duplicated) |
| Scanning | Single shared scanner page (phone browser), instant accept/reject, one scan per meal window |
| Balances | Separate lunch / breakfast / brunch unit counts, grace allowance (global + per-member override) |
| Top-ups & billing | Cash or UPI QR, automatic PDF bill generation, manual UPI payment confirmation |
| Reversal | Undo a mistaken scan within a configurable window, restores the unit |
| Menu planning | Admin-only calendar/log of what's served, per date, per meal, per audience (student/staff/both) |
| Expenses | Log spend, see revenue vs. expense summary |
| Settings | Meal windows, grace allowance, reversal window — all DB-backed, all editable at runtime |

---

## 3. Technical overview

**Stack:** Python (FastAPI, async) · MongoDB (via Motor) · plain HTML/JS for the
scanner page (no frontend framework) · ReportLab for PDF bills · `qrcode` for QR
generation.

**Why this stack:** small single-canteen pilot, not a high-scale system — FastAPI
gives free request validation and async support without Django-level scaffolding;
MongoDB suits the somewhat variable shape of member records; the scanner page is
deliberately framework-free since it needs to sit open on a phone browser for
hours without memory bloat.

### Project layout

```
app/
  core/       — config (env vars) and MongoDB connection/index setup
  schemas/    — Pydantic request/response models
  services/   — core business logic
    scan_service.py     — meal window detection, one-scan-per-window lock,
                           grace allowance check, balance deduction, reversal
    qr_service.py        — permanent, reprintable QR code generation
    billing_service.py   — UPI QR (upi://pay URI) + PDF bill generation
  routers/    — HTTP endpoints (members, scan, topups, menu, expenses, settings)
  utils/
    meal_window.py       — resolves current meal type from DB-backed settings,
                            handles the Saturday-brunch-only rule
static/
  scanner.html — counter-facing scanner page
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

Interactive API docs: `http://<host>:8000/docs`

### Key design decisions

- **Meal windows are configurable, not hardcoded.** Breakfast/lunch/brunch start
  and end times live in the `settings` document in MongoDB
  (`app/core/database.py::get_global_settings`) and are editable via
  `PATCH /settings` — never edit source to change serving hours.
- **One scan per meal window**, enforced by checking for an existing non-reversed
  accepted scan within the current window's time bounds, not a fixed cooldown
  timer — so it naturally resets each day with no scheduled job needed.
- **Grace allowance**: global default in `settings`, with an optional per-member
  override (`grace_allowance_override`) for exceptions.
- **QR codes never change.** `qr_code_id` is generated once at member creation
  and reused for every reprint, so a lost card can never create a duplicate
  member entity.
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
