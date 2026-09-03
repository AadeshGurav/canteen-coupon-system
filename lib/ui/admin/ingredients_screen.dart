import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/inventory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final ingredientsProvider = FutureProvider.autoDispose<List<Ingredient>>(
    (ref) => ref.watch(backendProvider).listIngredients());

/// Ingredients master list (PRD §6.5.1).
class IngredientsScreen extends ConsumerWidget {
  const IngredientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredients = ref.watch(ingredientsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ingredients')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () => _form(context, ref, null),
      ),
      body: AsyncView<List<Ingredient>>(
        value: ingredients,
        onRetry: () => ref.invalidate(ingredientsProvider),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final ing = list[i];
            return NbSurface(
              onTap: () => _form(context, ref, ing),
              child: Row(
                children: [
                  Expanded(child: Text(ing.name, style: NbType.body)),
                  Text(ing.unit, style: NbType.label),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await runGuarded(
                        context,
                        () =>
                            ref.read(backendProvider).deleteIngredient(ing.id),
                        successMessage: 'Deleted.',
                      );
                      if (ok) ref.invalidate(ingredientsProvider);
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
      BuildContext context, WidgetRef ref, Ingredient? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final unit = TextEditingController(text: existing?.unit ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New ingredient' : existing.name,
            style: NbType.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NbTextField(label: 'Name', controller: name),
            const SizedBox(height: NbSpace.sm),
            NbTextField(label: 'Unit (kg, litre, pcs…)', controller: unit),
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
      if (existing == null) {
        await backend.createIngredient(name.text.trim(), unit.text.trim());
      } else {
        await backend.updateIngredient(existing.id,
            name: name.text.trim(), unit: unit.text.trim());
      }
    }, successMessage: 'Saved.');
    if (saved) ref.invalidate(ingredientsProvider);
  }
}
