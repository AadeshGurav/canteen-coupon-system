import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/ledger.dart';
import '../../domain/member.dart';
import '../../domain/settings.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

final _membersProvider = FutureProvider.autoDispose<List<Member>>(
    (ref) => ref.watch(backendProvider).listMembers(status: 'active'));
final _settingsProvider = FutureProvider.autoDispose<SettingsSnapshot>(
    (ref) => ref.watch(backendProvider).getSettings());

/// Top-up & billing (PRD §6.3): pick a member, enter units, pick cash/UPI. The
/// amount is computed from unit prices — never typed. Submit is disabled while
/// every unit is zero. Full-intensity CTA.
class TopUpScreen extends ConsumerStatefulWidget {
  const TopUpScreen({super.key});

  @override
  ConsumerState<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends ConsumerState<TopUpScreen> {
  Member? _member;
  int _lunch = 0, _breakfast = 0, _brunch = 0;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  double _amount(SettingsSnapshot s) =>
      _lunch * s.unitPrices.lunch +
      _breakfast * s.unitPrices.breakfast +
      _brunch * s.unitPrices.brunch;

  bool get _canSubmit =>
      _member != null && (_lunch + _breakfast + _brunch) > 0 && !_busy;

  Future<void> _submit(SettingsSnapshot s) async {
    setState(() => _busy = true);
    Topup? created;
    final ok = await runGuarded(context, () async {
      created = await ref.read(backendProvider).createTopup(TopupDraft(
            memberId: _member!.id,
            lunchUnits: _lunch,
            breakfastUnits: _breakfast,
            brunchUnits: _brunch,
            paymentMethod: _method,
            createdBy: '', // host/client backend fills this in
          ));
    }, successMessage: 'Balances credited.');
    if (mounted) setState(() => _busy = false);
    if (!ok || created == null || !mounted) return;
    await _showBillDialog(created!, s);
    if (mounted) {
      setState(() {
        _lunch = _breakfast = _brunch = 0;
        _member = null;
      });
      ref.invalidate(_membersProvider);
    }
  }

  Future<void> _showBillDialog(Topup topup, SettingsSnapshot s) async {
    Uint8List? upiQr;
    if (topup.paymentMethod == PaymentMethod.upi && topup.hasUpiQr) {
      try {
        upiQr = Uint8List.fromList(
            await ref.read(backendProvider).topupUpiQrPng(topup.id));
      } catch (_) {/* fall through — show without the QR */}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Bill #${topup.id}', style: NbType.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: Rs. ${topup.amount.toStringAsFixed(2)} '
                '(${topup.paymentMethod.wire.toUpperCase()})'),
            Text('Status: ${topup.paymentStatus}'),
            if (upiQr != null) ...[
              const SizedBox(height: NbSpace.md),
              const Text('Ask the payer to scan:'),
              const SizedBox(height: NbSpace.sm),
              Image.memory(upiQr, width: 220, height: 220),
            ],
          ],
        ),
        actions: [
          if (topup.paymentMethod == PaymentMethod.upi)
            NbButton.secondary(
              label: 'Mark received',
              onPressed: () async {
                final navigator = Navigator.of(context);
                final ok = await runGuarded(
                  context,
                  () => ref.read(backendProvider).confirmTopupPayment(topup.id),
                  successMessage: 'Payment confirmed.',
                );
                if (ok) navigator.pop();
              },
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersProvider);
    final settings = ref.watch(_settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Top-up & bill')),
      body: AsyncView<SettingsSnapshot>(
        value: settings,
        onRetry: () => ref.invalidate(_settingsProvider),
        builder: (s) => AsyncView<List<Member>>(
          value: members,
          onRetry: () => ref.invalidate(_membersProvider),
          builder: (list) => ListView(
            padding: const EdgeInsets.all(NbSpace.lg),
            children: [
              NbSurface(
                child: DropdownButtonFormField<Member>(
                  initialValue: _member,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'MEMBER'),
                  items: [
                    for (final m in list)
                      DropdownMenuItem(
                        value: m,
                        child: Text('${m.name} · ${m.type}'),
                      ),
                  ],
                  onChanged: (m) => setState(() => _member = m),
                ),
              ),
              const SizedBox(height: NbSpace.md),
              _UnitRow(
                label: 'Lunch  (Rs. ${s.unitPrices.lunch.toStringAsFixed(0)})',
                value: _lunch,
                onChanged: (v) => setState(() => _lunch = v),
              ),
              _UnitRow(
                label:
                    'Breakfast  (Rs. ${s.unitPrices.breakfast.toStringAsFixed(0)})',
                value: _breakfast,
                onChanged: (v) => setState(() => _breakfast = v),
              ),
              _UnitRow(
                label:
                    'Brunch  (Rs. ${s.unitPrices.brunch.toStringAsFixed(0)})',
                value: _brunch,
                onChanged: (v) => setState(() => _brunch = v),
              ),
              const SizedBox(height: NbSpace.md),
              SegmentedButton<PaymentMethod>(
                segments: const [
                  ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
                  ButtonSegment(value: PaymentMethod.upi, label: Text('UPI')),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              const SizedBox(height: NbSpace.lg),
              NbSurface(
                intensity: NbIntensity.full,
                background: NbColors.surfaceMuted,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: NbType.label),
                    Text('Rs. ${_amount(s).toStringAsFixed(2)}',
                        style: NbType.heading),
                  ],
                ),
              ),
              const SizedBox(height: NbSpace.md),
              NbButton(
                label: 'Charge & generate bill',
                busy: _busy,
                onPressed: _canSubmit ? () => _submit(s) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NbSpace.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: NbType.body)),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          Text('$value', style: NbType.heading),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
