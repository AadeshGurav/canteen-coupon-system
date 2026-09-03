import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/app_mode.dart';
import '../../domain/menu.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final _monthProvider = StateProvider.autoDispose<DateTime>(
    (_) => DateTime(DateTime.now().year, DateTime.now().month));

final _menuProvider = FutureProvider.autoDispose<List<MenuEntry>>((ref) {
  final month = ref.watch(_monthProvider);
  final end = DateTime(month.year, month.month + 1, 0);
  return ref.watch(backendProvider).listMenu(start: month, end: end);
});
final _categoriesProvider = FutureProvider.autoDispose<List<MenuCategory>>(
    (ref) => ref.watch(backendProvider).listMenuCategories());

/// Menu planning (PRD §6.5). A month view as a date-grouped list (prev/next
/// month), each day showing its logged meals; tap a day to add or review.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_monthProvider);
    final entries = ref.watch(_menuProvider);
    final monthFmt = DateFormat('MMMM y');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu calendar'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(_monthProvider.notifier).state =
                    DateTime(month.year, month.month - 1),
              ),
              Text(monthFmt.format(month), style: NbType.label),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ref.read(_monthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
        onPressed: () => _addEntry(context, ref, DateTime.now()),
      ),
      body: AsyncView<List<MenuEntry>>(
        value: entries,
        onRetry: () => ref.invalidate(_menuProvider),
        builder: (list) {
          final byDay = <String, List<MenuEntry>>{};
          for (final e in list) {
            byDay
                .putIfAbsent(DateFormat('EEE, MMM d').format(e.date), () => [])
                .add(e);
          }
          if (byDay.isEmpty) {
            return const Center(
                child: Text('Nothing planned this month.', style: NbType.body));
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
                for (final e in day.value)
                  NbSurface(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${e.mealType.wire} · ${e.categories.join(", ")}',
                                  style: NbType.label),
                              Text(e.items.join(', '), style: NbType.body),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await runGuarded(
                              context,
                              () => ref
                                  .read(backendProvider)
                                  .deleteMenuEntry(e.id),
                              successMessage: 'Removed.',
                            );
                            if (ok) ref.invalidate(_menuProvider);
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

  Future<void> _addEntry(
      BuildContext context, WidgetRef ref, DateTime initialDate) async {
    final categories = await ref.read(_categoriesProvider.future);
    if (!context.mounted) return;
    var date = initialDate;
    var meal = MealType.lunch;
    final selectedCategories = <String>{};
    final items = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add menu entry', style: NbType.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(DateFormat('EEE, MMM d, y').format(date),
                            style: NbType.body)),
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
                      child: const Text('Date'),
                    ),
                  ],
                ),
                DropdownButton<MealType>(
                  value: meal,
                  isExpanded: true,
                  items: [
                    for (final m in MealType.values)
                      DropdownMenuItem(value: m, child: Text(m.wire)),
                  ],
                  onChanged: (m) => setLocal(() => meal = m ?? meal),
                ),
                Wrap(
                  spacing: NbSpace.sm,
                  children: [
                    for (final c in categories)
                      FilterChip(
                        label: Text(c.name),
                        selected: selectedCategories.contains(c.name),
                        onSelected: (v) => setLocal(() => v
                            ? selectedCategories.add(c.name)
                            : selectedCategories.remove(c.name)),
                      ),
                  ],
                ),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                    label: 'Items (comma-separated)', controller: items),
              ],
            ),
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
      () => ref.read(backendProvider).addMenuEntry(MenuEntryDraft(
            date: date,
            mealType: meal,
            categories: selectedCategories.toList(),
            items: items.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            createdBy: '',
          )),
      successMessage: 'Entry added.',
    );
    if (saved) ref.invalidate(_menuProvider);
  }
}
