import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Where generated bills and UPI QR images live on the host device. A thin
/// wrapper around a base directory (the app documents dir, set once by the host
/// bootstrap) so services don't each re-derive paths.
class ArtifactStore {
  ArtifactStore(this.baseDir);

  final String baseDir;

  Future<String> writeBill(int topupId, Uint8List bytes) =>
      _write(p.join('bills', 'bill_$topupId.pdf'), bytes);

  Future<String> writeUpiQr(int topupId, Uint8List bytes) =>
      _write(p.join('qr', 'upi_$topupId.png'), bytes);

  Future<String> writeMemberQr(String codeId, Uint8List bytes) =>
      _write(p.join('qr', '$codeId.png'), bytes);

  Future<Uint8List> read(String path) => File(path).readAsBytes();

  Future<String> _write(String relative, Uint8List bytes) async {
    final file = File(p.join(baseDir, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
