import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import '../core/config.dart';
import '../core/logging.dart';

/// A host found on the LAN (PRD §13.5).
class DiscoveredHost {
  const DiscoveredHost(
      {required this.name, required this.host, required this.port});

  final String name;
  final String host;
  final int port;

  String get baseUrl => 'http://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredHost && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Host mode: publish this device as `_canteen._tcp` so clients find it without
/// anyone typing an IP (PRD §13.5).
///
/// Robust by design: the first `register` may fail (no Wi-Fi yet, or the OS
/// mDNS stack is briefly unavailable). Rather than give up, it keeps retrying
/// on a timer until it sticks, and re-registers if [advertise] is called again
/// with new details. [isAdvertising] tells the caller whether a client can
/// currently discover this host.
class HostAdvertiser {
  final _log = log('discovery');
  static const _retryEvery = Duration(seconds: 15);

  nsd.Registration? _registration;
  Timer? _retry;
  String? _name;
  int? _port;

  bool get isAdvertising => _registration != null;

  /// Registers now; on failure keeps retrying in the background until it
  /// succeeds or [stop] is called. Returns once the first attempt settles, so
  /// the caller can reflect an immediate success/failure in the UI.
  Future<void> advertise({required String name, required int port}) async {
    _name = name;
    _port = port;
    _retry?.cancel();
    await _unregister();
    await _tryRegister();
  }

  Future<void> _tryRegister() async {
    final name = _name, port = _port;
    if (name == null || port == null) return;
    try {
      _registration = await nsd.register(
        nsd.Service(
            name: name, type: AppConfig.discoveryServiceType, port: port),
      );
      _retry?.cancel();
      _retry = null;
      _log.info(
          'advertising "$name" on ${AppConfig.discoveryServiceType}:$port');
    } catch (e) {
      _log.warning(
          'advertise failed, will retry in ${_retryEvery.inSeconds}s', e);
      _retry ??= Timer.periodic(_retryEvery, (_) {
        if (!isAdvertising) unawaited(_tryRegister());
      });
    }
  }

  Future<void> _unregister() async {
    final reg = _registration;
    _registration = null;
    if (reg != null) {
      try {
        await nsd.unregister(reg);
      } catch (_) {/* best effort */}
    }
  }

  Future<void> stop() async {
    _retry?.cancel();
    _retry = null;
    _name = _port = null;
    await _unregister();
    _log.info('stopped advertising');
  }
}

/// Client mode: browse for hosts continuously. Emits the current set on every
/// change so the UI just rebuilds a list.
///
/// `NsdManager` on Android is known to go quiet after a while (no error, just
/// no more callbacks). To survive that — and Wi-Fi drops, sleep/wake, and
/// roaming — discovery is torn down and restarted on a timer, and [restart]
/// can be called on app-resume or a manual "search again". The results stream
/// stays open across every re-arm.
class HostBrowser {
  final _log = log('discovery');
  static const _rearmEvery = Duration(seconds: 25);

  /// A host stays in the list this long after it was last seen — long enough to
  /// ride through a re-arm blip or one missed mDNS round, short enough that a
  /// host that's genuinely gone disappears.
  static const _staleAfter = Duration(seconds: 40);

  final _controller = StreamController<List<DiscoveredHost>>.broadcast();
  final Map<DiscoveredHost, DateTime> _seen = {};
  nsd.Discovery? _discovery;
  Timer? _rearm;
  bool _starting = false;
  bool _emittedOnce = false;

  Stream<List<DiscoveredHost>> get hosts => _controller.stream;

  Future<void> start() async {
    if (_discovery != null || _starting) return;
    _starting = true;
    try {
      _discovery = await nsd.startDiscovery(
        AppConfig.discoveryServiceType,
        ipLookupType: nsd.IpLookupType.any,
      );
      _discovery!.addListener(_emit);
      // Push an initial empty list the very first time so the UI shows
      // "searching" rather than nothing; never on a re-arm (would flicker).
      if (!_emittedOnce) _emit();
      _rearm ??= Timer.periodic(_rearmEvery, (_) => _reArm());
      _log.info('discovery started');
    } catch (e) {
      _log.warning('discovery start failed, will retry on next re-arm', e);
      _rearm ??= Timer.periodic(_rearmEvery, (_) => _reArm());
    } finally {
      _starting = false;
    }
  }

  /// Stop + start the OS discovery without disturbing the results stream —
  /// recovers a silently-dead `NsdManager`.
  Future<void> restart() async {
    await _teardownDiscovery();
    await start();
  }

  Future<void> _reArm() async {
    if (_starting) return;
    await _teardownDiscovery();
    await start();
    _emit(); // re-prune the sticky list even if the new scan is slow to report
  }

  void _emit() {
    final now = DateTime.now();
    for (final service in _discovery?.services ?? const <nsd.Service>[]) {
      final host = service.host;
      final port = service.port;
      if (host == null || port == null) continue;
      _seen[DiscoveredHost(
        name: service.name ?? host,
        host: host,
        port: port,
      )] = now;
    }
    _seen.removeWhere((_, at) => now.difference(at) > _staleAfter);
    _emittedOnce = true;
    if (!_controller.isClosed) _controller.add(_seen.keys.toList());
  }

  Future<void> _teardownDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      discovery.removeListener(_emit);
      try {
        await nsd.stopDiscovery(discovery);
      } catch (_) {/* best effort */}
    }
  }

  Future<void> stop() async {
    _rearm?.cancel();
    _rearm = null;
    await _teardownDiscovery();
    _log.info('discovery stopped');
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
