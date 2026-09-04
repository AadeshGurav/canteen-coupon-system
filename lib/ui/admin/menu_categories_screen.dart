import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/menu.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final _categoriesProvider = FutureProvider.autoDispose<List<MenuCategory>>(
    (ref) => ref.watch(backendProvider).listMenuCategories());

/// Editable menu category list (PRD §6.5) — not a fixed enum.
class MenuCategoriesScreen extends ConsumerWidget {
  const MenuCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final categories = ref.watch(_categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Menu categories')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: t.color.accent,
        foregroundColor: t.color.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () => _form(context, ref, null),
      ),
      body: AsyncView<List<MenuCategory>>(
        value: categories,
        onRetry: () => ref.invalidate(_categoriesProvider),
        loadingLabel: 'Loading categories…',
        empty: NbEmpty(
          icon: Icons.category_outlined,
          title: 'No categories yet',
          quips: EmptyQuips.categories,
          actionLabel: 'Add a category',
          onAction: () => _form(context, ref, null),
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final c = list[i];
            return NbSurface(
              onTap: () => _form(context, ref, c),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: t.text.body),
                        if (c.description != null)
                          Text(c.description!, style: t.text.label),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await runGuarded(
                        context,
                        () =>
                            ref.read(backendProvider).deleteMenuCategory(c.id),
                        successMessage: 'Deleted.',
                      );
                      if (ok) ref.invalidate(_categoriesProvider);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _form(
      BuildContext context, WidgetRef ref, MenuCategory? existing) async {
    final t = context.tokens;
    final name = TextEditingController(text: existing?.name ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New category' : existing.name,
            style: t.text.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NbTextField(label: 'Name', controller: name),
            const SizedBox(height: NbSpace.sm),
            NbTextField(label: 'Description (optional)', controller: desc),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          NbButton(
              label: 'Save', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final saved = await runGuarded(context, () async {
      final backend = ref.read(backendProvider);
      final d = desc.text.trim().isEmpty ? null : desc.text.trim();
      if (existing == null) {
        await backend.createMenuCategory(name.text.trim(), d);
      } else {
        await backend.updateMenuCategory(existing.id,
            name: name.text.trim(), description: d);
      }
    }, successMessage: 'Saved.');
    if (saved) ref.invalidate(_categoriesProvider);
  }
}
