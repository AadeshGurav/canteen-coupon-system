# PRD — Canteen Unit-Based Coupon System

**Status:** Active build — **v2 architecture pivot approved (native Flutter app, see §13–§14), supersedes the original browser/FastAPI/MongoDB delivery model described in earlier sections of this document.** Where a section conflicts with §13–§14, the later section wins; conflicts are marked inline with strikethrough + a "Superseded" note rather than silently deleted, so the reasoning trail stays intact.
**Owner:** Aadesh (developer/architect) — building for a canteen contractor client
**Build window:** originally 15 days for the v1 pilot; v2 (native app) timeline TBD
**Audience for this doc:** Claude Code (or any engineer/agent) implementing this system. Read this fully before writing code — **§13 and §14 specifically contain pinned dependency versions and structural decisions that should not be re-researched or re-decided at build time.**

---

## 1. Problem & Context

A canteen contractor runs meal service (breakfast, lunch, and Saturday brunch) for students and staff at one campus. Today this is paper-based: tracking who has paid, how many meals they're owed, and confirming meals at the counter is manual and error-prone.

We are replacing this with a small, self-hosted application that:
- Issues each person (student or staff) a printable QR/barcode.
- Lets a counter operator scan that code at meal time and get an instant accept/reject decision.
- Tracks meal entitlements as **units** (not currency) — a lunch unit, a breakfast unit, a brunch unit — topped up by parents (for students) or staff themselves.
- Gives the contractor (the **admin**) full control over people, balances, pricing, menu planning, and basic business tracking (expenses vs. revenue).

This is **not** a payment platform and **not** a multi-tenant SaaS product. It is a single-operator tool for one canteen, built lean, built once, and built to keep running with minimal maintenance afterward.

---

## 2. Goals

1. Replace paper tracking with a reliable digital system for meal entitlements.
2. Make the counter scan flow fast, unambiguous, and foolproof — this is the highest-traffic, highest-stakes part of the system.
3. Give the admin a frictionless way to onboard people, top up balances, generate bills, and correct mistakes.
4. Keep the system self-contained enough that the admin (who is technically capable, but not the developer) can operate and diagnose it without ongoing developer support.
5. Keep the build scoped to what's needed for one campus, one canteen — but don't paint the architecture into a corner if it needs to grow later (multiple campuses, WhatsApp delivery, automated UPI confirmation, etc. — see §9 Out of Scope).

## 3. Non-Goals

- No real money custody, wallets, or payment processing beyond generating a UPI payment QR code. The system tracks meal **units**, never currency balances as a stored-value wallet.
- No multi-campus / multi-tenant support in this build (design should not actively block it later, but do not build it now).
- No student/staff-facing menu view. The menu planner is admin-only.
- ~~No mobile app. Everything is a browser page served on the local network.~~ **Superseded — see §13.** The system is being rebuilt as a native Flutter app for Android first. This is a deliberate architecture pivot, not scope creep: the browser-only approach still stands as the reasoning for *why* the system must stay local-network-first and self-hosted (§7) — only the delivery mechanism (native app vs. browser) and backend stack (embedded Dart server vs. FastAPI/MongoDB) are changing. §13 is the authoritative record of that decision and what replaces it.
- No automated UPI payment webhook/confirmation in this build — confirmation is manual by the admin.
- No WhatsApp integration in this build (deferred — see §9).

---

## 4. Users & Roles

Three login roles exist, each with a real account (username + password) and
a server-side session — this supersedes the original "no login" decision for
the admin dashboard and the scanner page (see §9 and the "Superseded
decisions" note below):

| Role | Who | What they can do |
|---|---|---|
| **Admin** | The contractor (client) | Everything: member CRUD, top-ups & billing, QR generation/reprint, menu planning, expense tracking, settings, scan reversal, and managing user accounts (add/edit-role/reset-password/deactivate/delete other users). |
| **Counter** | Whoever staffs the billing/top-up counter | Scan, plus top-ups & billing. No access to member CRUD, menu planning, expenses, refunds, settings, or user management. |
| **Scanner** | Whoever staffs the meal-serving scan point | Scan only. Nothing else. |
| **Member entity — student** | A student, represented as a record, not a login-based "account" | Has a QR code. Gets scanned at the counter. Does not use the app directly and has no login of its own. |
| **Member entity — staff** | A staff member, same entity model as student with a different `type` | Same as student, different pricing. |

An initial admin account is bootstrapped automatically on first startup from
`INITIAL_ADMIN_USERNAME`/`INITIAL_ADMIN_PASSWORD` (env config, since this is
the one credential that has to exist before there's anyone to set it via the
UI) — from then on, all account management happens through the admin-only
**Users** page, never `.env`.

**Important modeling decision:** students and staff are **one data type**, `member_entity`, distinguished by a `type` field — not two separate collections/models. This avoids duplicate CRUD logic and duplicate schemas for what is functionally the same entity with different pricing and a couple of type-specific fields (class/roll number vs. staff ID).

---

## 5. Core Concepts

- **Unit, not currency.** Every member entity has three balances: `lunch`, `breakfast`, `brunch`. A scan deducts exactly one unit of the relevant type. Top-ups add units. Nothing here is a monetary wallet.
- **No automatic resets, ever.** Balances are never reset at month-end, term-end, or on any schedule. A balance only changes because of a scan, a scan reversal, a top-up, or a refund. If a member is out of units, they're out — the only thing that changes that is a top-up (or the grace allowance, see below). This is intentional: units purchased don't expire or get wiped by the calendar.
- **Saturday is different.** On Saturdays there is no separate breakfast/lunch — only a single **brunch** meal. Brunch is a third, independent unit type, only consumable on Saturdays.
- **Meal windows are configurable, not hardcoded.** Breakfast, lunch, and brunch each have a start/end time. These live in a `settings` document in the database and are editable by the admin — never hardcoded constants in source. Start/end times are the canteen's own local wall-clock hours (e.g. "07:00" means 7am at the canteen) — the server converts its internal UTC clock to the canteen's timezone (also admin-editable, in that same settings document) before checking these, not the other way around.
- **One scan per meal window.** A member cannot be scanned twice for the same meal on the same day. This is enforced by checking for an existing accepted, non-reversed scan for that member/meal within the calendar day — not by a separate cooldown timer, so it naturally resets each day with no scheduled job required — and not by the meal's configured clock window, so a counter operator's manual meal-type override (for edge cases) can't fall outside those hours and silently defeat the lock.
- **Grace allowance.** A member may be allowed to go negative on a balance by a configurable number of units before a hard stop, so a kid isn't turned away mid-week while a parent sorts out payment. This is a **global default in settings**, with an optional **per-member override** for exceptions the admin sets individually. Any scan that was only possible because of the grace allowance (i.e., it pushed the balance negative) must be clearly flagged — both in the stored scan record (`via_grace`) and as a visible badge/indicator wherever scans are shown, so the admin can immediately spot who's eating on credit.
- **Scan reversal.** If a scan was a mistake (wrong code, operator error, member changes their mind), it can be undone within a configurable window (default 10 minutes) after the scan. Reversing restores the unit and marks the scan as reversed — it does not delete the scan record (audit trail must be preserved).
- **QR codes are permanent per member.** A member's QR/barcode value is generated once at creation and never changes. Reprinting (lost/damaged card) re-renders the same code — it never issues a new one. This prevents duplicate member entities from lost-card situations.

---

## 6. Functional Requirements

### 6.1 Member Entity Management (Admin)
- Create, read, update, delete member entities.
- Fields: `type` (student/staff), `name`, and type-specific fields (`class`/`roll_number` for students, `staff_id` for staff).
- Each entity has a `status` (active/inactive) — inactive entities should fail scans with a clear reason, not a generic error.
- Admin can perform **credit operations**: add lunch/breakfast/brunch units to a member's balance (this is the top-up action, see §6.3).
- Admin can migrate existing paper-based records into the system (bulk import is in scope for the pilot — see §9 for what's deferred vs. what's needed at launch).
- Admin can set a per-member grace allowance override.

### 6.2 QR/Barcode Issuance
- On member creation, generate a unique, permanent code identifier and render it as a QR image.
- Admin can print codes (single or batch).
- Admin can **reprint** a lost/damaged code — this must reuse the existing code identifier, never generate a new one.

### 6.3 Top-ups & Billing
- Admin or counter operator selects a member, enters units to add per meal type, and a payment method: `cash` or `upi`. **The amount is never typed in** — it's calculated automatically from the per-meal-type unit prices set in Settings (§6.8), and the submit action is disabled while every unit is still zero (a zero-unit top-up is meaningless and rejected server-side too).
- On submit: balances are credited immediately, and a **PDF bill** is generated showing units purchased and the member's new balances.
- If payment method is `upi`: generate a UPI payment QR (standard `upi://pay` URI scheme — no payment gateway integration) and show it in a pop-up at the moment of payment, so the payer can scan it right there — it does **not** appear on the bill PDF itself. Payment status starts `pending`.
- If payment method is `cash`: payment status is `confirmed` immediately; no UPI QR needed.
- Admin can manually mark a pending UPI top-up as `confirmed` once they've verified receipt in their own UPI app. There is no automated payment webhook in this build.

### 6.4 Scanning (Counter Flow)
- One shared scanner page, browser-based, accessed via a local-network DNS name from a mobile phone camera. Requires signing in with an account that has `scanner`, `counter`, or `admin` role (superseding the original "no login" decision — see §9) — the session is remembered on that device/browser until sign-out or expiry, so this is still effectively a fast, shared kiosk in practice, just no longer an open endpoint.
- On scan: resolve the member by code, determine current meal type from the time of day and day of week (using the configurable meal windows in settings), and apply, in order:
  1. Unknown code → reject, clear message.
  2. Inactive member → reject, clear message.
  3. No meal currently in a serving window → reject, clear message.
  4. Already scanned for this meal window → reject, clear message.
  5. Balance check (including grace allowance) → reject if exhausted, clear message.
  6. Otherwise → accept, deduct one unit, log the scan, show member name + meal + remaining balance.
- Every scan (accepted or rejected) should be clear at a glance to the counter operator — big, unambiguous accept/reject state, no reading required beyond a glance. This is the highest-frequency interaction in the whole system and must be fast and foolproof.
- Admin can reverse a specific accepted scan within the configured reversal window.

### 6.5 Menu Planning (Admin-only)
- Admin manages **menu categories** as a first-class, CRUD-editable list (e.g. "Jain", "Normal", "Staff") — categories are not a fixed enum in code. Admin can add, rename, or remove categories as the canteen's offering changes.
- Admin can log what's being served, per date, per meal type, tagged with one or more menu categories (a dish might apply to just "Jain", or to both "Normal" and "Staff").
- The primary planning surface is an interactive month calendar (prev/next navigation, current day highlighted, each day's logged meals shown as tags at a glance) — clicking any day opens a dialog pre-filled with that date to log a new entry or review/delete what's already logged there.
- This is a planning/record tool only — no student- or staff-facing view.

### 6.5.1 Ingredients, Recipes & Purchase Schedule (Admin manages; admin + counter use)
- Admin maintains an **ingredients** master list (name + the unit it's bought in) and **recipes** — a dish name (matched case-insensitively against a menu entry's item names) linked to the ingredients it needs, each with a free-text quantity note (e.g. "2kg per 50 servings") rather than a precise per-serving quantity model, since this system doesn't track expected headcount per entry.
- The admin generates a **purchase schedule** for a date range: for every planned menu entry in that range, whichever of its items has a matching recipe contributes one schedule item per ingredient, per date. Generation is idempotent — re-running it over an overlapping range never duplicates an item or resets one that's already been checked off.
- Admin **and counter** can view the schedule, check items off as purchased (recording who and when), and add ad-hoc manual items not tied to any recipe. Only admin can generate the schedule or delete an item — this mirrors counter's existing scan+billing-only permission boundary (§4).

### 6.5.2 Notifications (Persistent, in-app; all roles)
- A notification center (bell icon in the dashboard nav) surfaces two kinds of reminder, computed automatically and persisted so they survive a refresh or logout:
  - **Meal prep reminders** — fires a configurable number of minutes (`prep_lead_minutes`, default 60, admin-editable in Settings) before a meal window starts, but only if something is actually planned on the calendar for that meal/day.
  - **Purchase-due reminders** — fires when any purchase-schedule item for a configurable number of days ahead (`purchase_lead_days`, default 1) is still unpurchased.
- Each notification is visible to every role that can act on it (admin and counter) and can be dismissed independently per user — dismissing doesn't hide it for anyone else still working from the same reminder.
- No new infrastructure: reminders are computed lazily on each `GET /notifications` poll (the dashboard polls automatically, no page needs to be manually refreshed) rather than a scheduled background job, and delivery is in-app only — no email/SMS/push.

### 6.6 Expense & Revenue Tracking (Admin)
- Admin can log expenses (category, description, amount, date) — groceries, tables, other overhead.
- System should provide a simple revenue-vs-expense summary (revenue = confirmed top-ups in a date range, expenses = logged expenses in that range, profit = the difference).

### 6.7 Refunds (Admin)
- If a member leaves the school or otherwise stops using the canteen, the admin can process a refund: specify how many lunch/breakfast/brunch units are being refunded. Unit inputs pre-fill from that member's actual current balance (capped there, so a refund can't exceed what they have) and the refund amount is calculated automatically from the same unit prices used for top-ups — never typed in.
- The **actual money movement is handled by the admin outside the app** (cash back, bank transfer, etc.) — the system's job is to keep the unit ledger accurate and to keep a record of what was refunded, when, and why.
- Refunding deducts the specified units from the member's balance immediately. A refund cannot request more units than the member currently has.
- This does not automatically deactivate the member — deactivation (if the member is leaving for good) is a separate action via the member's `status` field.

### 6.8 Settings (Admin)
All of the following must be stored in the database and editable at runtime — **none of this is a hardcoded constant in source, and none of it lives in environment config either**:
- Grace allowance: enabled/disabled, and default unit count.
- Meal windows: start/end time for breakfast, lunch, and brunch (brunch applies Saturday only).
- The canteen's own local timezone (IANA name) — what meal window start/end times above are actually measured in. Chosen from a dropdown listing every IANA zone the server's Python runtime knows (`zoneinfo.available_timezones()`), not freehand text a typo could silently break meal-window matching against.
- Unit prices — price per lunch/breakfast/brunch unit — used to compute top-up and refund amounts automatically (§6.3, §6.7) instead of an admin typing an amount by hand.
- UPI ID and payee name used to generate a top-up's payment QR (§6.3).
- Scan reversal window (minutes).
- Application name (branding) — shown in the dashboard's nav bar and browser tab title. Purely cosmetic, but stored the same way as everything else here: DB-backed, editable at runtime, no code change or restart needed.
- Prep reminder lead time (`prep_lead_minutes`) and purchase reminder lead time (`purchase_lead_days`) — see §6.5.2.

---

## 7. Non-Functional Requirements

- **Frictionless & foolproof.** This term was used repeatedly in planning specifically about the admin/payment side — every action there should have a clear, unambiguous outcome and be hard to get wrong. Favor explicit confirmations and clear state over cleverness.
- **Mobile-first, lightweight scanner page.** It will sit open on a phone browser for hours across a meal period. No heavy frontend framework, no memory leaks, no unnecessary background work. Plain JS/HTML preferred over a full SPA framework for this page specifically.
- **Local-network first.** Scanning and the admin dashboard must work entirely on the local network with no internet dependency. Internet access is only required for the UPI QR payment step (and that's still just a static QR, not a live network call) — not for anything during normal day-to-day operation. ~~**TLS is required, not optional**, for the scanner specifically: browsers only allow camera access in a secure context (HTTPS or `localhost`), and that rule holds even on a fully private, offline LAN — see `make tls-setup` in the README and `docs/USER_GUIDE.md` §2.3.~~ **Superseded — see §13.6.** Under the native-app architecture, scanning uses the device's native camera API, not a browser, so the secure-context requirement that forced mandatory TLS no longer applies to scanning. TLS/HTTPS is downgraded from a hard requirement to a recommended-but-optional protection for the *desktop-browser admin* surface only (protecting login credentials and session cookies over LAN, not enabling a feature) — see §13.6 for the certificate approach.
- **Operable without the developer.** The admin is technically capable and can debug his own issues post-handoff, but only if the system surfaces **clear, specific errors** (not generic 500s or silent failures) and maintains a **detailed, searchable action log** of scans, top-ups, and admin actions. Design logging as a first-class feature, not an afterthought — this is intended to double as the admin's own debugging tool.
- **Self-hosted, low-maintenance.** No managed cloud dependencies required to run day-to-day. ~~Target host is a laptop (or possibly a phone) on the local network. If hosted off a phone hotspot, the host's IP (and on Android 11+, its whole subnet) isn't stable without rooting the phone — `make mdns-setup` (optional, see README) publishes a `<hostname>.local` address as a workaround, since it doesn't depend on the current IP at all.~~ **Superseded — see §13.** Under the native-app architecture, any device running the app can become the host outright — no separate laptop, no manual `.local` setup script. Service discovery (§13.5) replaces the old mDNS workaround with the same underlying idea (don't depend on a stable IP), but built into the app rather than a manual step in the README.
- **This is a one-time build, not a retainer.** Prioritize correctness and clarity of failure over speculative extensibility. Don't build for scale this project doesn't need yet.

---

## 8. Data Model (reference)

See `app/schemas/` and `app/core/database.py` in the codebase for the authoritative, current schema. Summary of collections:

- `member_entities` — student/staff records, balances, QR code identifier, grace override, status.
- `scans` — one record per scan attempt's outcome, reversal state, and whether it was via the grace allowance (`via_grace`).
- `topups` — one record per credit/billing transaction, payment method/status, bill + UPI QR paths.
- `menu_log` — admin's meal planning entries, tagged with one or more menu categories.
- `menu_categories` — admin-managed list of categories (e.g. Jain, Normal, Staff) used to tag menu entries.
- `refunds` — one record per refund: units deducted, amount, reason, who processed it. The payout itself happens outside the app.
- `expenses` — logged business expenses.
- `settings` — single global document: grace allowance config, meal windows, unit prices, timezone, UPI details, reversal window, app name.
- `users` — login accounts: username, hashed password, role (admin/counter/scanner), active status.
- `sessions` — opaque server-side session tokens (not JWT), one per login, auto-expiring via a MongoDB TTL index (`SESSION_TTL_HOURS`).
- `ingredients` — admin-managed master list: name + unit.
- `recipes` — dish name (matched case-insensitively against menu entries) + the ingredients/quantity notes it needs.
- `purchase_schedule_items` — one per (date, ingredient): quantity note, purchased state (who/when), and whether it was auto-generated from the menu calendar or added manually.
- `notifications` — persistent in-app reminders: type, title/message, which roles can see it, and which usernames have dismissed it.

If the code and this PRD ever disagree on a schema detail, the code is the source of truth for *what currently exists*, but any schema change should be reflected back into this PRD and the README (see §11).

---

## 9. Out of Scope for This Build (Explicitly Deferred)

- Automated UPI payment confirmation via a payment gateway (e.g., Razorpay/Cashfree webhook). Manual confirmation only, for now.
- WhatsApp delivery of bills/PDFs. To be discussed and added later.
- Searchable, verbose action logging via a dedicated search engine (e.g., Elasticsearch) alongside the primary database. The primary database logs remain the source of truth for now; this is a planned upgrade once the core flow is validated in the pilot.
- Multi-campus / multi-tenant support.
- Any student/staff-facing app, portal, or menu view.

**Superseded decision:** Authentication/authorization was originally deferred
here as "acceptable for a LAN-only pilot." It has since been built (§4, §6.4)
— stdlib password hashing (`pbkdf2_hmac`) and opaque server-side sessions, no
new dependency — because a LAN-only pilot still has multiple people with very
different levels of trust (the contractor vs. a scan-only counter hire)
sharing the same network, and role separation was worth having from day one
rather than retrofitting later.

---

## 10. Engineering Standards (apply to all work on this repo)

These are general engineering principles for this codebase, not specific to any prior project — apply them throughout.

- **Clarity over cleverness.** Simple, explicit, readable code beats compact or "smart" code. If a piece of logic is hard to explain in a sentence, reconsider the approach.
- **One obvious way to do a thing.** Avoid parallel, inconsistent patterns for the same kind of problem across the codebase.
- **Small, focused functions and files.** Functions should do one clear thing. Keep files reasonably small and split by domain/responsibility once a file starts covering more than one concern (this codebase currently organizes by `core/`, `schemas/`, `services/`, `routers/`, `utils/` — follow that pattern for new code).
- **Descriptive naming.** No `data`, `temp`, `info`, `util` as names. Prefer verb-noun function names (`process_scan`, `generate_bill_pdf`, `reverse_scan`).
- **Errors are never silent.** Surface clear, specific, human-readable errors — especially anything the admin might see. No swallowed exceptions, no bare generic failures where a specific one is knowable.
- **Comment intent, not mechanics.** Explain *why*, not a restatement of *what* the code already says.
- **Don't reinvent what the stack already provides.** Use FastAPI's built-in validation, MongoDB's native features, etc., before adding new dependencies or hand-rolled infrastructure.
- **Config lives in config, not in code.** Anything an admin might reasonably need to change (meal windows, grace allowance, reversal window, etc.) belongs in the `settings` collection or environment config — never as a hardcoded constant buried in application logic.
- **Fault isolation.** A failure in one feature (e.g., PDF generation) should not take down unrelated functionality (e.g., the scan endpoint). Isolate and degrade gracefully where practical.
- **Formatting/tooling:** 4-space indentation, double-quoted strings, imports sorted, unused imports/variables removed. Use `black`, `ruff`, and `flake8` (or the project's configured equivalents) to keep this consistent — fix issues rather than suppress them.

### 10.1 Documentation Discipline
**Update `README.md` and the user documentation (`docs/USER_GUIDE.md`) after every change that affects behavior, setup, configuration, or usage.** Documentation drifting out of sync with the code is treated as a bug in the change, not a follow-up task. If you touch a feature, touch its docs in the same change.

### 10.2 Commit Discipline
**Make small, focused commits.** Each commit should represent one coherent change (one feature, one fix, one refactor) with a clear message describing what changed and why. Avoid large, sweeping commits that bundle unrelated changes — they're hard to review, hard to revert, and hard to reason about later.

---

## 11. Definition of Done (per feature)

A feature is not done until:
1. It works end-to-end (backend + frontend where applicable).
2. Errors are handled explicitly and surfaced clearly.
3. Any new config is stored in `settings`/env, not hardcoded.
4. `README.md` and `docs/USER_GUIDE.md` are updated to reflect it.
5. The change is committed in small, reviewable increments with clear messages.

---

## 12. Timeline Context (for reference, not a hard spec)

Originally scoped as a 15-day build:
- Days 1–3: core member entity CRUD and data models.
- Days 4–7: scanning flow (confirm/reject, meal-window lock, grace allowance).
- Days 8–10: admin dashboard, top-ups, PDF billing, UPI QR.
- Days 11–12: menu log, expense/revenue tracking.
- Days 13–15: scan reversal, QR reprinting, logging improvements, pilot testing with real conditions.

This is context for prioritization, not a constraint that should force cut corners on correctness.

---

## 13. Native App Architecture (v2 — Flutter, Host/Client on LAN)

**Status:** Approved direction, supersedes §3's original "no mobile app" non-goal and the browser-only/FastAPI-MongoDB delivery model described elsewhere in this document. Everything in §5, §6, and §8 (business rules, functional requirements, data model shape) still holds — this section only changes *how it's delivered and hosted*, not what it does.

### 13.1 Why this change

The original design put a laptop (or a phone acting only as a hotspot) at the center of the network, running FastAPI + MongoDB, with every device — including the host machine itself — reaching it through a browser. In practice this meant:
- A dependency on a laptop being present and powered on, when the actual devices in daily use are phones.
- A browser-only scanner page that could only get camera access over a secure context (HTTPS), which required a manual, one-time `mkcert` + root-CA-install step per device (§7, now superseded).

Moving to a single Flutter app that can act as **either host or client on the same LAN, from the same APK**, removes the laptop dependency entirely and turns the scanner into a first-class native camera flow instead of a browser workaround.

### 13.2 Core model: one APK, two roles

- On first launch, the app asks the operator to choose **Host** or **Client**. This is a per-install/per-session choice, not a compiled variant — the same APK ships to every device.
- **Host mode:** the phone (or eventually a desktop build, §13.8) runs the full backend in-process — business logic, the embedded database, and an embedded HTTP server (§13.4) — and advertises itself on the LAN (§13.5) so other devices can find it.
- **Client mode:** the app discovers a host on the LAN and talks to it over HTTP/JSON, exactly like today's browser pages did against FastAPI — the UI code is written against a single data-access interface so host-mode (local calls) and client-mode (network calls) are interchangeable at that boundary (see §13.7's layering).
- If the host device goes offline mid-session, clients should show a clear, specific "host unreachable" state (per CLAUDE.md §8, no silent failure) rather than a generic network error, with a retry/re-discover action.

### 13.3 Tech stack decisions (researched, pinned, ready to build against)

Per CLAUDE.md §10 ("every dependency is a decision, pin deliberately"), each of these was checked against current maintenance status, not just familiarity — one of the original candidates (Isar, for the database) was rejected specifically because it failed that check. Exact versions below reflect what was current as of this research pass; run `flutter pub outdated` at build time and bump patch/minor versions deliberately if newer stable releases exist, per CLAUDE.md §10's "know why an upgrade is happening."

| Concern | Package(s) | Version (pin) | Why |
|---|---|---|---|
| Embedded HTTP server | `shelf`, `shelf_router`, `shelf_static` | `shelf: ^1.4.2`, `shelf_router: ^1.1.4`, `shelf_static: ^1.1.2` | Official `dart-lang`-maintained, minimal, composable middleware model — matches CLAUDE.md's "don't reinvent the stack" and "prefer the standard/blessed tooling" guidance. `shelf_router` gives FastAPI-style route definitions; `shelf_static` serves the desktop-browser admin UI (§13.4) from the same server. |
| Local database | `drift` + `sqlite3_flutter_libs` | `drift: ^2.21.0` (+ matching `drift_dev`, `build_runner`) | **Isar was evaluated and rejected** — the core `isar` package's last release was 2023 and it is not maintained (a "v4" exists but is explicitly marked not production-ready; a community fork exists but has a low package-health score and one maintainer, which is a stability risk CLAUDE.md §10 flags directly: "prefer the standard library or something already in the project"). Drift is a Flutter Favorite, actively maintained, type-safe (compile-time query checking — matches CLAUDE.md §7's "validate input at the boundary" philosophy extended to the DB layer), and gives schema migrations for free, which this app will need as it grows (§13.9). |
| QR/barcode scanning | `mobile_scanner` | `^7.2.0` | Native CameraX/ML Kit on Android (AVFoundation on iOS, for later). Actively maintained, high adoption. Replaces the browser+`html5-qrcode` approach entirely — this is the biggest single simplification from the pivot, since it also removes the TLS-for-camera requirement (§7, §13.6). |
| LAN host discovery/advertisement | `nsd` | `^5.0.1` | Uses each platform's native NSD/Bonjour/mDNS APIs rather than a hand-rolled multicast socket implementation, which is more reliable across real-world Android OEM Wi-Fi stacks. Supports both `register()` (host advertises itself) and `startDiscovery()` (client finds it) — exactly the two operations needed, no extra surface. |
| QR code generation (member codes, UPI pay QR) | `qr_flutter` | `^4.1.0` | Mature, null-safe, no network dependency to render — matches the "static QR, not a live call" principle already established for UPI (§6.3). |
| PDF bill generation | `pdf` (+ `printing` for share/print/save) | `pdf: ^3.11.1`, `printing: ^5.13.4` | Dart-native, no platform-specific PDF engine dependency; direct analog of the current backend's PDF generation, just moved client-side. |
| State management / dependency injection | `flutter_riverpod` (+ `riverpod_generator`) | `flutter_riverpod: ^2.6.1` | Chosen specifically because it enforces the clean separation CLAUDE.md §4 asks for ("keep a clear boundary between user-facing interfaces and internal API/service layers") — providers are the natural seam between UI, the host/client data-access interface (§13.7), and the underlying services, without global mutable state. |
| Keeping the host server alive in the background | `flutter_foreground_task` | `^9.x` — **verify package integrity before pinning.** A supply-chain/CDN issue was publicly reported against a specific 9.1.0 build (mismatched published hash in some regions). Do not blindly `pub add` this — resolve to a specific version, verify its published SHA-256 against the package's GitHub release, and pin it explicitly in `pubspec.lock`. This is exactly the "every dependency is a decision" case CLAUDE.md §10 is describing. | Android kills background processes aggressively; if the phone is the host, the embedded server must run as a proper Android foreground service (with the required persistent notification) or it will be killed mid-shift, silently dropping every client's connection — this is a correctness requirement, not a nice-to-have, given §7's "foolproof" standard. |

**Deliberately not adding:** a separate ORM beyond drift, a separate routing/DI framework beyond Riverpod, or any cloud/Firebase dependency for discovery or sync — all would violate CLAUDE.md §4's "prefer deployment simplicity" and §10's "every dependency is a decision."

### 13.4 Same server, two audiences

One `shelf` server instance, mounted with a `Cascade` (or router-level split), serving two kinds of route from the same host process and the same underlying service/DB layer — no duplicated business logic between them:
- **JSON API routes** (`/api/...`) — consumed by the Flutter client app (other phones on the LAN in client mode).
- **Static web routes** (`/`, `/admin`, assets) — a lightweight HTML/JS admin page for **desktop browsers**, for the "intense admin work" use case (bulk data entry, spreadsheet-adjacent tasks) that's genuinely more comfortable on a bigger screen than a phone. This does **not** include the scan flow — scanning stays native-app-only (§13.6) since it needs the camera and native app is strictly better for it.

This is the direct answer to the "can we host a web server from the same host app" question: yes, and it's a natural fit for `shelf` rather than a bolt-on — it's the same pattern FastAPI + a static-files mount already used, just running embedded in Dart instead of Python.

### 13.5 Discovery mechanics

- Host mode calls `nsd.register()` advertising a service (e.g., `_canteen._tcp`) with the host's chosen port.
- Client mode calls `nsd.startDiscovery('_canteen._tcp')` and lists found hosts by their advertised name (e.g., the canteen's configured app name, §6.8) rather than requiring the operator to type an IP or hostname — this satisfies usability heuristic §11.1 #6 (recognition over recall) directly.
- If a host disappears and reappears (Wi-Fi toggle, app restart), clients should re-resolve automatically rather than requiring a manual reconnect, mirroring the resilience the old `.local`/mDNS setup was designed for.

### 13.6 TLS / certificates — decision

Per the discussion that produced this section: the *original* reason TLS was mandatory (§7) was strictly the browser camera secure-context rule, and that rule no longer applies once scanning is native. What remains is a much smaller, optional concern: encrypting admin login/session traffic between a desktop browser and the phone-hosted server on the LAN.

- **Decision:** ship a **"Generate certificate" button** in host mode that creates a self-signed certificate on-device (no `mkcert` binary, no shelling out — generate natively in Dart via a certificate/crypto package such as `basic_utils` or `pointycastle`) and configures the embedded server to serve HTTPS using it.
- **Known, accepted limitation:** a self-signed cert cannot eliminate the browser's "not trusted" warning on first connection — only a real CA can. The button changes that first-visit experience from "install a root CA, multiple steps" (today's flow) to "click through one browser warning, once per device" — a real improvement, not a full fix. This trade-off should be stated plainly in the admin-facing UI copy when the button is used (per CLAUDE.md §8: user-facing messages are specific, not falsely reassuring).
- **Scope:** this protects the desktop-admin surface only. It is explicitly **not** a requirement for the app to function — plain HTTP between two native app instances (host↔client) is acceptable for v1 given this is a closed, single-canteen LAN with no internet exposure (§7's existing local-network-first framing), and can be hardened later without a breaking change (§13.9).

### 13.7 Code structure (SOLID, extensible beyond Android-only v1)

Per the explicit ask that this not be a dead end once other platforms or transports are wanted, and per CLAUDE.md §4/§5 (clean separation of concerns, small focused modules): structure the app so the **host/client distinction is an implementation detail behind one interface**, not a fork in the UI code.

```
lib/
  core/            # cross-cutting: config, error types, logging
  data/
    local/         # drift schema, DAOs — used only when running as host
    remote/        # HTTP client against a discovered host — used only when running as client
    repository/    # ONE interface per domain (MemberRepository, ScanRepository, ...)
                    # with a HostRepository impl (calls local/) and a ClientRepository impl
                    # (calls remote/) — UI and business-logic code depend on the interface only
  services/        # business rules ported from the current FastAPI services/ layer
                    # (meal-window resolution, grace allowance, scan locking, etc.)
                    # — these run ONLY on the host, called either in-process (host mode)
                    # or via the JSON API (client mode calling into a remote host running them)
  server/          # shelf app: routers, JSON (de)serialization, static admin file serving
  discovery/       # nsd wrapper: advertise() / find()
  ui/
    scanner/       # native camera scan screen (mobile_scanner)
    admin/         # phone-native admin screens
    shared_widgets/ # theme-aware components (§14)
```

This mirrors the existing backend's `core/ schemas/ services/ routers/ utils/` split (PRD §10) closely on purpose — a developer or agent already familiar with the current codebase should recognize the shape immediately. Business rules live in exactly one place (`services/`) regardless of whether the call originated from an in-process host call or a client's HTTP request, which is what makes "extend to iOS / extend to desktop-as-host / extend to a fully offline peer-sync model later" additive rather than a rewrite.

### 13.8 Platform scope for this build vs. later

- **Now:** Android only, phone-as-host and phone-as-client, both from the same APK, per the explicit direction to focus there first.
- **Structurally free, not yet built:** `mobile_scanner`, `nsd`, `drift`, and `shelf` all already support iOS/desktop — the architecture in §13.7 doesn't need to change to add those targets later, only new platform-specific permission/manifest work and QA.
- **Not assumed:** don't build toward multi-host sync, cloud backup, or multi-campus support now (§9 still applies) — the interface-based structure in §13.7 makes room for that later without forcing any of that complexity into v1.

### 13.9 Migration notes from the current build

- The MongoDB collections listed in §8 map conceptually to drift tables of the same purpose; exact schema translation (embedded documents → relational tables/foreign keys where MongoDB's `member_entities` or `settings` used nested structures) is implementation work for the build phase, not decided here.
- Existing pilot data (if any exists by the time this ships) will need a one-time export/import path from MongoDB to the on-device SQLite file — worth a short migration script, scoped separately from this rebuild.
- README.md and `docs/USER_GUIDE.md` are now out of date against this section (they describe `make mdns-setup`, `make tls-setup`, and browser URLs that no longer apply) and must be updated in the same discipline this document requires of itself (§10.1, §11): tracked as a follow-up pass, not done in this edit.

---

## 14. Visual Theme — Neobrutalism (Client Requirement)

**Status:** Client-requested, approved. This section exists so the "how" doesn't get relitigated during implementation — the theme itself is not up for debate; its *execution* follows the rules below so it doesn't fight CLAUDE.md §11–§12.

### 14.1 The decision

The client has requested a neobrutalism visual theme (thick borders, flat saturated color blocks, hard/offset drop shadows, blocky high-contrast type). This is being built as requested — **not softened or talked out of** — but executed in a way that satisfies this codebase's own accessibility and usability standards (CLAUDE.md §11, §12) rather than working against them. The two are not actually in tension once the theme is scoped deliberately (§14.2) instead of applied uniformly.

### 14.2 Intensity is scoped by screen, not global

- **Full intensity** (heavy borders, hard shadows, large flat color blocks): the scan accept/reject result state, and primary call-to-action buttons (submit top-up, confirm scan reversal, generate bill). This is directly supported by the PRD's own requirement (§6.4) that scan results be "big, unambiguous... no reading required beyond a glance," and by Von Restorff (CLAUDE.md §11.2) — the one thing that should visually dominate a screen is the thing the operator must act on fastest.
- **Restrained variant** (same border/type language, lighter shadow weight, tighter palette): admin data surfaces — member tables, the menu-planning calendar, settings forms, purchase-schedule lists. These are information-dense per Miller/Cowan (§11.2) and the "aesthetic minimalist design" heuristic (§11.1 #8); full-intensity neobrutalism on every table row would compete with the data itself rather than support it.

### 14.3 Non-negotiable constraints (from CLAUDE.md, apply regardless of theme)

- **Never encode meaning in color alone** (§12.2, POUR "Perceivable"). Accept/reject and other status states get a distinct shape/icon/border-weight in addition to color, not color by itself — this is free to add within a neobrutalism aesthetic and costs nothing stylistically.
- **WCAG AA contrast is the working default** (§12.2) for text and meaningful UI elements, checked against the actual chosen palette, not assumed because the style is "bold."
- **8-point spacing grid and small type scale still apply** (§11.4) — neobrutalism is a border/color/shadow language, not license to break the underlying grid. Consistent spacing is what keeps it reading as *intentional* rather than chaotic.
- **60/30/10 color distribution** (§11.4) still governs how much of the screen is neutral vs. surface vs. accent, even though neobrutalism's accent colors will be more saturated than a typical soft-UI palette — the ratio keeps the loud colors from overwhelming the interface as a whole.

### 14.4 Deliverable for implementation

Before UI build begins: a small theme spec (color tokens, border-width tokens, shadow tokens, and the two intensity levels from §14.2) should be defined once as reusable design tokens (matches `ui/shared_widgets/` in §13.7's structure) rather than hand-styled per-screen — this is the same "config lives in config, not scattered in code" principle (CLAUDE.md §7) applied to design instead of business logic.

---