# User Guide — Canteen Coupon System (v2, native app)

For the people running the canteen day to day. The system is now a single
**Android app** (`Canteen Coupon`) installed on every device — no browser, no
laptop required. The product rules (units, meal windows, grace allowance, scan
reversal, billing) are unchanged from v1; see `docs/PRD.md` §5–§8.

---

## 1. Roles

| Role | Who | Can do |
|---|---|---|
| **Admin** | The contractor | Everything: members, top-ups & billing, QR codes, menu planning, ingredients/recipes/purchase schedule, expenses, refunds, settings, scan reversal, user accounts. |
| **Counter** | Billing-counter staff | Scan, top-ups & billing, and the shared purchase schedule. Nothing else. |
| **Scanner** | Meal-serving staff | Scan only. |

Students and staff are **records**, not logins — they carry a QR code and get
scanned.

---

## 2. First-time setup

### 2.1 Pick a host device

One phone is the **host**: it holds the database and serves the others. Pick
the phone that stays at the canteen and is on power during meal times —
**preferably an Android phone** (an iPhone host can only serve while the app
is open on screen; see 2.4).

1. Install and open the app on that phone.
2. On the setup screen, tap **Run as host**.
3. It goes straight to **sign in**. The server starts serving on the Wi-Fi on
   its own in the background — there is no separate "start server" step.
4. The first time only, the sign-in screen shows a generated **admin
   password** for username `admin`. Write it down — it is shown once and never
   logged. Sign in and change it from **Users**.

Every other device installs the same app and taps **Run as client**, then
picks the host from the list. If it doesn't appear (some routers block
device-to-device discovery), tap **Connect by IP address** and type the
host's address — see it on the host under **Admin ▸ Hosting & LAN**.

You can change a device's role later from the ↔ icon in the top bar.

### 2.2 Managing the host (Admin ▸ Hosting & LAN)

Sign in on the host as **admin** and open **Hosting & LAN** (also a card at
the top of **Settings**). It shows:

- whether the server is **serving**, and the exact URL(s) other devices use;
- **Stop / Restart** serving (rarely needed — it auto-starts);
- **Generate certificate** for optional HTTPS (see 2.3);
- the keep-awake reminder (2.4).

The admin dashboard shows a yellow banner if the host is *not* serving.

### 2.3 Scanning

Scanning uses the phone camera directly — grant the camera permission when
asked. There is **no HTTPS requirement** for scanning.

### 2.4 Desktop admin (browser)

For heavy data entry, a full admin runs in a desktop browser — served by the
host phone itself. Under **Admin ▸ Hosting & LAN**, the **DESKTOP ADMIN** box
shows the exact URL(s), e.g.:

```
http://192.168.1.42:8710/
```

Open that on any computer on the same Wi-Fi and sign in with an **admin** (or
**counter**) account. It covers everything except scanning: members, top-ups
& billing, scan log & reversal, menu calendar (month grid), categories,
ingredients, recipes, purchase schedule, expenses, refunds, settings, users.
Bill PDFs open in a new tab. Use the plain `http://` URL — it's faster than
the HTTPS one.

**Optional HTTPS:** tap **Generate certificate** under Hosting & LAN, then
**Restart** serving. The server then *also* listens on `https://<ip>:8711/`.
Phones always use the HTTP port, so a cert never affects phone-to-phone use.
The HTTPS URL still shows a browser "not trusted" warning the first time each
computer connects — only a real CA removes that.

### 2.5 No Wi-Fi? Serve from the host's own hotspot (Android)

Under **Admin ▸ Hosting & LAN**, **Start hotspot** makes the Android host
broadcast its own private Wi-Fi — no router, no internet. It shows the
network name, password, and a QR the other phones can scan to join. Once
they're on it, they pick the host from the list, or use **Connect by IP →
192.168.49.1**. Starting the hotspot turns this phone's normal Wi-Fi off
while it's running. (iPhone can't do this — use its built-in Personal
Hotspot from iOS Settings instead.)

### 2.6 Keeping the host awake

While serving, the app keeps the screen from timing out.

- **Android:** a persistent notification + foreground service keep the server
  running even with the screen off. Allow the notification permission when
  asked. Keep the phone on power and on Wi-Fi; don't "force stop" the app.
- **iPhone:** iOS **cannot** keep the server running in the background. Leave
  the app open and on screen for the whole meal service — locking the phone
  or switching apps stops the server and every client drops. iOS also can't
  create its own Wi-Fi: everyone must be on the same router, or turn on
  **Personal Hotspot** (Settings ▸ Personal Hotspot) and have the other
  phones join it. For a full shift, host on Android.

This is shown as a banner on the iPhone during host setup and under Hosting
& LAN.

---

## 3. Daily use

### 3.1 Scan (counter / scanner / admin)

Open **Scan**, point at the QR. The verdict fills the screen:

- **Green ACCEPTED** — name, meal, units left. A yellow **ON GRACE ALLOWANCE**
  badge means the balance went negative.
- **Red REJECTED** — the reason in plain words (unknown code, inactive member,
  no meal being served now, already collected today, no units left).

Tap **Next** for the next person. A member can only be scanned once per meal
per day.

### 3.2 Top-up & bill (counter / admin)

**Top-up & bill** → pick the member → set units per meal type with +/− → pick
**Cash** or **UPI**. The amount is calculated from the unit prices in
Settings — you never type it. **Charge & generate bill** credits the balance
immediately and shows the bill. For UPI it also shows a payment QR for the
payer to scan; once the money lands, tap **Mark received**.

### 3.3 Members (admin)

**Members** → **New** for a student (class + roll) or staff (staff ID).
Tap a member to edit, set them inactive, or set a per-member grace override.
**Credit** adds units without a bill. **QR** shows the printable code — it
never changes, so reprinting a lost card is safe.

### 3.4 Scan log & reversal (admin)

**Scan log** lists recent scans. **Reverse** on an accepted scan within the
configured window (Settings → reversal window) restores the unit. The scan
row stays in the log, marked reversed.

### 3.5 Menu, ingredients, purchase schedule (admin; counter co-manages the schedule)

- **Menu categories** — your own list (Jain, Normal, Staff…).
- **Menu calendar** — log what's served per date/meal, tagged with categories.
- **Ingredients** / **Recipes** — a recipe links a dish name (matched against
  menu items, case-insensitive) to ingredients with free-text quantity notes.
- **Purchase schedule** — the ↻ / generate action builds a shopping list from
  the menu calendar for a date range (safe to re-run — it never duplicates or
  un-checks anything). Admin and counter can check items off and add ad-hoc
  items.

### 3.6 Expenses, refunds (admin)

- **Expenses & revenue** — log expenses; the top strip shows revenue
  (confirmed top-ups), expenses, and profit for the period.
- **Refunds** — deduct units from a leaving member and record it. Units
  pre-fill from their balance and can't exceed it. The actual payout happens
  outside the app.

### 3.7 Notifications

The bell in the top bar shows prep reminders (before a planned meal's window)
and purchase-due reminders. Dismissing one only hides it for you.

### 3.8 Settings (admin)

All runtime config, no reinstall: app name, unit prices, meal windows,
timezone, grace allowance, scan-reversal window, reminder lead times, UPI ID
and payee name.

### 3.9 Users (admin)

Add accounts, change roles, reset passwords, deactivate. You can't deactivate
or delete your own account.

---

## 4. If something's wrong

- **A client says "host unreachable"** — the host phone is off, asleep, on a
  different Wi-Fi, or (iPhone) the app was backgrounded. Wake it, check
  **Admin ▸ Hosting & LAN** shows *serving*, and tap **Retry** / **Find host
  again**. If discovery won't find it, use **Connect by IP address**.
- **Camera won't open** — grant the camera permission in the OS settings for
  Tiffin.
- **Host logs** — the host writes a rolling log file on its own storage
  (`logs/app.log` under the app's documents directory) recording every scan,
  top-up, refund, and admin action.
