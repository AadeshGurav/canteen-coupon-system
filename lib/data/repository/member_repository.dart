import '../../domain/member.dart';

/// The data-access seam (PRD §13.7): UI and business-logic code depend only on
/// this interface. In host mode it is backed by drift + services running
/// in-process; in client mode by HTTP calls to a discovered host. Neither the
/// screen nor the caller knows which.
///
/// One interface per domain — this is the pattern; the other 13 domains follow
/// the same shape.
abstract interface class MemberRepository {
  Future<List<Member>> list({String? type, String? status});

  Future<Member> getById(int id);

  /// Resolve by permanent QR value — used by the scanner and by top-up member
  /// lookup.
  Future<Member?> getByQrCode(String qrCodeId);

  Future<Member> create(MemberDraft draft);

  /// Bulk paper-to-digital migration (PRD §6.1). Each row is independent — one
  /// bad row doesn't fail the batch.
  Future<BulkResult> createBulk(List<MemberDraft> drafts);

  Future<Member> update(int id, MemberPatch patch);

  /// Only permitted for a member with no scan/top-up/refund history (PRD §6.1) —
  /// throws [ConflictException] otherwise.
  Future<void> delete(int id);

  /// Add units to balances (the admin credit action, PRD §6.1). This is the
  /// primitive; a billed top-up goes through [TopupRepository].
  Future<Member> credit(int id, UnitCounts units);

  /// (Re)render the member's permanent QR image and return its bytes.
  Future<List<int>> renderQr(int id);
}

/// Result of a partial-success bulk operation.
class BulkResult {
  const BulkResult({required this.created, required this.failed});

  final List<Member> created;
  final List<BulkFailure> failed;
}

class BulkFailure {
  const BulkFailure(
      {required this.index, required this.name, required this.error});

  final int index;
  final String name;
  final String error;
}
