import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_mode.dart';
import '../core/config.dart';
import '../core/logging.dart';
import '../data/backend.dart';
import '../data/client_backend.dart';
import '../data/host_backend.dart';
import '../data/local/database.dart';
import '../data/remote/api_client.dart';
import '../discovery/discovery.dart';
import '../domain/ops.dart';
import '../server/host_container.dart';
import '../server/host_keep_alive.dart';
import '../server/server.dart';
import '../server/tls.dart';
import '../server/web_admin_assets.dart';
import 'bootstrap.dart';
export 'bootstrap.dart' show appModeStoreProvider, sharedPreferencesProvider;

/// The chosen mode for this install. `null` → the mode picker.
///
/// Held in a [Notifier] (not a plain Provider over the store) so [set]/[clear]
/// update the UI immediately — the store is `overrideWithValue`, so invalidating
/// it notifies nobody, which is why "Run as host" used to need an app restart.
class ModeController extends Notifier<AppMode?> {
  @override
  AppMode? build() => ref.read(appModeStoreProvider).read();

  Future<void> set(AppMode mode) async {
    await ref.read(appModeStoreProvider).write(mode);
    state = mode;
  }

  Future<void> clear() async {
    await ref.read(appModeStoreProvider).clear();
    // Drop any host/client resources and session tied to the old mode.
    ref.invalidate(sessionProvider);
    ref.invalidate(selectedHostProvider);
    state = null;
  }
}

final currentModeProvider =
    NotifierProvider<ModeController, AppMode?>(ModeController.new);

// ===========================================================================
// Host mode
// ===========================================================================

/// The host's own document directory (SQLite file + generated artifacts).
final _documentsDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
});

/// The host database — one per process, closed when the provider is disposed.
final hostDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The wired-up host container. Also runs the one-time admin bootstrap and
/// stashes any generated first-run password for the console to show once.
final hostContainerProvider = FutureProvider<HostContainer>((ref) async {
  final documentsDir = await ref.watch(_documentsDirProvider.future);
  // Host mode writes its log to a file (the admin's debugging tool, PRD §7).
  await AppLogger.configure(toFile: true);

  final container = HostContainer.create(
    db: ref.watch(hostDatabaseProvider),
    documentsDir: documentsDir,
    sessionTtl: const Duration(hours: _sessionTtlHours),
  );
  final generated = await container.bootstrap(
    initialAdminUsername: 'admin',
    initialAdminPassword: null,
  );
  ref.read(generatedAdminPasswordProvider.notifier).state = generated;
  return container;
});

/// Set once by [hostContainerProvider] if a first-run admin password was
/// generated — the host console surfaces it exactly once (never logged).
final generatedAdminPasswordProvider = StateProvider<String?>((_) => null);

const int _sessionTtlHours = 12;

final hostServerProvider = Provider<HostServer>((ref) {
  final container = ref.watch(hostContainerProvider).requireValue;
  final server = HostServer(container);
  ref.onDispose(server.stop);
  return server;
});

/// Copies the bundled desktop-admin web files to a real directory `shelf_static`
/// can serve, once. Returns its path.
final webAdminDirProvider = FutureProvider<String>((ref) async {
  final documentsDir = await ref.watch(_documentsDirProvider.future);
  return WebAdminAssets(documentsDir).materialize();
});

final hostKeepAliveProvider = Provider<HostKeepAlive>((ref) {
  final keepAlive = HostKeepAlive();
  ref.onDispose(keepAlive.stop);
  return keepAlive;
});

final hostAdvertiserProvider = Provider<HostAdvertiser>((ref) {
  final advertiser = HostAdvertiser();
  ref.onDispose(advertiser.stop);
  return advertiser;
});

/// LAN URLs a desktop browser can open once the server is running — the plain
/// HTTP ones always, plus the HTTPS ones when a cert is loaded (§13.6).
class LanUrls {
  const LanUrls({required this.http, required this.https});
  final List<String> http;
  final List<String> https;
}

final lanUrlsProvider = FutureProvider.autoDispose<LanUrls>((ref) async {
  if (!ref.watch(hostRunningProvider)) {
    return const LanUrls(http: [], https: []);
  }
  final server = ref.read(hostServerProvider);
  final addrs = await HostServer.lanAddresses();
  return LanUrls(
    http: [for (final a in addrs) 'http://$a:${server.httpPort}/'],
    https: server.httpsPort == null
        ? const []
        : [for (final a in addrs) 'https://$a:${server.httpsPort}/'],
  );
});

/// True while the embedded LAN server is listening. Written by
/// [HostServingController]; read by [lanUrlsProvider] and [hostWakelockProvider].
final hostRunningProvider = StateProvider<bool>((_) => false);

/// Owns the LAN server lifecycle: start/stop, mDNS advertise, the Android
/// keep-alive service, and the optional self-signed cert. A host *serves* — so
/// [ModeGate] calls [ensureStarted] the moment the database is ready, before
/// anyone signs in. The admin manages it afterwards from Admin → Hosting; it is
/// no longer a pre-login console (that surface is gone).
class HostServingState {
  const HostServingState({
    this.running = false,
    this.busy = false,
    this.certExpiry,
    this.discoveryOk = true,
    this.lastError,
  });

  final bool running;
  final bool busy;

  /// `yyyy-mm-dd` of the loaded cert, or null when none has been generated.
  final String? certExpiry;

  /// False once an advertise attempt has failed (no Wi-Fi) — clients then need
  /// the manual "Connect by IP" path.
  final bool discoveryOk;
  final String? lastError;

  HostServingState copyWith({
    bool? running,
    bool? busy,
    String? certExpiry,
    bool? discoveryOk,
    String? lastError,
    bool clearError = false,
  }) =>
      HostServingState(
        running: running ?? this.running,
        busy: busy ?? this.busy,
        certExpiry: certExpiry ?? this.certExpiry,
        discoveryOk: discoveryOk ?? this.discoveryOk,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class HostServingController extends Notifier<HostServingState> {
  @override
  HostServingState build() => const HostServingState();

  bool _transitioning = false;

  Future<String> get _docsDir async =>
      (await ref.read(hostContainerProvider.future)).artifacts.baseDir;

  /// Idempotent — safe to call on every rebuild of [ModeGate].
  Future<void> ensureStarted() async {
    if (state.running || _transitioning) return;
    await start();
  }

  Future<void> start() async {
    if (state.running || _transitioning) return;
    _transitioning = true;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final tls = SelfSignedTls(await _docsDir);
      final server = ref.read(hostServerProvider)
        ..staticRoot = await ref.read(webAdminDirProvider.future);
      await server.start(
        port: AppConfig.defaultServerPort,
        securityContext: tls.securityContext(),
      );
      ref.read(hostRunningProvider.notifier).state = true;
      ref.invalidate(lanUrlsProvider);
      state = state.copyWith(running: true, busy: false);
      unawaited(_publishAndKeepAlive());
    } catch (e) {
      state = state.copyWith(busy: false, lastError: '$e');
    } finally {
      _transitioning = false;
    }
  }

  Future<void> _publishAndKeepAlive() async {
    final container = await ref.read(hostContainerProvider.future);
    final appName = await container.settings.readAppName();
    try {
      await ref
          .read(hostAdvertiserProvider)
          .advertise(name: appName, port: AppConfig.defaultServerPort)
          .timeout(const Duration(seconds: 8));
      state = state.copyWith(discoveryOk: true);
    } catch (_) {
      state = state.copyWith(discoveryOk: false);
    }
    try {
      await ref
          .read(hostKeepAliveProvider)
          .start(appName: appName, port: AppConfig.defaultServerPort);
    } catch (_) {
      // Notification permission etc. — logged inside HostKeepAlive.
    }
  }

  Future<void> stop() async {
    if (_transitioning) return;
    _transitioning = true;
    state = state.copyWith(busy: true);
    try {
      await ref.read(hostKeepAliveProvider).stop().catchError((_) {});
      await ref
          .read(hostAdvertiserProvider)
          .stop()
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
      await ref.read(hostServerProvider).stop();
    } finally {
      ref.read(hostRunningProvider.notifier).state = false;
      ref.invalidate(lanUrlsProvider);
      state = state.copyWith(running: false, busy: false);
      _transitioning = false;
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> generateCert() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final expiry = await SelfSignedTls(await _docsDir).generate();
      state = state.copyWith(
        busy: false,
        certExpiry: expiry.toLocal().toString().split(' ').first,
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastError: '$e');
    }
  }
}

final hostServingProvider =
    NotifierProvider<HostServingController, HostServingState>(
        HostServingController.new);

/// Holds the screen awake for as long as the host server is running (PRD §13.3).
///
/// Watched from [ModeGate] in host mode rather than the host console — the
/// console is disposed once the host device signs in, but the server keeps
/// running underneath it. On Android this pins the display; on iOS it disables
/// the idle timer (the only lever the platform gives — it cannot keep a
/// backgrounded app alive).
final hostWakelockProvider = Provider<void>((ref) {
  final running = ref.watch(hostRunningProvider);
  WakelockPlus.toggle(enable: running);
  ref.onDispose(() => WakelockPlus.disable());
});

// ===========================================================================
// Client mode
// ===========================================================================

final hostBrowserProvider = Provider<HostBrowser>((ref) {
  final browser = HostBrowser();
  ref.onDispose(browser.dispose);
  return browser;
});

final discoveredHostsProvider = StreamProvider<List<DiscoveredHost>>((ref) {
  final browser = ref.watch(hostBrowserProvider);
  browser.start();
  return browser.hosts;
});

/// The host the operator picked from the discovery list.
final selectedHostProvider = StateProvider<DiscoveredHost?>((_) => null);

final _apiClientProvider = Provider<ApiClient?>((ref) {
  final host = ref.watch(selectedHostProvider);
  if (host == null) return null;
  final client = ApiClient(baseUrl: host.baseUrl);
  ref.onDispose(client.close);
  return client;
});

// ===========================================================================
// The one seam every screen depends on
// ===========================================================================

/// Resolves to a [Backend] once the mode's prerequisites are ready (host
/// container built, or a client host picked). Throws otherwise so the UI shows
/// a clear state rather than a half-wired screen.
final backendProvider = Provider<Backend>((ref) {
  final mode = ref.watch(currentModeProvider);
  switch (mode) {
    case AppMode.host:
      final container = ref.watch(hostContainerProvider).requireValue;
      return HostBackend(container);
    case AppMode.client:
      final api = ref.watch(_apiClientProvider);
      if (api == null) {
        throw StateError('No host selected yet');
      }
      return ClientBackend(api);
    case null:
      throw StateError('Mode not chosen');
  }
});

// ===========================================================================
// Session
// ===========================================================================

class SessionController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  Future<void> login(String username, String password) async {
    state = await ref.read(backendProvider).login(username, password);
  }

  Future<void> logout() async {
    try {
      await ref.read(backendProvider).logout();
    } finally {
      state = null;
    }
  }
}

final sessionProvider =
    NotifierProvider<SessionController, AuthSession?>(SessionController.new);

/// Polls `GET /notifications` on a cadence (PRD §6.5.2) once signed in.
final notificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) async* {
  final backend = ref.watch(backendProvider);
  if (ref.watch(sessionProvider) == null) {
    yield const [];
    return;
  }
  while (true) {
    try {
      yield await backend.listNotifications();
    } catch (_) {
      yield const [];
    }
    await Future<void>.delayed(AppConfig.notificationPollInterval);
  }
});

/// Absolute path of a rendered member QR, for a screen that wants to reuse the
/// file rather than hold bytes. (Currently unused by the UI; kept for the
/// print/share flow.)
String memberQrCachePath(String documentsDir, String codeId) =>
    p.join(documentsDir, 'qr', '$codeId.png');
