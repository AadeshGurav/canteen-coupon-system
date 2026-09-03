import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart' hide Member;
import '../data/local/mappers.dart';
import '../data/repository/member_repository.dart';
import '../domain/member.dart';
import 'qr_service.dart';

/// Member entity CRUD + credit + QR reprint — a port of v1
/// `app/routers/members.py` + the member-shaped bits of `qr_service.py`.
class MemberService {
  MemberService(this._db, this._qr);

  final AppDatabase _db;
  final QrService _qr;
  final _log = log('member');

  Future<List<Member>> list({String? type, String? status}) async {
    final query = _db.select(_db.members);
    if (type != null) query.where((m) => m.type.equals(type));
    if (status != null) query.where((m) => m.status.equals(status));
    return (await query.get()).map(memberFromRow).toList();
  }

  Future<Member> getById(int id) async {
    final row = await (_db.select(_db.members)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw const NotFoundException('Member not found.');
    return memberFromRow(row);
  }

  Future<Member?> getByQrCode(String qrCodeId) async {
    final row = await (_db.select(_db.members)
          ..where((m) => m.qrCodeId.equals(qrCodeId)))
        .getSingleOrNull();
    return row == null ? null : memberFromRow(row);
  }

  Future<Member> create(MemberDraft draft) async {
    _validateTypeSpecific(
        draft.type, draft.className, draft.rollNumber, draft.staffId);
    final now = DateTime.now().toUtc();

    // qr_code_id is random; a collision is astronomically unlikely but retry
    // rather than surface a raw unique-constraint error (matches v1).
    for (var attempt = 0; attempt < 3; attempt++) {
      final codeId = _qr.generateCodeId();
      try {
        final id = await _db.into(_db.members).insert(MembersCompanion.insert(
              type: draft.type,
              name: draft.name,
              className: Value(draft.className),
              rollNumber: Value(draft.rollNumber),
              staffId: Value(draft.staffId),
              qrCodeId: codeId,
              lunchBalance: Value(draft.balances.lunch),
              breakfastBalance: Value(draft.balances.breakfast),
              brunchBalance: Value(draft.balances.brunch),
              graceAllowanceOverride: Value(draft.graceAllowanceOverride),
              createdAt: now,
              updatedAt: now,
            ));
        _log.info(
            'created member_id=$id type=${draft.type} name=${draft.name}');
        return await getById(id);
      } on Exception catch (e) {
        if (_isUniqueViolation(e) && attempt < 2) continue;
        rethrow;
      }
    }
    throw const InternalException(
        'Could not generate a unique QR code — please try again.');
  }

  /// Migrate paper records in one call (PRD §6.1). Each row is independent —
  /// one bad row doesn't fail the batch.
  Future<BulkResult> createBulk(List<MemberDraft> drafts) async {
    final created = <Member>[];
    final failed = <BulkFailure>[];
    for (var i = 0; i < drafts.length; i++) {
      try {
        created.add(await create(drafts[i]));
      } catch (e) {
        _log.warning('bulk_create_failed index=$i name=${drafts[i].name}');
        failed.add(BulkFailure(index: i, name: drafts[i].name, error: '$e'));
      }
    }
    _log.info('bulk_created count=${created.length} failed=${failed.length}');
    return BulkResult(created: created, failed: failed);
  }

  Future<Member> update(int id, MemberPatch patch) async {
    final existing = await (_db.select(_db.members)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) throw const NotFoundException('Member not found.');

    // type is immutable; still guard against a staff_id on a student etc.
    _validateTypeSpecific(
      existing.type,
      patch.className ?? existing.className,
      patch.rollNumber ?? existing.rollNumber,
      patch.staffId ?? existing.staffId,
    );

    final companion = MembersCompanion(
      name: patch.name == null ? const Value.absent() : Value(patch.name!),
      className: patch.className == null
          ? const Value.absent()
          : Value(patch.className),
      rollNumber: patch.rollNumber == null
          ? const Value.absent()
          : Value(patch.rollNumber),
      staffId:
          patch.staffId == null ? const Value.absent() : Value(patch.staffId),
      status:
          patch.status == null ? const Value.absent() : Value(patch.status!),
      graceAllowanceOverride:
          patch.touchesGrace ? Value(patch.graceValue) : const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(_db.members)..where((m) => m.id.equals(id)))
        .write(companion);
    _log.info('updated member_id=$id');
    return await getById(id);
  }

  /// Only for a member with no history — otherwise it would orphan scan /
  /// top-up / refund rows (PRD §6.1). Use status='inactive' instead.
  Future<void> delete(int id) async {
    final hasScans = await (_db.select(_db.scans)
              ..where((s) => s.memberId.equals(id))
              ..limit(1))
            .getSingleOrNull() !=
        null;
    final hasTopups = await (_db.select(_db.topups)
              ..where((t) => t.memberId.equals(id))
              ..limit(1))
            .getSingleOrNull() !=
        null;
    final hasRefunds = await (_db.select(_db.refunds)
              ..where((r) => r.memberId.equals(id))
              ..limit(1))
            .getSingleOrNull() !=
        null;
    if (hasScans || hasTopups || hasRefunds) {
      throw const ConflictException(
        "This member has scan, top-up, or refund history and can't be deleted — "
        "it would orphan those records. Set status to 'inactive' instead.",
      );
    }
    final n =
        await (_db.delete(_db.members)..where((m) => m.id.equals(id))).go();
    if (n == 0) throw const NotFoundException('Member not found.');
    _log.warning('deleted member_id=$id');
  }

  /// Admin credit primitive — add units, no bill (PRD §6.1). A billed top-up
  /// goes through TopupService.
  Future<Member> credit(int id, UnitCounts units) async {
    final existing = await (_db.select(_db.members)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) throw const NotFoundException('Member not found.');
    await (_db.update(_db.members)..where((m) => m.id.equals(id))).write(
      MembersCompanion(
        lunchBalance: Value(existing.lunchBalance + units.lunch),
        breakfastBalance: Value(existing.breakfastBalance + units.breakfast),
        brunchBalance: Value(existing.brunchBalance + units.brunch),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    _log.info('credited member_id=$id '
        'lunch=+${units.lunch} breakfast=+${units.breakfast} brunch=+${units.brunch}');
    return await getById(id);
  }

  Future<List<int>> renderQr(int id) async {
    final member = await getById(id);
    final bytes = await _qr.renderPng(member.qrCodeId);
    return bytes;
  }

  // ---- validation ---------------------------------------------------

  void _validateTypeSpecific(
    String type,
    String? className,
    String? rollNumber,
    String? staffId,
  ) {
    if (type == 'student' && (staffId != null && staffId.isNotEmpty)) {
      throw const ValidationException(
          'staff_id should not be set for a student member.');
    }
    if (type == 'staff' &&
        ((className != null && className.isNotEmpty) ||
            (rollNumber != null && rollNumber.isNotEmpty))) {
      throw const ValidationException(
          'class/roll number should not be set for a staff member.');
    }
    if (type != 'student' && type != 'staff') {
      throw ValidationException("Unknown member type '$type'.");
    }
  }

  bool _isUniqueViolation(Exception e) =>
      e.toString().toLowerCase().contains('unique');
}
