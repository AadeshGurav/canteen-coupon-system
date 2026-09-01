# User Guide — Canteen Coupon System

This is a working document for the people actually running the canteen day to
day: the admin (managing members, top-ups, and settings) and whoever staffs the
scanner at meal times. It starts bare and gets filled in as the system is built
and tested — treat sections marked `(TODO)` as placeholders, not gaps to work
around.

---

## 1. Who this is for

- **Admin** — adds and manages students/staff, tops up balances, prints QR
  codes, plans the menu, tracks expenses, and adjusts settings.
- **Counter operator** — uses the scanner page at meal times. No login needed;
  this can be the admin or anyone else staffing the counter.

## 2. Getting started

### 2.1 Accessing the system
On the canteen laptop (or any device on the same local network), open a
browser to:
- **Admin dashboard:** `http://<host-device-ip-or-dns-name>:8000/static/admin/index.html`
- **Counter scanner:** `http://<host-device-ip-or-dns-name>:8000/static/scanner.html`

Bookmark both — the dashboard has a nav bar at the top linking to every admin
page (Members, Top-ups & Billing, Scan Log, Menu Planning, Expenses, Refunds,
Settings).

### 2.2 Logging in
There is no login for this build — the admin dashboard and scanner are open to
anyone on the local network. This is acceptable for a LAN-only pilot but
**must** be addressed before handoff or any exposure beyond the local network
(see `docs/PRD.md` §9).

## 3. Admin: managing members (students & staff)

### 3.1 Adding a new member
Go to **Members** → **+ Add member**. Choose Student or Staff, enter their
name and the type-specific field (class/roll number for a student, staff ID
for staff), and optionally a personal grace allowance override. Saving
generates their permanent QR code automatically — new members start with
zero balances until you top them up (§4).

### 3.2 Editing a member
On the **Members** page, click **Edit** on their row to change their name,
class/roll/staff ID, status, or grace override. A member's `type`
(student/staff) can't be changed after creation — if you get it wrong,
deactivate the record and create a new one.

### 3.3 Printing a QR code
Click **QR** on a member's row to open/download their code as a PNG, ready to
print.

### 3.4 Reprinting a lost or damaged QR code
Click **QR** again — reprinting always reuses the member's original code, so
it never generates a new one and never creates a duplicate record for the
same person.

### 3.5 Deactivating a member
Click **Deactivate** on their row. An inactive member's code will be rejected
at the scanner with a clear "account inactive" message instead of a generic
error. Click **Activate** to reverse this at any time — deactivating does not
touch their balances.

### 3.6 Migrating existing paper records in bulk
For a one-time migration from paper records, `POST /members/bulk` (via
`/docs`, or ask your developer to run a script against it) accepts a list of
members in one request. Each row is created independently — one bad row in
a large batch doesn't fail the rest — and the response lists which rows
succeeded and which failed, with why.

## 4. Admin: topping up balances & billing

### 4.1 Adding lunch / breakfast / brunch units
Go to **Top-ups & Billing**, pick the member, enter how many units of each
meal type they're buying, the amount paid, and a payment method. Submitting
credits their balance immediately and generates a PDF bill you can open from
the **Bill** link in the top-ups table below the form.

(For a quick balance correction with no bill — e.g. fixing a data-entry
mistake — use the **Credit** button on the **Members** page instead.)

### 4.2 Cash payment
Choose **Cash** as the payment method. The top-up is marked **Confirmed**
immediately — nothing further to do.

### 4.3 UPI payment
Choose **UPI**. The generated bill includes a UPI payment QR for the parent
or staff member to scan and pay directly — there's no live payment
confirmation, so the top-up starts **Pending**. Once you see the money land
in your own UPI app, come back to **Top-ups & Billing** and click **Confirm
payment** on that row.

### 4.4 Finding and reprinting a bill
Every past top-up is listed on the **Top-ups & Billing** page with a **Bill**
link that opens the original PDF.

## 5. Counter operator: scanning

### 5.1 Opening the scanner
Open `http://<host>:8000/static/scanner.html` on the counter phone's browser
and allow camera access. Leave it open for the whole meal period.

### 5.2 Reading the result
- **Green / accepted** — meal confirmed, hand over the meal. A yellow
  **GRACE** badge means this meal was only possible because the member went
  into their grace allowance — worth a mental note that they're eating on
  credit.
- **Red / rejected** — do not hand over the meal. The message on screen will
  say why (no units left, already scanned for this meal, unknown code, etc.).

### 5.3 What to do if the code won't scan
Make sure the code is flat, well-lit, and fully in frame. If it's damaged,
have the admin reprint it (§3.4) — reprinting never changes the underlying
code, so the reprinted copy will scan exactly the same as the original.

## 6. Admin: undoing a mistaken scan

Go to **Scan Log**. Enter your name once (it's remembered on this device),
then click **Reverse** next to the scan you want to undo — this only appears
while the scan is still inside the reversal window (default: 10 minutes
after the scan). Reversing restores the unit to the member's balance and
keeps the original scan record marked "Reversed" rather than deleting it, so
there's always an audit trail.

## 7. Admin: menu planning

This is for your own planning — students and staff never see this. Go to
**Menu Planning**:
1. Under **Menu categories**, add the tags you use to label dishes (e.g.
   Jain, Normal, Staff) — these are fully yours to add, rename, or remove as
   the offering changes.
2. Under **Log today's menu**, pick the date and meal, check which
   category/categories the dish applies to, list the items, and save. The
   log below shows everything entered so far, most recent first.

## 8. Admin: expenses & revenue

Go to **Expenses**. Log each expense (category, description, amount, date)
as it happens. The **Revenue vs. expense summary** card above the log lets
you pick a date range (or leave it open-ended) to see total revenue
(confirmed top-ups), total expenses, and profit for that period.

## 9. Admin: settings

Go to **Settings**. These control how the system behaves and can be changed
at any time without needing a developer — changes take effect immediately,
no restart required:

- **Meal windows** — the start/end time for breakfast, lunch, and Saturday
  brunch, in the canteen's own local time (make sure `LOCAL_TIMEZONE` in the
  server's environment is set correctly for your location — see the README —
  or these times will be checked against UTC instead).
- **Grace allowance** — whether members can go negative on a balance, and by
  how many units, before being turned away. Enable/disable it and set the
  default unit count here; set a per-member exception on that member's row
  on the **Members** page.
- **Reversal window** — how many minutes after a scan it can still be undone.

## 10. Admin: refunds

Go to **Refunds** when a member leaves the school or otherwise stops using
the canteen. Pick the member, enter how many units of each meal type are
being refunded and the amount, and save. This deducts the units from their
balance immediately and keeps a record of what was refunded and why — the
actual money movement (cash back, bank transfer) is something you handle
yourself outside the app. This doesn't deactivate the member; if they're
leaving for good, also deactivate them (§3.5).

## 11. Troubleshooting

If something breaks or behaves unexpectedly, check `logs/app.log` on the
host machine first — every scan decision, top-up, refund, member change, and
settings change is logged there with enough detail to diagnose without
reproducing the issue, and any unexpected server error is logged there with
full detail even though the browser only shows a generic message.

`(This section is meant to keep growing from real issues hit during the
pilot. When something breaks, add what happened and how it was fixed here.)`

---

*This guide is updated alongside the application. If something here doesn't
match what you see on screen, that's a bug in the documentation — please flag
it.*
