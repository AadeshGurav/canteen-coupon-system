.PHONY: setup gen watch run apk analyze test format clean doctor

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

# Run on a connected Android device / emulator.
run:
	flutter run

# Build the release APK (PRD §13.8: Android only for v1).
apk:
	flutter build apk --release

analyze:
	dart analyze --fatal-infos

test:
	flutter test

format:
	dart format lib test

doctor:
	flutter doctor -v

clean:
	flutter clean
	rm -f lib/**/*.g.dart
