import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;

import '../core/logging.dart';

/// The desktop-admin web bundle (PRD §13.4) is shipped as Flutter assets, which
/// `shelf_static` can't serve directly — it needs a real directory. On host
/// start this copies `assets/web_admin/**` out to `<documentsDir>/web_admin/`
/// and returns that path for `HostServer(staticRoot: ...)`.
class WebAdminAssets {
  WebAdminAssets(this.documentsDir);

  final String documentsDir;
  final _log = log('webadmin');

  static const _prefix = 'assets/web_admin/';

  Future<String> materialize() async {
    final targetDir = p.join(documentsDir, 'web_admin');

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest.listAssets().where((a) => a.startsWith(_prefix)).toList();

    if (assets.isEmpty) {
      // Defensive: still return a usable (empty) dir so the server starts.
      await Directory(targetDir).create(recursive: true);
      _log.warning('no web_admin assets bundled — desktop admin unavailable');
      return targetDir;
    }

    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      final file = File(p.join(targetDir, asset.substring(_prefix.length)));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    _log.info('materialized ${assets.length} web-admin file(s) to $targetDir');
    return targetDir;
  }
}
