import 'package:flutter/services.dart';

import 'logging.dart';

/// Holds the display on while this device is serving.
///
/// Replaces the `wakelock_plus` package, which pulled in `package_info_plus`
/// — a plugin that no longer compiles under this Flutter's Kotlin setup, and
/// which this app had no other use for. All that was needed was one window
/// flag on Android and the idle timer on iOS, so it lives on the same
/// MethodChannel pattern the hotspot control already uses.
class ScreenAwake {
  const ScreenAwake();

  static const _channel = MethodChannel('tiffin/screen');

  /// Never throws: a phone that won't hold its screen on is a comfort problem,
  /// not a reason to fail whatever the caller was doing.
  Future<void> set({required bool enabled}) async {
    try {
      await _channel.invokeMethod<bool>('setKeepAwake', {'enabled': enabled});
    } on PlatformException catch (e) {
      log('screen').warning('could not set keep-awake', e);
    } on MissingPluginException {
      // Desktop or a test host — nothing to hold awake.
    }
  }
}
