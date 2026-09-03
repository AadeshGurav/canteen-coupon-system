import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/ledger.dart';
import '../../domain/member.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final _refundsProvider = FutureProvider.autoDispose<List<Refund>>(
    (ref) => ref.watch(backendProvider).listRefunds());
final _activeMembersProvider = FutureProvider.autoDispose<List<Member>>(
    (ref) => ref.watch(backendProvider).listMembers());

/// Refunds (PRD §6.7): deduct units from a member's balance and record it. The
/// money movement is outside the app. Units pre-fill from the current balance
/// and can't exceed it (the host enforces this too).
class RefundsScreen extends ConsumerWidget {
  const RefundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refunds = ref.watch(_refundsProvider);
    final fmt = DateFormat('MMM d, y');
    return Scaffold(
      appBar: AppBar(title: const Text('Refunds')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.undo),
        label: const Text('New refund'),
        onPressed: () => _form(context, ref),
      ),
      body: AsyncView<List<Refund>>(
        value: refunds,
        onRetry: () => ref.invalidate(_refundsProvider),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final r = list[i];
            return NbSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'L${r.lunchUnits} B${r.breakfastUnits} Br${r.brunchUnits}'
                      '  ·  Rs. ${r.refundAmount.toStringAsFixed(2)}',
                      style: NbType.body),
                  Text(
                      '${fmt.format(r.createdAt.toLocal())} · by ${r.processedBy}'
                      '${r.reason == null ? '' : ' · ${r.reason}'}',
                      style: NbType.label),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _form(BuildContext context, WidgetRef ref) async {
    final members = await ref.read(_activeMembersProvider.future);
    if (!context.mounted || members.isEmpty) return;
    Member selected = members.first;
    final lunch = TextEditingController();
    final breakfast = TextEditingController();
    final brunch = TextEditingController();
    final reason = TextEditingController();

    void prefill() {
      lunch.text = '${selected.balances.lunch}';
      breakfast.text = '${selected.balances.breakfast}';
      brunch.text = '${selected.balances.brunch}';
    }

    prefill();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New refund', style: NbType.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<Member>(
                  value: selected,
                  isExpanded: true,
                  items: [
                    for (final m in members)
                      DropdownMenuItem(value: m, child: Text(m.name)),
                  ],
                  onChanged: (m) => setLocal(() {
                    selected = m ?? selected;
                    prefill();
                  }),
                ),
                NbTextField(
                    label: 'Lunch units',
                    controller: lunch,
                    keyboardType: TextInputType.number),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                    label: 'Breakfast units',
                    controller: breakfast,
                    keyboardType: TextInputType.number),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                    label: 'Brunch units',
                    controller: brunch,
                    keyboardType: TextInputType.number),
                const SizedBox(height: NbSpace.sm),
                NbTextField(label: 'Reason (optional)', controller: reason),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            NbButton(
                label: 'Process',
                onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final saved = await runGuarded(
      context,
      () => ref.read(backendProvider).createRefund(RefundDraft(
            memberId: selected.id,
            lunchUnits: int.tryParse(lunch.text) ?? 0,
            breakfastUnits: int.tryParse(breakfast.text) ?? 0,
            brunchUnits: int.tryParse(brunch.text) ?? 0,
            reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
            processedBy: '',
          )),
      successMessage: 'Refund recorded.',
    );
    if (saved) ref.invalidate(_refundsProvider);
  }
}
