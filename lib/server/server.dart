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

/// The embedded server (PRD §13.4). One `shelf` pipeline, but bound to **two
/// listeners** so the two audiences never fight over TLS:
///
///  * plain **HTTP on [port]** — always. This is what client-mode app instances
///    talk to (PRD §13.6: "plain HTTP between two native app instances is
///    acceptable" on the closed LAN), and what `nsd` advertises.
///  * **HTTPS on [port] + 1** — only when a self-signed cert exists. This is the
///    optional encrypted surface for a desktop browser (PRD §13.6); a client
///    never needs it, so it can't trip over the untrusted-cert error.
///
/// Both listeners serve the same handler: `/api/...` JSON plus the static
/// HTML/JS desktop-admin bundle.
class HostServer {
  HostServer(this._container, {this.staticRoot});

  final HostContainer _container;

  /// Directory holding the desktop-admin web bundle. When null, only `/api` is
  /// served. Set before [start] (the host console materializes the bundle from
  /// Flutter assets first).
  String? staticRoot;

  final _log = log('server');
  HttpServer? _http;
  HttpServer? _https;

  bool get isRunning => _http != null;

  /// The port client apps connect to (plain HTTP).
  int? get port => _http?.port;
  int? get httpPort => _http?.port;

  /// The encrypted desktop-browser port, or null when no cert is loaded.
  int? get httpsPort => _https?.port;

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

  /// Binds plain HTTP on [port] (always) and, when [securityContext] is given,
  /// HTTPS on [port] + 1 as well.
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

    _http = await shelf_io.serve(handler, bind, port);
    _http!.autoCompress = true;
    _log.info(
        'http listening on http://${_http!.address.address}:${_http!.port}'
        '  static=${staticRoot ?? '(none)'}');

    if (securityContext != null) {
      try {
        _https = await shelf_io.serve(handler, bind, port + 1,
            securityContext: securityContext);
        _https!.autoCompress = true;
        _log.info('https listening on '
            'https://${_https!.address.address}:${_https!.port}');
      } catch (e, st) {
        // HTTP is up and clients are fine — the encrypted desktop port is
        // optional, so log and carry on rather than fail the whole start.
        _log.severe('https listener failed to bind on ${port + 1}', e, st);
        _https = null;
      }
    }
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    await _https?.close(force: true);
    _http = null;
    _https = null;
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
