import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/logging.dart';

/// Keeps the host process (and its embedded HTTP server) alive when the app is
/// backgrounded, by running an Android foreground service with a persistent
/// notification (PRD §13.3). Android otherwise kills the process mid-shift and
/// silently drops every client.
///
/// The service's task isolate does no work — the server runs in the main
/// isolate, and the only thing needed here is for Android to keep that process
/// resident. `eventAction: nothing()` means [_HostTaskHandler.onRepeatEvent]
/// never fires.
class HostKeepAlive {
  final _log = log('keepalive');
  bool _initialized = false;

  void _ensureInitialized() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tiffin_host',
        channelName: 'Canteen host server',
        channelDescription:
            'Shown while this device is serving the canteen on the LAN.',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// Returns true if the service is running (or was already). A denied
  /// notification permission is logged but not fatal — the service can still
  /// start, it just can't show its notification on Android 13+.
  Future<bool> start({required String appName, required int port}) async {
    _ensureInitialized();

    final permission =
        await FlutterForegroundTask.requestNotificationPermission();
    if (permission != NotificationPermission.granted) {
      _log.warning(
        'notification permission=$permission — the host may still be killed '
        'when backgrounded; ask the operator to allow notifications',
      );
    }

    if (await FlutterForegroundTask.isRunningService) return true;

    final result = await FlutterForegroundTask.startService(
      notificationTitle: '$appName — host running',
      notificationText:
          'Serving on port $port. Keep this device on and on Wi-Fi.',
      callback: startHostKeepAliveCallback,
    );

    if (result is ServiceRequestFailure) {
      _log.severe('foreground service failed to start', result.error);
      return false;
    }
    _log.info('foreground service started');
    return true;
  }

  Future<void> stop() async {
    _ensureInitialized();
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
    _log.info('foreground service stopped');
  }
}

/// Top-level entry point the plugin spawns in the service isolate.
@pragma('vm:entry-point')
void startHostKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_HostTaskHandler());
}

class _HostTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
