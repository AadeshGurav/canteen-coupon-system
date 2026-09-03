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

final _selectedDayProvider =
    StateProvider.autoDispose<DateTime>((_) => _dateOnly(DateTime.now()));

final _menuProvider = FutureProvider.autoDispose<List<MenuEntry>>((ref) {
  final month = ref.watch(_monthProvider);
  final end = DateTime(month.year, month.month + 1, 0);
  return ref.watch(backendProvider).listMenu(start: month, end: end);
});
final _categoriesProvider = FutureProvider.autoDispose<List<MenuCategory>>(
    (ref) => ref.watch(backendProvider).listMenuCategories());

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Menu planning (PRD §6.5) — an interactive month **calendar grid** (as the v1
/// build had): prev/next month, today highlighted, each day shows its logged
/// meals as tags at a glance. Tap a day to select it; the panel below lists
/// that day's entries and lets you add or delete. Restrained neobrutalism —
/// this is a dense data surface.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_monthProvider);
    final selected = ref.watch(_selectedDayProvider);
    final entries = ref.watch(_menuProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu calendar'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(_monthProvider.notifier).state =
                    DateTime(month.year, month.month - 1),
              ),
              Text(DateFormat('MMMM y').format(month), style: NbType.label),
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
        label: Text('Add · ${DateFormat('MMM d').format(selected)}'),
        onPressed: () => _addEntry(context, ref, selected),
      ),
      body: AsyncView<List<MenuEntry>>(
        value: entries,
        onRetry: () => ref.invalidate(_menuProvider),
        loadingLabel: 'Loading the month…',
        builder: (list) {
          final byDay = <int, List<MenuEntry>>{};
          for (final e in list) {
            if (e.date.year == month.year && e.date.month == month.month) {
              byDay.putIfAbsent(e.date.day, () => []).add(e);
            }
          }
          final dayEntries = list
              .where((e) => _sameDay(e.date, selected))
              .toList()
            ..sort((a, b) => a.mealType.index.compareTo(b.mealType.index));

          return Column(
            children: [
              _MonthGrid(
                month: month,
                selected: selected,
                entryCountByDay: {
                  for (final d in byDay.keys) d: byDay[d]!.length
                },
                mealsByDay: {
                  for (final d in byDay.keys)
                    d: byDay[d]!.map((e) => e.mealType).toSet()
                },
                onSelect: (day) =>
                    ref.read(_selectedDayProvider.notifier).state = day,
              ),
              const Divider(height: 0),
              Expanded(
                child: _DayPanel(
                  day: selected,
                  entries: dayEntries,
                  onDelete: (id) async {
                    final ok = await runGuarded(
                      context,
                      () => ref.read(backendProvider).deleteMenuEntry(id),
                      successMessage: 'Removed.',
                    );
                    if (ok) ref.invalidate(_menuProvider);
                  },
                  onAdd: () => _addEntry(context, ref, selected),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addEntry(
      BuildContext context, WidgetRef ref, DateTime day) async {
    final categories = await ref.read(_categoriesProvider.future);
    if (!context.mounted) return;
    var date = day;
    var meal = MealType.lunch;
    final selectedCategories = <String>{};
    final items = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Add · ${DateFormat('EEE, MMM d').format(date)}',
              style: NbType.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<MealType>(
                  value: meal,
                  isExpanded: true,
                  items: [
                    for (final m in MealType.values)
                      DropdownMenuItem(value: m, child: Text(m.wire)),
                  ],
                  onChanged: (m) => setLocal(() => meal = m ?? meal),
                ),
                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: NbSpace.sm),
                    child: Text(
                        'No categories yet — add some on the Menu categories '
                        'page first.',
                        style: NbType.label),
                  )
                else
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

/// A colour + a letter per meal — never colour alone (PRD §14.3).
const _mealColor = {
  MealType.breakfast: NbColors.warn,
  MealType.lunch: NbColors.accent,
  MealType.brunch: NbColors.accept,
};

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.entryCountByDay,
    required this.mealsByDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<int, int> entryCountByDay;
  final Map<int, Set<MealType>> mealsByDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first grid. weekday: Mon=1..Sun=7.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = _dateOnly(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(NbSpace.sm),
      child: Column(
        children: [
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d, style: NbType.label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NbSpace.xs),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _cell(r * 7 + c - leadingBlanks + 1, today),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int day, DateTime today) {
    if (day < 1 || day > DateTime(month.year, month.month + 1, 0).day) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final date = DateTime(month.year, month.month, day);
    final isSelected = _sameDay(date, selected);
    final isToday = _sameDay(date, today);
    final meals = mealsByDay[day] ?? const <MealType>{};
    final count = entryCountByDay[day] ?? 0;

    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: GestureDetector(
          onTap: () => onSelect(date),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? NbColors.ink : NbColors.surface,
              border: Border.all(
                color: isToday ? NbColors.accent : NbColors.ink,
                width: isSelected || isToday ? NbBorders.bold : NbBorders.hair,
              ),
              boxShadow: isSelected ? NbShadows.restrained : null,
            ),
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$day',
                    style: NbType.label.copyWith(
                        color: isSelected ? NbColors.surface : NbColors.ink)),
                const Spacer(),
                if (count > 0)
                  Row(
                    children: [
                      for (final m in MealType.values)
                        if (meals.contains(m))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 2),
                            color: _mealColor[m],
                          ),
                      const Spacer(),
                      Text('$count',
                          style: NbType.label.copyWith(
                              fontSize: 10,
                              color: isSelected
                                  ? NbColors.surface
                                  : NbColors.ink)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.day,
    required this.entries,
    required this.onDelete,
    required this.onAdd,
  });

  final DateTime day;
  final List<MenuEntry> entries;
  final ValueChanged<int> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NbSpace.md),
      children: [
        Text(DateFormat('EEEE, MMMM d').format(day).toUpperCase(),
            style: NbType.heading),
        const SizedBox(height: NbSpace.sm),
        if (entries.isEmpty)
          const NbSurface(
            background: NbColors.surfaceMuted,
            child: Row(
              children: [
                Icon(Icons.restaurant_menu, color: NbColors.ink),
                SizedBox(width: NbSpace.sm),
                Expanded(
                  child:
                      Text('Nothing planned for this day.', style: NbType.body),
                ),
              ],
            ),
          )
        else
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: NbSpace.sm),
              child: NbSurface(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 40,
                      color: _mealColor[e.mealType],
                    ),
                    const SizedBox(width: NbSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${e.mealType.wire.toUpperCase()} · '
                              '${e.categories.join(", ")}',
                              style: NbType.label),
                          Text(e.items.join(', '), style: NbType.body),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete(e.id),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: NbSpace.sm),
        NbButton.secondary(
            label: 'Add an entry for this day', onPressed: onAdd),
      ],
    );
  }
}
