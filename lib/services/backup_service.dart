import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart';

/// What a `.tiffin` file says about itself.
class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.encrypted,
    required this.rowCounts,
    this.salt,
    this.nonce,
  });

  factory BackupManifest.fromJson(Map<String, dynamic> j) => BackupManifest(
        schemaVersion: (j['schemaVersion'] as num).toInt(),
        appVersion: j['appVersion'] as String? ?? 'unknown',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0),
        encrypted: j['encrypted'] as bool? ?? false,
        rowCounts: (j['rowCounts'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        salt: j['salt'] as String?,
        nonce: j['nonce'] as String?,
      );

  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final bool encrypted;

  /// Per-table counts, so a restore can report what it actually put back
  /// instead of a bare "done".
  final Map<String, int> rowCounts;

  final String? salt;
  final String? nonce;

  int get totalRows => rowCounts.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'createdAt': createdAt.toIso8601String(),
        'encrypted': encrypted,
        'rowCounts': rowCounts,
        if (salt != null) 'salt': salt,
        if (nonce != null) 'nonce': nonce,
      };
}

/// Full-fidelity backup and restore — the supported way to move a canteen to a
/// new phone.
///
/// The container is a zip holding a manifest and a SQLite snapshot taken with
/// `VACUUM INTO`, which produces a consistent copy without closing the live
/// database or reasoning about WAL state.
///
/// A passphrase is optional and offered prominently, not forced: the file
/// carries member names and password hashes, but a mandatory passphrase turns
/// "forgot it" into permanent data loss, and losing the data is the worse
/// failure of the two.
class BackupService {
  BackupService(
    this._db, {
    required this.appVersion,
    required this.workingDirectory,
  });

  final AppDatabase _db;
  final String appVersion;

  /// Where the temporary snapshot is written. Injected rather than resolved
  /// from path_provider so this stays a plain service a test can drive.
  final Directory workingDirectory;
  final _log = log('backup');

  static const manifestEntry = 'manifest.json';
  static const databaseEntry = 'tiffin.sqlite';
  static const fileExtension = 'tiffin';

  /// Bumping this rejects files a newer app wrote, rather than letting an
  /// older app misread them.
  static const formatVersion = 1;

  Future<List<int>> export({String? passphrase}) async {
    final counts = await _rowCounts();
    final snapshot = await _snapshot();

    try {
      var bytes = await snapshot.readAsBytes();
      String? salt;
      String? nonce;

      if (passphrase != null && passphrase.isNotEmpty) {
        final saltBytes = _randomBytes(16);
        final nonceBytes = _randomBytes(12);
        bytes = _encrypt(bytes, passphrase, saltBytes, nonceBytes);
        salt = base64Encode(saltBytes);
        nonce = base64Encode(nonceBytes);
      }

      final manifest = BackupManifest(
        schemaVersion: _db.schemaVersion,
        appVersion: appVersion,
        createdAt: DateTime.now().toUtc(),
        encrypted: salt != null,
        rowCounts: counts,
        salt: salt,
        nonce: nonce,
      );

      final archive = Archive();
      final manifestBytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'format': formatVersion,
        ...manifest.toJson(),
      }));
      archive
        ..addFile(
            ArchiveFile(manifestEntry, manifestBytes.length, manifestBytes))
        ..addFile(ArchiveFile(databaseEntry, bytes.length, bytes));

      _log.info('backup_exported rows=${manifest.totalRows} '
          'encrypted=${manifest.encrypted}');
      return ZipEncoder().encode(archive);
    } finally {
      // The snapshot is a second copy of everything; don't leave it lying in
      // the app's documents directory.
      if (snapshot.existsSync()) snapshot.deleteSync();
    }
  }

  String fileName({DateTime? now}) =>
      'tiffin-backup-${DateFormat('yyyy-MM-dd-HHmm').format(now ?? DateTime.now())}'
      '.$fileExtension';

  /// Reads and validates a backup without touching the live database, so the
  /// UI can show what it holds before anyone commits to replacing anything.
  BackupManifest inspect(List<int> bytes) => _open(bytes).$1;

  /// Validates [bytes], decrypts if needed, and writes the database it
  /// contains to [destination].
  ///
  /// Deliberately stops short of swapping the live file: closing and
  /// re-opening the database is the caller's business, and staging first means
  /// a corrupt or wrong-passphrase file fails before anything is destroyed.
  Future<BackupManifest> stageRestore(
    List<int> bytes,
    File destination, {
    String? passphrase,
  }) async {
    final (manifest, payload) = _open(bytes);

    if (manifest.schemaVersion > _db.schemaVersion) {
      throw ValidationException(
        'This backup was made by a newer version of Tiffin '
        '(database v${manifest.schemaVersion}, this app understands '
        'v${_db.schemaVersion}). Update the app first.',
      );
    }

    var data = payload;
    if (manifest.encrypted) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const ValidationException(
            'This backup is password-protected. Enter its password.');
      }
      data = _decrypt(
        payload,
        passphrase,
        base64Decode(manifest.salt!),
        base64Decode(manifest.nonce!),
      );
    }

    if (!_looksLikeSqlite(data)) {
      throw const ValidationException(
          'That file does not contain a readable database.');
    }

    await destination.writeAsBytes(data, flush: true);
    _log.info('backup_staged rows=${manifest.totalRows}');
    return manifest;
  }

  // ---- internals --------------------------------------------------------

  (BackupManifest, Uint8List) _open(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ValidationException('That is not a Tiffin backup file.');
    }

    ArchiveFile? entry(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    final manifestFile = entry(manifestEntry);
    final dbFile = entry(databaseEntry);
    if (manifestFile == null || dbFile == null) {
      throw const ValidationException(
          'That backup is missing part of its contents.');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, dynamic>;
    } catch (_) {
      throw const ValidationException('That backup\'s manifest is unreadable.');
    }

    final format = (json['format'] as num?)?.toInt() ?? 1;
    if (format > formatVersion) {
      throw const ValidationException(
          'That backup uses a newer format. Update the app first.');
    }

    return (
      BackupManifest.fromJson(json),
      Uint8List.fromList(dbFile.content as List<int>)
    );
  }

  /// A consistent copy without stopping the server: SQLite writes the whole
  /// database out itself, so there is no half-written page or stray WAL.
  Future<File> _snapshot() async {
    if (!workingDirectory.existsSync()) {
      workingDirectory.createSync(recursive: true);
    }
    final target = File(p.join(workingDirectory.path,
        'backup-${DateTime.now().microsecondsSinceEpoch}.sqlite'));
    if (target.existsSync()) target.deleteSync();
    // Path is app-generated; quotes are escaped anyway because VACUUM INTO
    // takes a literal, not a bound parameter.
    final escaped = target.path.replaceAll("'", "''");
    await _db.customStatement("VACUUM INTO '$escaped'");
    return target;
  }

  Future<Map<String, int>> _rowCounts() async {
    final counts = <String, int>{};
    for (final table in _db.allTables) {
      final row = await _db
          .customSelect('SELECT COUNT(*) AS n FROM "${table.actualTableName}"')
          .getSingle();
      counts[table.actualTableName] = row.read<int>('n');
    }
    return counts;
  }

  static bool _looksLikeSqlite(Uint8List bytes) {
    const header = 'SQLite format 3';
    if (bytes.length < header.length) return false;
    return String.fromCharCodes(bytes.sublist(0, header.length)) == header;
  }

  Uint8List _randomBytes(int n) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 then AES-GCM, matching the iteration count the
  /// password hashes already use.
  KeyParameter _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, 32));
    return KeyParameter(
        derivator.process(Uint8List.fromList(utf8.encode(passphrase))));
  }

  Uint8List _encrypt(
      Uint8List data, String passphrase, Uint8List salt, Uint8List nonce) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          true,
          AEADParameters(
              _deriveKey(passphrase, salt), 128, nonce, Uint8List(0)));
    return cipher.process(data);
  }

  Uint8List _decrypt(
      Uint8List data, String passphrase, Uint8List salt, Uint8List nonce) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(
              _deriveKey(passphrase, salt), 128, nonce, Uint8List(0)));
    try {
      return cipher.process(data);
    } catch (_) {
      // GCM authentication failing is overwhelmingly a wrong password, and
      // saying so beats surfacing a MAC error to a canteen admin.
      throw const ValidationException(
          'That password does not open this backup.');
    }
  }
}
