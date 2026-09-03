import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/app_mode.dart';
import '../core/errors.dart';
import '../domain/ledger.dart';
import '../domain/member.dart';
import 'host_container.dart';
import 'http_json.dart';
import 'middleware.dart';

/// Authenticated `/api` routes for members, scanning, top-ups and refunds.
/// Ports v1 `routers/members.py`, `scan.py`, `topups.py`, `refunds.py`.
Router memberAndLedgerRoutes(HostContainer c) {
  final router = Router();

  // ---- members --------------------------------------------------
  router.get('/members', (Request request) async {
    requireRole(request, rolesBilling);
    final members = await c.members.list(
      type: request.url.queryParameters['type'],
      status: request.url.queryParameters['status'],
    );
    return jsonList(members.map((m) => m.toJson()));
  });

  router.get('/members/<id>', (Request request, String id) async {
    requireRole(request, rolesBilling);
    final member = await c.members.getById(pathId(id, entity: 'member'));
    return jsonOk(member.toJson());
  });

  router.post('/members', (Request request) async {
    requireRole(request, rolesAdmin);
    final draft = MemberDraft.fromJson(await readJsonObject(request));
    return jsonOk((await c.members.create(draft)).toJson());
  });

  router.post('/members/bulk', (Request request) async {
    requireRole(request, rolesAdmin);
    final rows = await readJsonArray(request);
    final drafts = rows
        .map((e) => MemberDraft.fromJson(e as Map<String, dynamic>))
        .toList();
    final result = await c.members.createBulk(drafts);
    return jsonOk({
      'created': result.created.map((m) => m.toJson()).toList(),
      'failed': result.failed
          .map((f) => {'index': f.index, 'name': f.name, 'error': f.error})
          .toList(),
    });
  });

  router.patch('/members/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final patch = MemberPatch.fromJson(await readJsonObject(request));
    final updated = await c.members.update(pathId(id, entity: 'member'), patch);
    return jsonOk(updated.toJson());
  });

  router.delete('/members/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.members.delete(pathId(id, entity: 'member'));
    return jsonOk({'success': true});
  });

  router.post('/members/<id>/credit', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final units = UnitCounts.fromJson(body);
    final updated = await c.members.credit(pathId(id, entity: 'member'), units);
    return jsonOk(updated.toJson());
  });

  router.get('/members/<id>/qr', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final bytes = await c.members.renderQr(pathId(id, entity: 'member'));
    return bytesOk(bytes, 'image/png');
  });

  // ---- scanning -------------------------------------------------
  router.post('/scan', (Request request) async {
    requireRole(request, rolesAll);
    final body = await readJsonObject(request);
    final code = (body['qrCodeId'] as String?)?.trim() ?? '';
    if (code.isEmpty) {
      throw const ValidationException('qrCodeId is required.');
    }
    final overrideRaw = body['mealTypeOverride'] as String?;
    final result = await c.scans.processScan(
      code,
      mealTypeOverride:
          overrideRaw == null ? null : MealType.fromWire(overrideRaw),
    );
    return jsonOk(result.toJson());
  });

  router.post('/scan/reverse', (Request request) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final caller = callerOf(request);
    final scanId = (body['scanId'] as num?)?.toInt();
    if (scanId == null) throw const ValidationException('scanId is required.');
    final result = await c.scans.reverseScan(scanId, caller.username);
    return jsonOk(result.toJson());
  });

  router.get('/scans', (Request request) async {
    requireRole(request, rolesAdmin);
    final scans = await c.scans.recentScans(
      memberId: int.tryParse(request.url.queryParameters['memberId'] ?? ''),
      limit: intParam(request, 'limit', fallback: 200),
    );
    return jsonList(scans.map((s) => s.toJson()));
  });

  // ---- top-ups -------------------------------------------------
  router.get('/topups', (Request request) async {
    requireRole(request, rolesBilling);
    final topups = await c.topups.list(
      memberId: int.tryParse(request.url.queryParameters['memberId'] ?? ''),
      limit: intParam(request, 'limit', fallback: 200),
    );
    return jsonList(topups.map((t) => t.toJson()));
  });

  router.post('/topups', (Request request) async {
    final caller = requireRole(request, rolesBilling);
    final body = await readJsonObject(request);
    final draft = TopupDraft.fromJson({...body, 'createdBy': caller.username});
    return jsonOk((await c.topups.create(draft)).toJson());
  });

  router.post('/topups/<id>/confirm-payment',
      (Request request, String id) async {
    requireRole(request, rolesBilling);
    await c.topups.confirmPayment(pathId(id, entity: 'top-up'));
    return jsonOk({'success': true});
  });

  router.get('/topups/<id>/bill', (Request request, String id) async {
    requireRole(request, rolesBilling);
    final bytes = await c.topups.billPdf(pathId(id, entity: 'top-up'));
    return bytesOk(bytes, 'application/pdf');
  });

  router.get('/topups/<id>/upi-qr', (Request request, String id) async {
    requireRole(request, rolesBilling);
    final bytes = await c.topups.upiQr(pathId(id, entity: 'top-up'));
    return bytesOk(bytes, 'image/png');
  });

  // ---- refunds (admin) --------------------------------------
  router.get('/refunds', (Request request) async {
    requireRole(request, rolesAdmin);
    final refunds = await c.refunds.list(
      memberId: int.tryParse(request.url.queryParameters['memberId'] ?? ''),
    );
    return jsonList(refunds.map((r) => r.toJson()));
  });

  router.post('/refunds', (Request request) async {
    final caller = requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final draft =
        RefundDraft.fromJson({...body, 'processedBy': caller.username});
    return jsonOk((await c.refunds.create(draft)).toJson());
  });

  return router;
}
