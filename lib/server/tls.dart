import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:path/path.dart' as p;

import '../core/logging.dart';

/// On-device self-signed certificate for the desktop-admin HTTPS surface
/// (PRD §13.6). No `mkcert`, no shelling out — RSA keypair + self-signed X.509
/// generated in Dart, written as PEM under `<documentsDir>/tls/`.
///
/// Known, accepted limitation (state it plainly in the UI, per CLAUDE.md §8):
/// a self-signed cert can't remove the browser's "not trusted" warning — only
/// a real CA can. It turns "install a root CA, several steps" into "click
/// through one warning, once per device".
class SelfSignedTls {
  SelfSignedTls(this.documentsDir);

  final String documentsDir;
  final _log = log('tls');

  String get _dir => p.join(documentsDir, 'tls');
  File get _keyFile => File(p.join(_dir, 'key.pem'));
  File get _certFile => File(p.join(_dir, 'cert.pem'));

  bool get exists => _keyFile.existsSync() && _certFile.existsSync();

  /// Generate (or regenerate) the keypair + certificate. Returns the cert's
  /// not-after date for display.
  Future<DateTime> generate({String commonName = 'tiffin.local'}) async {
    await Directory(_dir).create(recursive: true);

    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;

    final csr = X509Utils.generateRsaCsrPem(
      {'CN': commonName, 'O': 'Tiffin'},
      privateKey,
      publicKey,
    );

    const days = 825; // within the 825-day cap browsers accept for leaf certs
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      days,
      sans: [commonName, 'localhost'],
    );

    await _keyFile.writeAsString(
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
    await _certFile.writeAsString(certPem);
    _log.info('generated self-signed cert cn=$commonName days=$days');

    return DateTime.now().add(const Duration(days: days));
  }

  /// A [SecurityContext] for [HttpServer] / shelf, or null if no cert exists.
  SecurityContext? securityContext() {
    if (!exists) return null;
    return SecurityContext()
      ..useCertificateChain(_certFile.path)
      ..usePrivateKey(_keyFile.path);
  }
}
