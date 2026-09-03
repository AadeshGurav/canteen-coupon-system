import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// Application logging — a first-class feature, not an afterthought (PRD §7,
/// CLAUDE.md §8). Every scan decision, top-up, refund, and admin action is
/// logged here with enough identifiers to debug without reproducing.
///
/// On the host device the log is also written to a rotating file under the app's
/// documents directory so the admin can read it after the fact. On a client it
/// stays console-only (a client has nothing to debug that the host log won't
/// already show).
class AppLogger {
  AppLogger._();

  static bool _configured = false;
  static IOSink? _fileSink;
  static File? _logFile;

  /// [toFile] should be true only in host mode.
  static Future<void> configure({required bool toFile}) async {
    if (_configured) return;
    _configured = true;

    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      final line = _format(record);
      // stdout is what an operator watching the host device sees on boot.
      // ignore: avoid_print
      print(line);
      _fileSink?.writeln(line);
      if (record.error != null) {
        final errLine = '    error: ${record.error}';
        // ignore: avoid_print
        print(errLine);
        _fileSink?.writeln(errLine);
      }
    });

    if (toFile) {
      await _openFile();
    }
  }

  static String _format(LogRecord r) =>
      '${r.time.toUtc().toIso8601String()} ${r.level.name.padRight(7)} '
      '${r.loggerName} ${r.message}';

  static Future<void> _openFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(dir.path, 'logs'));
    await logsDir.create(recursive: true);
    final file = File(p.join(logsDir.path, 'app.log'));

    await _rotateIfNeeded(file);
    _logFile = file;
    _fileSink = file.openWrite(mode: FileMode.append);
  }

  static Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) return;
    if (await file.length() < AppConfig.logFileMaxBytes) return;

    for (var i = AppConfig.logFileBackupCount - 1; i >= 1; i--) {
      final src = File('${file.path}.$i');
      if (await src.exists()) await src.rename('${file.path}.${i + 1}');
    }
    await file.rename('${file.path}.1');
  }

  /// Absolute path of the current log file, or null on a client.
  static String? get logFilePath => _logFile?.path;

  static Future<void> dispose() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
  }
}

/// Convenience: `log('scan').info(...)` — one named logger per domain, matching
/// the Python build's `logging.getLogger(__name__)` convention.
Logger log(String domain) => Logger(domain);
