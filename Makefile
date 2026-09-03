.PHONY: setup gen watch run apk analyze test format clean doctor

# Zero-touch setup (CLAUDE.md §9): one command from a fresh checkout to a
# runnable app.
setup:
	flutter pub get
	dart run build_runner build --delete-conflicting-outputs

# Regenerate codegen output (drift schema, riverpod providers, l10n). Run
# after changing a @DriftDatabase table, a @riverpod provider, or an .arb file.
gen:
	dart run build_runner build --delete-conflicting-outputs

# Same, but rebuilds on save during development.
watch:
	dart run build_runner watch --delete-conflicting-outputs

# Run on a connected Android device / emulator.
run:
	flutter run

# Build the release APK (PRD §13.8: Android only for v1).
apk:
	flutter build apk --release

analyze:
	dart analyze
	dart run custom_lint

test:
	flutter test

format:
	dart format lib test

doctor:
	flutter doctor -v

clean:
	flutter clean
	rm -f lib/**/*.g.dart
