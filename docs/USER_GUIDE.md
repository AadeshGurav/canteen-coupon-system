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
- **Prep reminder lead time** and **purchase reminder lead time** — how far
  ahead of a meal / an ingredient's purchase date the notification bell
  (§12) reminds you.

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

## 11. Admin/counter: ingredients, recipes & the purchase schedule

Go to **Ingredients & Purchasing**.

- **Ingredients** (admin-only) — the master list of what you buy, with the
  unit you buy it in (kg, litre, pcs — whatever's natural for that item).
- **Recipes** (admin-only) — link a dish name to the ingredients it needs.
  The dish name must match what you type into a menu entry's items list
  (§7) — spelling matters, but capitalization doesn't ("Dal Rice" and
  "dal rice" are the same dish). Each ingredient gets a free-text quantity
  note (e.g. "2kg per 50 servings") rather than an exact number — this
  system doesn't track expected headcount, so a note is more honest than a
  precise-looking figure that isn't.
- **Purchase schedule** (admin generates it; admin and counter both use it)
  — click **Generate for this range** with a date range covering your
  planned menu, and one line appears per (date, ingredient) for every
  planned dish that has a recipe. Running this again over the same or an
  overlapping range never creates duplicates or resets something already
  checked off. Check the box next to an item once you've bought it — it
  records who and when. You can also add something to the list manually
  (a date, an ingredient, and a note) for anything the menu calendar
  wouldn't otherwise surface.

## 12. Notifications

The bell icon in the nav bar (every page) shows persistent reminders that
survive a refresh or logout:

- **Start prepping [meal]** — appears a configurable number of minutes
  before a planned meal's serving window starts (default 60; set in
  Settings), but only if something's actually on the calendar for it.
- **Ingredient purchase due** — appears when there's still something
  unpurchased on the schedule for a configurable number of days out
  (default 1 day ahead; set in Settings).

Click the bell to see the list; click the × on any item to dismiss it —
dismissing only affects your own view, not anyone else's. New reminders are
checked for automatically every time the bell polls (no need to refresh the
page); nothing here is email or SMS, it's all in-app.

## 13. Admin: managing user accounts

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

## 14. Troubleshooting

If something breaks or behaves unexpectedly, check `logs/app.log` on the
host machine first — every scan decision, top-up, refund, member change, and
settings change is logged there with enough detail to diagnose without
reproducing the issue, and any unexpected server error is logged there with
full detail even though the browser only shows a generic message.

### The dashboard/scanner won't load — `docker compose up` says the app container is unhealthy

Run `docker compose logs app --tail 60`. If you see
`Authentication failed` (or the app itself prints `FATAL: MongoDB
authentication failed`), the password in `.env`'s `MONGO_ROOT_PASSWORD`
doesn't match the one already stored inside the database — this happens if
that value was changed *after* the stack had already run once before,
since MongoDB only applies it the very first time. Two ways out:
- Put `.env`'s `MONGO_ROOT_PASSWORD` back to whatever it was the first time
  this deployment ever came up, or
- If there's no real data on this machine yet worth keeping, run
  `docker compose down -v` (this deletes the database and generated files)
  and then bring it back up — it'll reinitialize cleanly against
  whatever's in `.env` now.

### The scanner keeps asking for camera permission every time the page loads

The scanner now checks camera permission on load and shows a clear "Enable
camera" button instead of silently retrying — if it's still asking every
time even after tapping that and allowing access, the most common cause is
an **unstable IP address**: a browser's permission grant is tied to the
exact address the page was loaded from (e.g. `http://192.168.1.42/...`),
and phones on a hotspot/router often get handed a *different* IP address
every time they reconnect, which looks like a brand new site to the
browser each time — so it forgets the earlier grant. If the scanner phone
is on the same network as the host machine, set up the optional stable
hostname (`make mdns-setup`, documented in the README) and access the
scanner via that `<name>.local` address instead of a raw IP — a stable
address means a stable permission grant.

### Admin login shows up on a device I didn't expect

This isn't a shared session — session tokens live only in the browser that
logged in and can't transfer to another device through anything this app
does. Check `logs/app.log` for `auth.login_succeeded username=...` lines:
if you see one entry per device/time, someone simply signed in with the
same known credentials on both, most likely because a browser's saved-
password feature offered/autofilled it (this can happen across devices
signed into the same browser account, e.g. the same Google or Apple
account). If a device is meant to be scan-only, sign it in with a
`scanner`-role account instead of the admin account — then even if it's
left signed in, it can't do anything beyond scan.

`(This section is meant to keep growing from real issues hit during the
pilot. When something breaks, add what happened and how it was fixed here.)`

---

*This guide is updated alongside the application. If something here doesn't
match what you see on screen, that's a bug in the documentation — please flag
it.*
