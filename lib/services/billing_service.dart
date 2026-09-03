import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/member.dart';

/// Bill PDF + UPI payment QR — a port of v1 `app/services/billing_service.py`.
///
/// The UPI QR is deliberately NOT on the bill (PRD §6.3) — it's shown in a
/// modal at the moment of payment and outlives that moment as nothing. The
/// bill is the transaction record.
class BillingService {
  BillingService();

  /// Standard `upi://pay` URI (no gateway). Returns null when no UPI ID is
  /// configured — cash-only setups.
  String? upiPaymentUri({
    required double amount,
    required String note,
    required String upiId,
    required String upiPayeeName,
  }) {
    if (upiId.isEmpty) return null;
    final params = {
      'pa': upiId,
      'pn': upiPayeeName,
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      'tn': note,
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }

  Future<Uint8List> buildBillPdf({
    required int topupId,
    required Member member,
    required int lunchUnits,
    required int breakfastUnits,
    required int brunchUnits,
    required double amount,
    required String paymentMethod,
    required UnitCounts newBalances,
    required String appName,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(appName,
                  style: const pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Bill ID: $topupId'),
              pw.Text('Member: ${member.name} (${member.type})'),
              pw.SizedBox(height: 16),
              pw.Text('Units purchased',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                  'Lunch: $lunchUnits   Breakfast: $breakfastUnits   Brunch: $brunchUnits'),
              pw.SizedBox(height: 12),
              pw.Text(
                  'Amount: Rs. ${amount.toStringAsFixed(2)}  '
                  '(${paymentMethod.toUpperCase()})',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Text('New balances',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Lunch: ${newBalances.lunch}   '
                  'Breakfast: ${newBalances.breakfast}   '
                  'Brunch: ${newBalances.brunch}'),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }
}
