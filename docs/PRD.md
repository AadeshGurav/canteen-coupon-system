# PRD — Canteen Unit-Based Coupon System

**Status:** Active build
**Owner:** Aadesh (developer/architect) — building for a canteen contractor client
**Build window:** 15 days, single-campus pilot
**Audience for this doc:** Claude Code (or any engineer/agent) implementing this system. Read this fully before writing code.

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
- No mobile app. Everything is a browser page served on the local network.
- No automated UPI payment webhook/confirmation in this build — confirmation is manual by the admin.
- No WhatsApp integration in this build (deferred — see §9).

---

## 4. Users & Roles

| Role | Who | What they do |
|---|---|---|
| **Admin** | The contractor (client) | Full CRUD on member entities, top-ups & billing, QR generation/reprint, menu planning, expense tracking, settings (grace allowance, meal windows, reversal window), scan reversal. |
| **Counter operator** | Whoever is staffing the scan point (could be the admin or someone else) | Uses the shared scanner page. No separate login required — this is a single shared station. |
| **Member entity — student** | A student, represented as a record, not a login-based "account" | Has a QR code. Gets scanned at the counter. Does not use the app directly. |
| **Member entity — staff** | A staff member, same entity model as student with a different `type` | Same as student, different pricing. |

**Important modeling decision:** students and staff are **one data type**, `member_entity`, distinguished by a `type` field — not two separate collections/models. This avoids duplicate CRUD logic and duplicate schemas for what is functionally the same entity with different pricing and a couple of type-specific fields (class/roll number vs. staff ID).

---

## 5. Core Concepts

- **Unit, not currency.** Every member entity has three balances: `lunch`, `breakfast`, `brunch`. A scan deducts exactly one unit of the relevant type. Top-ups add units. Nothing here is a monetary wallet.
- **No automatic resets, ever.** Balances are never reset at month-end, term-end, or on any schedule. A balance only changes because of a scan, a scan reversal, a top-up, or a refund. If a member is out of units, they're out — the only thing that changes that is a top-up (or the grace allowance, see below). This is intentional: units purchased don't expire or get wiped by the calendar.
- **Saturday is different.** On Saturdays there is no separate breakfast/lunch — only a single **brunch** meal. Brunch is a third, independent unit type, only consumable on Saturdays.
- **Meal windows are configurable, not hardcoded.** Breakfast, lunch, and brunch each have a start/end time. These live in a `settings` document in the database and are editable by the admin — never hardcoded constants in source.
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
- Admin selects a member, enters units to add per meal type, and a payment method: `cash` or `upi`.
- On submit: balances are credited immediately, and a **PDF bill** is generated showing units purchased and the member's new balances.
- If payment method is `upi`: generate a UPI payment QR (standard `upi://pay` URI scheme — no payment gateway integration) and embed/attach it with the bill. Payment status starts `pending`.
- If payment method is `cash`: payment status is `confirmed` immediately; no UPI QR needed.
- Admin can manually mark a pending UPI top-up as `confirmed` once they've verified receipt in their own UPI app. There is no automated payment webhook in this build.

### 6.4 Scanning (Counter Flow)
- One shared scanner page, browser-based, accessed via a local-network DNS name from a mobile phone camera. No login for this page.
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
- This is a planning/record tool only — no student- or staff-facing view.

### 6.6 Expense & Revenue Tracking (Admin)
- Admin can log expenses (category, description, amount, date) — groceries, tables, other overhead.
- System should provide a simple revenue-vs-expense summary (revenue = confirmed top-ups in a date range, expenses = logged expenses in that range, profit = the difference).

### 6.7 Refunds (Admin)
- If a member leaves the school or otherwise stops using the canteen, the admin can process a refund: specify how many lunch/breakfast/brunch units are being refunded and the refund amount.
- The **actual money movement is handled by the admin outside the app** (cash back, bank transfer, etc.) — the system's job is to keep the unit ledger accurate and to keep a record of what was refunded, when, and why.
- Refunding deducts the specified units from the member's balance immediately. A refund cannot request more units than the member currently has.
- This does not automatically deactivate the member — deactivation (if the member is leaving for good) is a separate action via the member's `status` field.

### 6.8 Settings (Admin)
All of the following must be stored in the database and editable at runtime — **none of this is a hardcoded constant in source**:
- Grace allowance: enabled/disabled, and default unit count.
- Meal windows: start/end time for breakfast, lunch, and brunch (brunch applies Saturday only).
- Scan reversal window (minutes).

---

## 7. Non-Functional Requirements

- **Frictionless & foolproof.** This term was used repeatedly in planning specifically about the admin/payment side — every action there should have a clear, unambiguous outcome and be hard to get wrong. Favor explicit confirmations and clear state over cleverness.
- **Mobile-first, lightweight scanner page.** It will sit open on a phone browser for hours across a meal period. No heavy frontend framework, no memory leaks, no unnecessary background work. Plain JS/HTML preferred over a full SPA framework for this page specifically.
- **Local-network first.** Scanning and the admin dashboard must work entirely on the local network with no internet dependency. Internet access is only required for the UPI QR payment step (and that's still just a static QR, not a live network call).
- **Operable without the developer.** The admin is technically capable and can debug his own issues post-handoff, but only if the system surfaces **clear, specific errors** (not generic 500s or silent failures) and maintains a **detailed, searchable action log** of scans, top-ups, and admin actions. Design logging as a first-class feature, not an afterthought — this is intended to double as the admin's own debugging tool.
- **Self-hosted, low-maintenance.** No managed cloud dependencies required to run day-to-day. Target host is a laptop (or possibly a phone) on the local network.
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
- `settings` — single global document: grace allowance config, meal windows, reversal window.

If the code and this PRD ever disagree on a schema detail, the code is the source of truth for *what currently exists*, but any schema change should be reflected back into this PRD and the README (see §11).

---

## 9. Out of Scope for This Build (Explicitly Deferred)

- Automated UPI payment confirmation via a payment gateway (e.g., Razorpay/Cashfree webhook). Manual confirmation only, for now.
- WhatsApp delivery of bills/PDFs. To be discussed and added later.
- Searchable, verbose action logging via a dedicated search engine (e.g., Elasticsearch) alongside the primary database. The primary database logs remain the source of truth for now; this is a planned upgrade once the core flow is validated in the pilot.
- Multi-campus / multi-tenant support.
- Authentication/authorization on admin endpoints (acceptable for a LAN-only pilot; **must** be addressed before any handoff or exposure beyond the local network).
- Any student/staff-facing app, portal, or menu view.

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
