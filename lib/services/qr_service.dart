import 'dart:math';
import 'dart:typed_data';

import 'package:qr_flutter/qr_flutter.dart';

/// QR code identity + rendering — a port of v1 `app/services/qr_service.py`.
///
/// The code id is generated once at member creation, stored permanently, and
/// reused for every reprint (PRD §5, §6.2) — a lost card never mints a new id,
/// so it can't split one person into two member records.
class QrService {
  QrService();

  final _random = Random.secure();

  /// 12 hex chars, matching v1's `uuid4().hex[:12]`.
  String generateCodeId() {
    final bytes = List<int>.generate(6, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Render (or re-render) the QR PNG for a code id. Safe to call repeatedly
  /// for reprints since the id itself never changes.
  Future<Uint8List> renderPng(String codeId, {double size = 600}) async {
    final painter = QrPainter(
      data: codeId,
      version: QrVersions.auto,
      gapless: true,
      // High correction so a slightly damaged printed card still scans.
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    final bytes = await painter.toImageData(size);
    if (bytes == null) {
      throw StateError('QR rendering produced no image for code $codeId');
    }
    return bytes.buffer.asUint8List();
  }
}
