import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../ui/theme/appearance.dart';
import '../ui/theme/theme_catalog.dart';
import 'providers.dart';

final appearanceStoreProvider = Provider<AppearanceStore>(
    (ref) => AppearanceStore(ref.read(sharedPreferencesProvider)));

/// This device's own appearance choice, persisted immediately so the app opens
/// on the chosen theme rather than flashing the default first.
class AppearanceController extends Notifier<Appearance> {
  @override
  Appearance build() => ref.read(appearanceStoreProvider).read();

  Future<void> setTheme(TiffinThemeId theme) =>
      _save(state.copyWith(theme: theme));

  Future<void> setMode(ThemeMode mode) => _save(state.copyWith(mode: mode));

  Future<void> setMotion({required bool enabled}) =>
      _save(state.copyWith(motion: enabled));

  Future<void> _save(Appearance next) async {
    state = next;
    await ref.read(appearanceStoreProvider).write(next);
  }
}

final deviceAppearanceProvider =
    NotifierProvider<AppearanceController, Appearance>(
        AppearanceController.new);

/// The host's policy, fetched from the public endpoint so it applies before
/// anyone signs in.
///
/// Any failure resolves to [AppearancePolicy.none] rather than propagating: a
/// device that cannot reach its host yet must still render *something*, and
/// falling back to the device's own choice is the honest default. A host that
/// is enforcing will be obeyed the moment it is reachable.
final hostGreetingProvider = FutureProvider<HostGreeting>((ref) async {
  if (ref.watch(currentModeProvider) == null) return HostGreeting.unknown;
  try {
    final Backend backend = ref.watch(backendProvider);
    return await backend.greeting();
  } catch (_) {
    return HostGreeting.unknown;
  }
});

/// The host's appearance policy, from the same pre-login greeting.
final appearancePolicyProvider = Provider<AppearancePolicy>((ref) =>
    ref.watch(hostGreetingProvider).asData?.value.appearance ??
    AppearancePolicy.none);

/// What this device actually renders: the host's choice when it enforces one,
/// otherwise the device's own.
final effectiveAppearanceProvider = Provider<Appearance>((ref) {
  final device = ref.watch(deviceAppearanceProvider);
  return ref.watch(appearancePolicyProvider).resolve(device);
});

/// True when the host is dictating appearance, so the Appearance controls can
/// say so instead of silently discarding taps.
final appearanceIsEnforcedProvider =
    Provider<bool>((ref) => ref.watch(appearancePolicyProvider).enforced);
