import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart' hide Topup;
import '../data/local/mappers.dart';
import '../domain/ledger.dart';
import '../domain/member.dart';
import 'artifact_store.dart';
import 'billing_service.dart';
import 'qr_service.dart';
import 'settings_service.dart';

/// Top-ups & billing — a port of v1 `app/routers/topups.py`. The bill amount is
/// always computed from `settings.unitPrices`, never client-supplied (PRD §6.3).
/// Bill/QR generation is isolated: if it fails, the balance credit still
/// stands (CLAUDE.md §5).
class TopupService {
  TopupService(
      this._db, this._settings, this._billing, this._qr, this._artifacts);

  final AppDatabase _db;
  final SettingsService _settings;
  final BillingService _billing;
  final QrService _qr;
  final ArtifactStore _artifacts;
  final _log = log('topup');

  Future<List<Topup>> list({int? memberId, int limit = 200}) async {
    final query = _db.select(_db.topups)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit.clamp(1, 1000));
    if (memberId != null) query.where((t) => t.memberId.equals(memberId));
    return (await query.get()).map(topupFromRow).toList();
  }

  Future<Topup> getById(int id) async {
    final row = await (_db.select(_db.topups)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw const NotFoundException('Top-up not found.');
    return topupFromRow(row);
  }

  Future<Topup> create(TopupDraft draft) async {
    if (draft.isAllZero) {
      throw const ValidationException('A top-up needs at least one unit.');
    }
    final member = await (_db.select(_db.members)
          ..where((m) => m.id.equals(draft.memberId)))
        .getSingleOrNull();
    if (member == null) throw const NotFoundException('Member not found.');

    final settings = await _settings.read();
    final prices = settings.unitPrices;
    final amount = draft.lunchUnits * prices.lunch +
        draft.breakfastUnits * prices.breakfast +
        draft.brunchUnits * prices.brunch;

    final now = DateTime.now().toUtc();
    final newBalances = UnitCounts(
      lunch: member.lunchBalance + draft.lunchUnits,
      breakfast: member.breakfastBalance + draft.breakfastUnits,
      brunch: member.brunchBalance + draft.brunchUnits,
    );

    final topupId = await _db.transaction(() async {
      final id = await _db.into(_db.topups).insert(TopupsCompanion.insert(
            memberId: draft.memberId,
            lunchUnits: Value(draft.lunchUnits),
            breakfastUnits: Value(draft.breakfastUnits),
            brunchUnits: Value(draft.brunchUnits),
            amount: amount,
            paymentMethod: draft.paymentMethod.wire,
            // cash settles now; upi is pending until the admin confirms receipt.
            paymentStatus: draft.paymentMethod == PaymentMethod.cash
                ? 'confirmed'
                : 'pending',
            createdBy: draft.createdBy,
            createdAt: now,
          ));
      await (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
          .write(
        MembersCompanion(
          lunchBalance: Value(newBalances.lunch),
          breakfastBalance: Value(newBalances.breakfast),
          brunchBalance: Value(newBalances.brunch),
          updatedAt: Value(now),
        ),
      );
      return id;
    });

    _log.info('credited member_id=${draft.memberId} topup_id=$topupId '
        'amount=${amount.toStringAsFixed(2)} method=${draft.paymentMethod.wire} '
        'by=${draft.createdBy}');

    // Layered on top of a transaction that already committed — a rendering
    // failure must not lose or redo the credit.
    try {
      final billBytes = await _billing.buildBillPdf(
        topupId: topupId,
        member: memberFromRow(member),
        lunchUnits: draft.lunchUnits,
        breakfastUnits: draft.breakfastUnits,
        brunchUnits: draft.brunchUnits,
        amount: amount,
        paymentMethod: draft.paymentMethod.wire,
        newBalances: newBalances,
        appName: settings.appName,
      );
      final billPath = await _artifacts.writeBill(topupId, billBytes);

      String? qrPath;
      if (draft.paymentMethod == PaymentMethod.upi) {
        final uri = _billing.upiPaymentUri(
          amount: amount,
          note: 'Canteen topup $topupId',
          upiId: settings.upiId,
          upiPayeeName: settings.upiPayeeName,
        );
        if (uri != null) {
          final qrBytes = await _qr.renderPng(uri);
          qrPath = await _artifacts.writeUpiQr(topupId, qrBytes);
        }
      }

      await (_db.update(_db.topups)..where((t) => t.id.equals(topupId))).write(
        TopupsCompanion(
          billPdfPath: Value(billPath),
          upiQrPath: Value(qrPath),
        ),
      );
    } catch (e, st) {
      _log.severe(
          'bill_generation_failed topup_id=$topupId — balance already credited; '
          'admin should regenerate or inform the payer',
          e,
          st);
    }

    return getById(topupId);
  }

  Future<void> confirmPayment(int topupId) async {
    final n = await (_db.update(_db.topups)..where((t) => t.id.equals(topupId)))
        .write(const TopupsCompanion(paymentStatus: Value('confirmed')));
    if (n == 0) throw const NotFoundException('Top-up not found.');
    _log.info('payment_confirmed topup_id=$topupId');
  }

  /// Raw bytes of the stored bill PDF, for the API to stream.
  Future<Uint8List> billPdf(int topupId) async {
    final row = await (_db.select(_db.topups)
          ..where((t) => t.id.equals(topupId)))
        .getSingleOrNull();
    if (row?.billPdfPath == null) {
      throw const NotFoundException('No bill for this top-up.');
    }
    return _artifacts.read(row!.billPdfPath!);
  }

  Future<Uint8List> upiQr(int topupId) async {
    final row = await (_db.select(_db.topups)
          ..where((t) => t.id.equals(topupId)))
        .getSingleOrNull();
    if (row?.upiQrPath == null) {
      throw const NotFoundException('No UPI QR for this top-up.');
    }
    return _artifacts.read(row!.upiQrPath!);
  }
}
