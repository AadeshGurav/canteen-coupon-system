.PHONY: setup gen watch run apk ios analyze test format clean doctor schema icons

# Zero-touch setup (CLAUDE.md §9): one command from a fresh checkout to a
# runnable app.
setup:
	flutter pub get
	dart run build_runner build

# Regenerate codegen output (drift schema, riverpod providers, l10n). Run
# after changing a @DriftDatabase table, a @riverpod provider, or an .arb file.
gen:
	dart run build_runner build

# Same, but rebuilds on save during development.
watch:
	dart run build_runner watch

# Snapshot the current schema and regenerate the migration-test helpers.
# Run this AFTER bumping AppDatabase.schemaVersion and changing a table, so
# test/migration_test.dart can run the real migration against the real
# previous version — the host's database is the only copy of the data.
schema:
	dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
	dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
	dart run drift_dev schema steps drift_schemas/ lib/data/local/schema_versions.dart

# Run on a connected Android device / emulator.
run:
	flutter run

# Build the release APK (PRD §13.8: Android only for v1).
apk:
	flutter build apk --release

# Build the iOS app (needs full Xcode + CocoaPods). Signing is set in Xcode.
ios:
	flutter build ios --release

# Regenerate the per-theme launcher icons from the app's own painter, then
# rebuild the native icon sets. Run after changing a theme's palette or shape.
icons:
	flutter test test/generate_icons_test.dart --tags tool
	dart run flutter_launcher_icons

analyze:
	dart analyze --fatal-infos
	node --check assets/web_admin/app.js

test:
	flutter test --exclude-tags tool

format:
	dart format lib test

doctor:
	flutter doctor -v

clean:
	flutter clean
	rm -f lib/**/*.g.dart
