# Tiffin — canteen coupon system (v2, native Flutter app)

A single-campus canteen tool that issues each student/staff member a permanent
QR code, scans it at meal time for an instant accept/reject, and tracks meal
entitlements as **units** (lunch / breakfast / brunch) — never currency.

**v2 architecture (PRD §13):** one Flutter app, one APK, two roles on the LAN:

- **Host** — runs the on-device SQLite database (drift), the business logic,
  and an embedded HTTP server (shelf), and advertises itself over mDNS.
- **Client** — discovers a host on the same Wi-Fi and talks to it over
  HTTP/JSON. Same screens; the host/client difference is one interface behind
  the UI (`lib/data/repository/`).

The full product spec — business rules, roles, meal-window logic, grace
allowance, scan reversal, billing, menu planning, purchase schedule,
notifications — is in [`docs/PRD.md`](docs/PRD.md) (§5–§8).

- **Themes** — four (Neobrutal, Clean, Frost, Clay), each light and dark, with
  motion that belongs to the theme: [`docs/THEME_SPEC.md`](docs/THEME_SPEC.md).
- **Why things are the way they are** — runtime theming, the first-run setup
  flow, saved logins, and the export/backup design, with the alternatives that
  were rejected: [`docs/adr/`](docs/adr/).
- **Day-to-day use** — [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md).

Data portability: admins can export a multi-sheet `.xlsx` report, and a
complete encrypted `.tiffin` backup that restores onto another phone.

> **v1 (browser + FastAPI + MongoDB) has been removed** in favour of this
> rebuild. It's recoverable from git history before the `chore: remove v1`
> commit if a business rule needs cross-checking.

## Requirements

- Flutter SDK ≥ 3.24 (Dart ≥ 3.5)
- **Android:** Android SDK + JDK 17 (`flutter doctor` lists what's missing);
  an Android device or emulator.
- **iOS** (client mode; host is Android-first, PRD §13.8): a Mac with the
  full **Xcode** app + **CocoaPods** (`brew install cocoapods`), and an
  Apple ID for signing. `ios/` is scaffolded and configured (camera, local
  network + Bonjour `_tiffin._tcp`, ATS local networking). Open
  `ios/Runner.xcworkspace` in Xcode, set your Team + a unique bundle id,
  then `flutter run`.

## Setup

```bash
make setup      # flutter pub get + codegen (drift / riverpod / l10n)
make run        # run on a connected device (Android or iOS)
make apk        # release APK  ->  build/app/outputs/flutter-apk/
make ios        # release .app (needs Xcode) -> build/ios/iphoneos/
```

`make setup` runs `build_runner`, which generates the files git ignores
(`*.g.dart`). Re-run `make gen` after changing a drift table, a `@riverpod`
provider, or `lib/l10n/*.arb`.

**After a schema change**, bump `AppDatabase.schemaVersion` and run
`make schema`. That snapshots the new schema and regenerates the versioned
migration steps, so `test/migration_test.dart` runs the real migration against
a real previous version. A host's SQLite file is the only copy of its data, so
migrations are not written against the *current* tables — each step sees the
schema as it was at that version.

## Project layout (PRD §13.7)

```
lib/
  app/            bootstrap, mode gate
  core/           config, typed errors, logging, role, app mode, time/meal windows
  domain/         plain models shared by every layer
  data/
    local/        drift schema + DAOs        (host mode only)
    remote/       HTTP client to a host      (client mode only)
    repository/   ONE interface per domain, + Host*/Client* implementations
  services/       business rules (host only) — ported from v1 app/services + routers
  server/         shelf app: routers, JSON, static desktop-admin serving
  discovery/      nsd wrapper: advertise() / find()
  ui/
    theme/        design tokens + the four themes, in OKLCH
    settings/     appearance (theme, light/dark, motion, saved logins)
    shared_widgets/
    ...           mode picker, host setup, client discovery, login, scanner, admin
```

## Status

Working end to end on real hardware (a Vivo V2135 / Android 13 host and an
iPhone 17 client): mode pick → host setup → serve + discover → sign in → role
home, with scanning, top-ups, members, menu planning, the purchase schedule,
expenses and refunds all functional, plus the desktop web admin served by the
host.

Since then: four themes with light/dark and motion, first-run admin setup,
per-host saved logins, and `.xlsx` / `.tiffin` export and restore.

Known gaps:

- The Android offline hotspot has not been exercised on real hardware; OEM
  behaviour for `LocalOnlyHotspot` varies.
- Android release signing still uses the debug keystore.
- No on-device performance profiling yet.
- An iPhone can act as host, but only while the app is on screen — iOS will
  not let it serve in the background. The app says so rather than pretending
  otherwise. Host on Android for real shifts.
