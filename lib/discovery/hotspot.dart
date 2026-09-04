import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';

/// The credentials for the router-less Wi-Fi the host device is broadcasting.
class HotspotInfo {
  const HotspotInfo({
    required this.ssid,
    required this.passphrase,
    required this.host,
  });

  final String ssid;
  final String passphrase;

  /// The host's fixed address on a local-only hotspot (`192.168.49.1`).
  final String host;

  /// Standard "join this Wi-Fi" QR payload — the platform camera and most QR
  /// apps offer a one-tap connect from it.
  String get joinQr => 'WIFI:T:WPA;S:$ssid;P:$passphrase;;';
}

class HotspotState {
  const HotspotState({
    this.info,
    this.busy = false,
    this.error,
    this.supported = true,
  });

  final HotspotInfo? info;
  final bool busy;
  final String? error;

  /// False on iOS and pre-Android-8; the Hosting screen hides the section.
  final bool supported;

  bool get active => info != null;

  HotspotState copyWith({
    HotspotInfo? info,
    bool clearInfo = false,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? supported,
  }) =>
      HotspotState(
        info: clearInfo ? null : (info ?? this.info),
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        supported: supported ?? this.supported,
      );
}

/// Drives the native `tiffin/hotspot` channel (see MainActivity.kt). iOS has no
/// equivalent API, so there it just reports `supported == false`.
class HotspotController extends Notifier<HotspotState> {
  static const _channel = MethodChannel('tiffin/hotspot');
  final _log = log('hotspot');

  @override
  HotspotState build() {
    _probeSupport();
    return const HotspotState();
  }

  Future<void> _probeSupport() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isSupported') ?? false;
      state = state.copyWith(supported: ok);
    } catch (_) {
      state = state.copyWith(supported: false);
    }
  }

  Future<void> start() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('start');
      if (m == null) throw StateError('empty hotspot response');
      state = state.copyWith(
        busy: false,
        info: HotspotInfo(
          ssid: (m['ssid'] ?? '') as String,
          passphrase: (m['passphrase'] ?? '') as String,
          host: (m['host'] ?? '192.168.49.1') as String,
        ),
      );
      _log.info('hotspot up: ${state.info!.ssid}');
    } on PlatformException catch (e) {
      state = state.copyWith(busy: false, error: e.message ?? e.code);
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  Future<void> stop() async {
    state = state.copyWith(busy: true);
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {/* best effort */}
    state = state.copyWith(busy: false, clearInfo: true);
  }
}

final hotspotProvider =
    NotifierProvider<HotspotController, HotspotState>(HotspotController.new);
