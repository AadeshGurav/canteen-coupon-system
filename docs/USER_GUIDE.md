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
`(TODO: fill in once hosting is finalized — e.g. "on the canteen laptop, open
http://canteen.local:8000 in a browser")`

### 2.2 Logging in
`(TODO: once admin auth is added, document credentials/setup here)`

## 3. Admin: managing members (students & staff)

### 3.1 Adding a new member
`(TODO: step-by-step once the admin UI exists — for now, done via the API at
POST /members)`

### 3.2 Editing a member
`(TODO)`

### 3.3 Printing a QR code
`(TODO)`

### 3.4 Reprinting a lost or damaged QR code
Reprinting always reuses the member's original code — it will never generate a
new one, so there's no risk of creating a duplicate record for the same person.
`(TODO: exact steps once UI exists)`

### 3.5 Deactivating a member
`(TODO)`

## 4. Admin: topping up balances & billing

### 4.1 Adding lunch / breakfast / brunch units
`(TODO)`

### 4.2 Cash payment
`(TODO)`

### 4.3 UPI payment
The system generates a UPI QR code for the parent or staff member to scan and
pay directly — there's no live payment confirmation, so **you (the admin) must
manually mark the payment as received** once you see it land in your UPI app.
`(TODO: exact steps once UI exists)`

### 4.4 Finding and reprinting a bill
`(TODO)`

## 5. Counter operator: scanning

### 5.1 Opening the scanner
`(TODO)`

### 5.2 Reading the result
- **Green / accepted** — meal confirmed, hand over the meal.
- **Red / rejected** — do not hand over the meal. The message on screen will say
  why (no units left, already scanned for this meal, unknown code, etc.).

### 5.3 What to do if the code won't scan
`(TODO)`

## 6. Admin: undoing a mistaken scan

If a scan was confirmed by mistake, it can be reversed within the reversal
window (default: 10 minutes after the scan). Reversing restores the unit to the
member's balance.
`(TODO: exact steps once UI exists)`

## 7. Admin: menu planning

This is for your own planning — students and staff never see this.
`(TODO)`

## 8. Admin: expenses & revenue

`(TODO)`

## 9. Admin: settings

These control how the system behaves and can be changed at any time without
needing a developer:

- **Meal windows** — the start/end time for breakfast, lunch, and Saturday
  brunch.
- **Grace allowance** — whether members can go negative on a balance, and by
  how many units, before being turned away. Can also be set per member as an
  exception.
- **Reversal window** — how many minutes after a scan it can still be undone.

`(TODO: exact steps once settings UI exists)`

## 10. Troubleshooting

`(TODO — this section is meant to grow from real issues hit during the pilot.
When something breaks, add what happened and how it was fixed here.)`

---

*This guide is updated alongside the application. If something here doesn't
match what you see on screen, that's a bug in the documentation — please flag
it.*
