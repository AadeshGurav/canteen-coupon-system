# ADR 0001 — Runtime theming, data portability, and the choices behind them

Status: accepted · 2026-09-04

Records the decisions from the release that added four themes, motion, a
first-run setup flow, per-host saved logins, and Excel/backup export — with the
alternatives that were rejected, so they don't get relitigated.

---

## 1. Design tokens moved from `static const` to a `ThemeExtension`

**Context.** Every token (`NbColors.ink`, `NbType.body`, …) was a compile-time
constant referenced directly in 30 files — 313 references. The app could only
ever have one look.

**Decision.** Tokens live in a `TiffinTokens` object carried on `ThemeData` as a
`ThemeExtension`, read through `context.tokens`.

**Alternatives rejected.**
- *A mutable global swapped on theme change.* Same edit count, but implicit
  global state that fights Flutter's rebuild model.
- *Keeping tokens const and shipping one theme.* Doesn't meet the requirement.

**Consequences.** 313 mechanical edits and 24 `const` constructors dropped.
Spacing and intensity stayed `static const` on purpose — an 8pt rhythm isn't a
matter of taste, and excluding it halved the migration. A missed token no longer
fails to compile; it throws at build time on one screen under one theme, which
is why `theme_render_test.dart` exists.

---

## 2. Palettes are authored in OKLCH, in-repo

**Decision.** A small pure-Dart OKLCH → sRGB converter, with palettes expressed
as lightness steps on fixed hue/chroma.

**Why.** Eight palettes (four themes × light/dark) is too many to hand-pick.
OKLCH makes dark mode a lightness inversion of the same hue rather than a second
palette, and makes "hold the hue, fix the contrast" a one-number change.

**Consequences.** ~90 lines to own and test. Worth it: the contrast test found
eleven real failures during authoring that hand-picked hex would have shipped.

---

## 3. Motion is hand-rolled, not `flutter_animate`

**Decision.** Entrance, stagger, press and switch are built on Flutter's own
primitives.

**Why.** All four are short with built-in widgets, and hand-rolling kept the
"animations off" switch a single branch instead of a flag threaded through a
library. The stagger delay is an `Interval` on the curve rather than a
`Future.delayed`, so there is no timer to leak when a fast scroll disposes the
widget.

**Consequence.** Deviates from the plan, which specified `flutter_animate`.

---

## 4. The first admin is chosen, not generated

**Context.** Bootstrap created `admin` with a random password and displayed it
once on the login screen, held only in a `StateProvider`. Background the app,
restart it, or miss the banner, and the host had an account nobody could sign in
as — recoverable only by wiping the database.

**Decision.** A host with an empty users table shows a setup screen where the
operator chooses the credentials, with a "suggest a strong one" button.

**Why not just persist the generated password?** Storing a plaintext credential
to make up for a UI that can be missed is the wrong fix. The condition is
derived from the database on every read, so setup also reappears correctly after
a data reset instead of being a one-shot.

**Recovery.** "Forgot the password?" exists on the host device only and never
over the network — it runs against the local database, so it grants nothing that
physical possession of the phone didn't already grant, given the same phone can
wipe everything from Settings.

---

## 5. Saved logins key on a host id, not a URL

**Decision.** Hosts generate a stable id (schema v4, filled lazily). Clients key
saved logins on it, in the platform keychain via `flutter_secure_storage`.

**Why.** A LAN address is not an identity — DHCP hands out a different one and
the same canteen looks like a new host. Keying on the id also lets one phone
keep separate account sets for two canteens.

**Security posture.** Usernames are always remembered (not a secret, and typing
one on a phone is friction worth removing). Passwords only on an explicit
per-account opt-in, and clearing that tick actively deletes a previously saved
one. These are shared phones; the opt-in is the point.

---

## 6. Excel is export-only; the backup file is the migration path

**Decision.** Two artifacts. A multi-sheet `.xlsx` for people to read, print and
pivot — never re-imported. A `.tiffin` backup (zip: manifest + `VACUUM INTO`
snapshot) for moving a canteen to a new phone.

**Why not Excel round-trip?** A spreadsheet loses types, ids and referential
integrity. Reading one back is a route to corrupt balances, which is the one
failure this app cannot have.

**Passphrase optional, not mandatory.** The file carries member names and
password hashes, so protection is offered and recommended — but a mandatory
passphrase turns "forgot it" into permanent data loss, and losing the data is
the worse failure of the two.

**Restore ordering.** Validate and stage → stop serving → keep the current
database beside the new one → clear the stale WAL → swap. Nothing is destroyed
until the file has been proven readable.

---

## 7. The `.xlsx` writer is hand-rolled

**Context.** The maintained `excel` package pins `archive ^3`; `basic_utils`,
which generates the host's TLS certificate, needs `archive ^4`. No version of
`excel` resolves.

**Decision.** Write the slice of the format a report needs — a zip of XML parts
with inline strings.

**Why not pin `basic_utils` back?** Freezing a security-relevant dependency to
accommodate a reporting convenience is the worse trade.

**Consequence.** ~180 lines to own. Nine tests pin the parts Excel requires and
the escaping it rejects, because "unreadable content" is a silent failure.

---

## 8. `wakelock_plus` was replaced with ~20 lines of native code

**Context.** It pulled `package_info_plus`, which applies its own Kotlin plugin
and no longer compiles under this Flutter — the Android build failed with
"cannot find symbol PackageInfoPlugin" the moment a cached AAR was cleaned. The
whole dependency existed for one call.

**Decision.** A `tiffin/screen` MethodChannel — a window flag on Android, the
idle timer on iOS — on the same pattern the hotspot control already uses.

**Consequence.** Two fewer dependencies and a version-conflict class removed
permanently.

---

## 9. The `applicationId` and iOS bundle ID were left alone

**Decision.** Everything else was renamed to Tiffin — Dart package, mDNS service
type, database filename, notification channel, TLS common name, web-admin
storage keys, docs, CI artifact, the GitHub repo. The Android `applicationId`
(`com.canteen.canteen_coupon`) and iOS bundle ID stayed.

**Why.** They are internal identifiers the OS uses to tell installed apps apart.
No user sees them — both display names already read "Tiffin". Changing one makes
the OS treat this as a *different app*: the old install stays, the new one starts
empty, and **the host's database does not carry over**. Real risk, zero
user-visible benefit.

The database filename *was* renamed, with a rename-on-open for a pre-Tiffin
`canteen.sqlite` (and its journal), because a cosmetic rename must not be the
thing that loses a host's only copy of its data.
