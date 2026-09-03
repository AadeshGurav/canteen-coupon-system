import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// True once the operator has started the server from the host console.
final hostRunningProvider = StateProvider<bool>((_) => false);

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
