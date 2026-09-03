import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/role.dart';
import '../../domain/inventory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';
import 'ingredients_screen.dart';

final _scheduleProvider =
    FutureProvider.autoDispose<List<PurchaseScheduleItem>>(
        (ref) => ref.watch(backendProvider).listPurchaseSchedule());

/// Purchase schedule (PRD §6.5.1). Admin generates from the menu calendar and
/// deletes; admin + counter check items off and add ad-hoc items.
class PurchaseScheduleScreen extends ConsumerWidget {
  const PurchaseScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(_scheduleProvider);
    final isAdmin = ref.watch(sessionProvider)?.role == Role.admin;
    final fmt = DateFormat('EEE, MMM d');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase schedule'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Generate from menu',
              onPressed: () => _generate(context, ref),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
        onPressed: () => _addManual(context, ref),
      ),
      body: AsyncView<List<PurchaseScheduleItem>>(
        value: schedule,
        onRetry: () => ref.invalidate(_scheduleProvider),
        builder: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Text('Nothing scheduled.', style: NbType.body));
          }
          final byDay = <String, List<PurchaseScheduleItem>>{};
          for (final it in list) {
            byDay.putIfAbsent(fmt.format(it.date), () => []).add(it);
          }
          return ListView(
            padding: const EdgeInsets.all(NbSpace.md),
            children: [
              for (final day in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      top: NbSpace.md, bottom: NbSpace.xs),
                  child: Text(day.key.toUpperCase(), style: NbType.label),
                ),
                for (final it in day.value)
                  NbSurface(
                    child: Row(
                      children: [
                        Checkbox(
                          value: it.purchased,
                          onChanged: (v) async {
                            final ok = await runGuarded(
                              context,
                              () => ref
                                  .read(backendProvider)
                                  .updatePurchaseItem(it.id,
                                      purchased: v ?? false),
                            );
                            if (ok) ref.invalidate(_scheduleProvider);
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${it.ingredientName} — ${it.quantityNote} '
                                  '(${it.ingredientUnit})',
                                  style: NbType.body),
                              Text(
                                  it.source == 'manual'
                                      ? 'manual'
                                      : 'from menu'
                                          '${it.purchased ? ' · by ${it.purchasedBy}' : ''}',
                                  style: NbType.label),
                            ],
                          ),
                        ),
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await runGuarded(
                                context,
                                () => ref
                                    .read(backendProvider)
                                    .deletePurchaseItem(it.id),
                                successMessage: 'Removed.',
                              );
                              if (ok) ref.invalidate(_scheduleProvider);
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 7));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Generate schedule', style: NbType.heading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dateRow(
                  context, 'From', start, (d) => setLocal(() => start = d)),
              _dateRow(context, 'To', end, (d) => setLocal(() => end = d)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            NbButton(
                label: 'Generate',
                onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await runGuarded(
      context,
      () async {
        final created = await ref
            .read(backendProvider)
            .generatePurchaseSchedule(start, end);
        if (context.mounted) {
          showNbSnack(context, 'Added $created new item(s).');
        }
      },
    );
    if (done) ref.invalidate(_scheduleProvider);
  }

  Future<void> _addManual(BuildContext context, WidgetRef ref) async {
    final ingredients = await ref.read(ingredientsProvider.future);
    if (!context.mounted || ingredients.isEmpty) return;
    var selected = ingredients.first;
    var date = DateTime.now();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add purchase item', style: NbType.heading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Ingredient>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final ing in ingredients)
                    DropdownMenuItem(value: ing, child: Text(ing.name)),
                ],
                onChanged: (v) => setLocal(() => selected = v ?? selected),
              ),
              _dateRow(context, 'Date', date, (d) => setLocal(() => date = d)),
              NbTextField(label: 'Quantity note', controller: note),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            NbButton(
                label: 'Add', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final saved = await runGuarded(
      context,
      () => ref
          .read(backendProvider)
          .addManualPurchaseItem(date, selected.id, note.text.trim()),
      successMessage: 'Item added.',
    );
    if (saved) ref.invalidate(_scheduleProvider);
  }

  Widget _dateRow(BuildContext context, String label, DateTime value,
      ValueChanged<DateTime> onChanged) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: NbType.label)),
        Expanded(
            child:
                Text(DateFormat('MMM d, y').format(value), style: NbType.body)),
        TextButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) onChanged(picked);
          },
          child: const Text('Pick'),
        ),
      ],
    );
  }
}
