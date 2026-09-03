import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import '../core/config.dart';
import '../core/logging.dart';

/// A host found on the LAN (PRD §13.5).
class DiscoveredHost {
  const DiscoveredHost({required this.name, required this.host, required this.port});

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

/// Host mode: publish this device as `_canteen._tcp` so clients can find it
/// without anyone typing an IP (PRD §13.5).
class HostAdvertiser {
  final _log = log('discovery');
  nsd.Registration? _registration;

  Future<void> advertise({required String name, required int port}) async {
    await stop();
    _registration = await nsd.register(
      nsd.Service(
        name: name,
        type: AppConfig.discoveryServiceType,
        port: port,
      ),
    );
    _log.info('advertising "$name" on ${AppConfig.discoveryServiceType}:$port');
  }

  Future<void> stop() async {
    final reg = _registration;
    _registration = null;
    if (reg != null) {
      await nsd.unregister(reg);
      _log.info('stopped advertising');
    }
  }
}

/// Client mode: browse for hosts. Emits the current set on every change so the
/// UI can just rebuild a list; re-resolves automatically when a host drops and
/// reappears (PRD §13.5).
class HostBrowser {
  final _log = log('discovery');
  final _controller = StreamController<List<DiscoveredHost>>.broadcast();
  nsd.Discovery? _discovery;

  Stream<List<DiscoveredHost>> get hosts => _controller.stream;

  Future<void> start() async {
    await stop();
    _discovery = await nsd.startDiscovery(
      AppConfig.discoveryServiceType,
      ipLookupType: nsd.IpLookupType.any,
    );
    _discovery!.addListener(_emit);
    _emit();
    _log.info('discovery started');
  }

  void _emit() {
    final discovery = _discovery;
    if (discovery == null) return;
    final found = <DiscoveredHost>[];
    for (final service in discovery.services) {
      final host = service.host;
      final port = service.port;
      if (host == null || port == null) continue;
      found.add(DiscoveredHost(
        name: service.name ?? host,
        host: host,
        port: port,
      ));
    }
    _controller.add(found);
  }

  Future<void> stop() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      discovery.removeListener(_emit);
      await nsd.stopDiscovery(discovery);
      _log.info('discovery stopped');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
