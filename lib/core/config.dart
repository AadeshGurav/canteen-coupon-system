/// Compile-time-ish constants and their runtime-configurable counterparts.
///
/// CLAUDE.md §7 / PRD §6.8: anything an operator might reasonably change lives
/// in the `settings` row of the database (see `SettingsService`), NOT here.
/// This file holds only values that are genuinely fixed for a given build:
/// the discovery service type, the default port, wire-format constants.
class AppConfig {
  const AppConfig._();

  /// mDNS/Bonjour service type the host advertises and the client scans for
  /// (PRD §13.5).
  static const String discoveryServiceType = '_canteen._tcp';

  /// Default TCP port for the embedded server. The host operator can override
  /// it in the mode picker; discovery carries the actual chosen port so
  /// clients never assume this value.
  static const int defaultServerPort = 8710;

  /// Bearer token header the client sends and the server reads.
  static const String authHeader = 'Authorization';
  static const String authScheme = 'Bearer';

  /// How often the client dashboard polls `GET /notifications` (PRD §6.5.2).
  static const Duration notificationPollInterval = Duration(seconds: 45);

  /// Rotating log file budget (the admin's primary debugging tool, PRD §7).
  static const int logFileMaxBytes = 5 * 1000 * 1000;
  static const int logFileBackupCount = 5;
}
