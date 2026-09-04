import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/ops.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final _expensesProvider = FutureProvider.autoDispose<List<Expense>>(
    (ref) => ref.watch(backendProvider).listExpenses());
final _summaryProvider = FutureProvider.autoDispose<ProfitSummary>(
    (ref) => ref.watch(backendProvider).profitSummary());

/// Expense logging + revenue-vs-expense summary (PRD §6.6).
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final expenses = ref.watch(_expensesProvider);
    final summary = ref.watch(_summaryProvider);
    final fmt = DateFormat('MMM d');

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses & revenue')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: t.color.accent,
        foregroundColor: t.color.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Log expense'),
        onPressed: () => _form(context, ref),
      ),
      body: Column(
        children: [
          summary.maybeWhen(
            data: (s) => NbSurface(
              intensity: NbIntensity.full,
              background: t.color.surfaceMuted,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat(t, 'Revenue', s.revenue),
                  _stat(t, 'Expenses', s.expenses),
                  _stat(t, 'Profit', s.profit),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: AsyncView<List<Expense>>(
              value: expenses,
              onRetry: () => ref.invalidate(_expensesProvider),
              loadingLabel: 'Loading expenses…',
              empty: NbEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'No expenses logged',
                quips: EmptyQuips.expenses,
                actionLabel: 'Log an expense',
                onAction: () => _form(context, ref),
              ),
              builder: (list) => ListView.separated(
                padding: const EdgeInsets.all(NbSpace.md),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
                itemBuilder: (_, i) {
                  final e = list[i];
                  return NbSurface(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.category} · ${e.description}',
                                  style: t.text.body),
                              Text(fmt.format(e.date), style: t.text.label),
                            ],
                          ),
                        ),
                        Text('Rs. ${e.amount.toStringAsFixed(2)}',
                            style: t.text.body),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(TiffinTokens t, String label, double value) => Column(
        children: [
          Text(label.toUpperCase(), style: t.text.label),
          Text('Rs. ${value.toStringAsFixed(0)}', style: t.text.heading),
        ],
      );

  Future<void> _form(BuildContext context, WidgetRef ref) async {
    final t = context.tokens;
    final category = TextEditingController();
    final description = TextEditingController();
    final amount = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Log expense', style: t.text.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NbTextField(
                    label: 'Category (groceries, tables…)',
                    controller: category),
                const SizedBox(height: NbSpace.sm),
                NbTextField(label: 'Description', controller: description),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                    label: 'Amount (Rs.)',
                    controller: amount,
                    keyboardType: TextInputType.number),
                const SizedBox(height: NbSpace.sm),
                Row(
                  children: [
                    Expanded(
                        child: Text(DateFormat('MMM d, y').format(date),
                            style: t.text.body)),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setLocal(() => date = picked);
                      },
                      child: const Text('Change date'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            NbButton(
                label: 'Save', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final saved = await runGuarded(
      context,
      () => ref.read(backendProvider).addExpense(ExpenseDraft(
            category: category.text.trim(),
            description: description.text.trim(),
            amount: double.tryParse(amount.text) ?? 0,
            date: date,
            createdBy: '',
          )),
      successMessage: 'Expense logged.',
    );
    if (saved) {
      ref.invalidate(_expensesProvider);
      ref.invalidate(_summaryProvider);
    }
  }
}
