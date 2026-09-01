# User Guide — Canteen Coupon System

This is a working document for the people actually running the canteen day to
day: the admin (managing members, top-ups, and settings) and whoever staffs the
scanner at meal times. It starts bare and gets filled in as the system is built
and tested — treat sections marked `(TODO)` as placeholders, not gaps to work
around.

---

## 1. Who this is for

- **Admin** — adds and manages students/staff, tops up balances, prints QR
  codes, plans the menu, tracks expenses, adjusts settings, and manages the
  other accounts below. Has access to everything.
- **Counter** — a login role for whoever staffs the top-up/billing counter.
  Can scan and record top-ups; can't touch member records, menu planning,
  expenses, refunds, settings, or other users.
- **Scanner** — a login role for whoever staffs the meal-serving scan point.
  Can only scan.

## 2. Getting started

### 2.1 Accessing the system
On the canteen laptop (or any device on the same local network), open a
browser to:
- **Admin dashboard:** `http://<host-device-ip-or-dns-name>:8000/static/admin/index.html`
- **Counter scanner:** `http://<host-device-ip-or-dns-name>:8000/static/scanner.html`

Bookmark both — the dashboard has a nav bar at the top linking to every page
you have access to (Members, Top-ups & Billing, Scan Log, Menu Planning,
Expenses, Refunds, Settings, Users — a counter or scanner login only sees the
subset it can actually use).

### 2.2 Logging in
Every page requires signing in with a username and password — there's one
account per person/station, each with a role (§1) that controls what they can
see and do. The very first account (an **admin**) is created automatically
the first time the app starts, from `INITIAL_ADMIN_USERNAME`/
`INITIAL_ADMIN_PASSWORD` in `.env` — after that, add every other account
(admin, counter, or scanner) from the **Users** page (admin-only), never by
editing `.env` again. A session stays signed in on that device/browser until
you sign out or it expires (`SESSION_TTL_HOURS`, default 12).

If you forget a password, an admin can reset it from the **Users** page —
there's no self-service "forgot password" flow, by design, since this isn't
an internet-facing product with an email/SMS channel to send a reset link
through.

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

## 4. Admin/counter: topping up balances & billing

### 4.1 Adding lunch / breakfast / brunch units
Go to **Top-ups & Billing**, pick the member, and enter how many units of
each meal type they're buying. The amount updates live as you type — it's
calculated from the unit prices set on the **Settings** page (§9), so you
never type an amount by hand. At least one unit is required; the button to
record the top-up stays disabled while everything is at zero. Submitting
credits their balance immediately and generates a PDF bill you can open from
the **Bill** link in the top-ups table below the form.

(For a quick balance correction with no bill — e.g. fixing a data-entry
mistake — use the **Credit** button on the **Members** page instead,
admin-only.)

### 4.2 Cash payment
Choose **Cash** as the payment method. The top-up is marked **Confirmed**
immediately — nothing further to do.

### 4.3 UPI payment
Choose **UPI**. Right after you submit, a pop-up shows the UPI payment QR for
the parent or staff member to scan and pay directly on the spot — it doesn't
appear on the bill PDF itself. There's no live payment confirmation, so the
top-up starts **Pending**. Once you see the money land in your own UPI app,
come back to **Top-ups & Billing** and click **Confirm payment** on that row.
You can reopen the QR for any pending UPI top-up from its row if you closed
the pop-up too soon.

### 4.4 Finding and reprinting a bill
Every past top-up is listed on the **Top-ups & Billing** page with a **Bill**
link that opens the original PDF.

## 5. Scanning

### 5.1 Opening the scanner
Open `http://<host>:8000/static/scanner.html` on the counter phone's browser
and sign in with a scanner, counter, or admin account (§2.2) — this device
stays signed in afterward, so this is only needed once per phone/browser,
not once per meal. Allow camera access and leave it open for the whole meal
period.

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
2. The calendar below is the main planning view. Use **Prev**/**Next** to
   move between months; each day shows what's already logged as small tags,
   right on the calendar. Click any day (or **+ Log an entry**) to open a
   form pre-filled with that date — pick the meal, check which
   category/categories the dish applies to, list the items, and save. The
   same dialog also lists — and lets you delete — anything already logged
   for that day.

## 8. Admin: expenses & revenue

Go to **Expenses**. Log each expense (category, description, amount, date)
as it happens. The **Revenue vs. expense summary** card above the log lets
you pick a date range (or leave it open-ended) to see total revenue
(confirmed top-ups), total expenses, and profit for that period.

## 9. Admin: settings

Go to **Settings**. These control how the system behaves and can be changed
at any time without needing a developer — changes take effect immediately,
no restart required:

- **Timezone** — set this to the canteen's actual location (e.g. `Asia/
  Kolkata`) before setting meal windows below, using the dropdown — it lists
  every timezone the server knows, so there's no typo risk. Left at the
  default `UTC`, breakfast/lunch/brunch will be checked against UTC time
  instead of the canteen's own clock.
- **Meal windows** — the start/end time for breakfast, lunch, and Saturday
  brunch, in the timezone set just above.
- **Unit prices** — price per lunch/breakfast/brunch unit. These drive the
  automatic amount calculation on the Top-ups & Billing and Refunds pages
  (§4.1, §10) — set them here once and never type a rupee amount by hand
  again.
- **UPI payment** — the UPI ID and payee name shown on a UPI top-up's
  payment QR (§4.3). Leave the UPI ID blank for a cash-only canteen.
- **Grace allowance** — whether members can go negative on a balance, and by
  how many units, before being turned away. Enable/disable it and set the
  default unit count here; set a per-member exception on that member's row
  on the **Members** page. When it's on, the **Members** page also shows a
  **Grace left** column — how many grace units each member still has before
  they'd be turned away.
- **Reversal window** — how many minutes after a scan it can still be undone.
- **Branding** — the application name shown in the nav bar and browser tab
  across the whole dashboard. Purely cosmetic — rename it to your canteen's
  actual name if you like.

## 10. Admin: refunds

Go to **Refunds** when a member leaves the school or otherwise stops using
the canteen. Pick the member — the unit fields pre-fill with everything they
currently have (so refunding "all of it" needs no typing), or lower the
numbers for a partial refund; you can't enter more than the member's actual
balance. The refund amount is calculated automatically from the unit prices
set in Settings (§9), the same as top-ups. Save, and it deducts the units
from their balance immediately and keeps a record of what was refunded and
why — the actual money movement (cash back, bank transfer) is something you
handle yourself outside the app. This doesn't deactivate the member; if
they're leaving for good, also deactivate them (§3.5).

## 11. Admin: managing user accounts

Go to **Users** to add, edit, or remove the login accounts covered in §1/§2.2
— this page is admin-only.

- **Add a user** — enter a username, a temporary password (they can't change
  it themselves yet, so pick something you'll tell them), and a role
  (admin/counter/scanner).
- **Change a role** — use the role dropdown directly on their row.
- **Reset a password** — click **Reset password** on their row and enter a
  new one.
- **Deactivate / reactivate** — turns their login on or off without deleting
  the account (or its history of who-did-what).
- **Delete** — permanently removes the account.

You can't demote, deactivate, or delete your own account from this page —
that's a deliberate guardrail so an admin can't accidentally lock themselves
out.

## 12. Troubleshooting

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
