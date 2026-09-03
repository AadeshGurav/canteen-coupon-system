import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import '../core/logging.dart';
import 'host_container.dart';
import 'middleware.dart';
import 'routes_auth.dart';
import 'routes_members.dart';
import 'routes_planning.dart';

/// The embedded HTTP server (PRD §13.4). One `shelf` pipeline serving two
/// audiences from the same host process and the same service layer:
///
///  * `/api/...`  — JSON, consumed by client-mode app instances on the LAN.
///  * everything else — a static HTML/JS desktop-admin bundle (bulk data entry
///    on a real keyboard). Scanning is native-app-only, never here (PRD §13.6).
class HostServer {
  HostServer(this._container, {this.staticRoot});

  final HostContainer _container;

  /// Directory holding the desktop-admin web bundle. When null, only `/api` is
  /// served. Set before [start] (the host console materializes the bundle from
  /// Flutter assets first).
  String? staticRoot;

  final _log = log('server');
  HttpServer? _http;

  bool get isRunning => _http != null;
  int? get port => _http?.port;
  String? get address => _http?.address.address;

  /// Non-loopback IPv4 addresses this device is reachable at — for showing the
  /// operator the exact URL to open a desktop browser to.
  static Future<List<String>> lanAddresses() async {
    final out = <String>[];
    for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final addr in ni.addresses) {
        if (!addr.isLoopback) out.add(addr.address);
      }
    }
    return out;
  }

  /// Starts listening on [bind]:[port]. If [securityContext] is given the
  /// server speaks HTTPS with that certificate (PRD §13.6's self-signed cert).
  Future<void> start({
    String bind = '0.0.0.0',
    required int port,
    SecurityContext? securityContext,
  }) async {
    if (_http != null) return;

    final handler = const Pipeline()
        .addMiddleware(corsMiddleware())
        .addMiddleware(errorMiddleware())
        .addHandler(_root());

    _http = securityContext == null
        ? await shelf_io.serve(handler, bind, port)
        : await shelf_io.serve(handler, bind, port,
            securityContext: securityContext);
    _http!.autoCompress = true;
    _log.info('listening on ${securityContext == null ? 'http' : 'https'}://'
        '${_http!.address.address}:${_http!.port}  static=${staticRoot ?? '(none)'}');
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _log.info('stopped');
  }

  Handler _root() {
    // Public routes (login, branding) are tried first; anything they don't
    // match falls through to the session-guarded routers.
    final authedApi = const Pipeline()
        .addMiddleware(requireSessionMiddleware(_container.auth))
        .addHandler(_composed([
          authedAuthRoutes(_container),
          memberAndLedgerRoutes(_container),
          planningRoutes(_container),
        ]));

    final apiHandler = _composedHandlers([
      publicRoutes(_container).call,
      authedApi,
    ]);

    final apiRouter = Router(notFoundHandler: _notFound)
      ..mount('/api/', apiHandler)
      ..mount('/api', apiHandler);

    final stages = <Handler>[
      apiRouter.call,
      if (staticRoot != null)
        createStaticHandler(staticRoot!,
            defaultDocument: 'index.html', listDirectories: false),
    ];
    return Cascade().add(_composedHandlers(stages)).handler;
  }

  /// Try each router in order; the first non-404 response wins.
  Handler _composed(List<Router> routers) =>
      _composedHandlers(routers.map((r) => r.call).toList());

  Handler _composedHandlers(List<Handler> handlers) {
    return (Request request) async {
      for (final handler in handlers) {
        final response = await handler(request);
        if (response.statusCode != 404) return response;
      }
      return _notFound(request);
    };
  }

  Response _notFound(Request request) =>
      Response.notFound('{"error":"not_found","message":"No such endpoint."}',
          headers: {'content-type': 'application/json'});
}
