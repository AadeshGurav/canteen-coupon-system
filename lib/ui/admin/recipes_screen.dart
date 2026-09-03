import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/inventory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';
import 'ingredients_screen.dart';

final _recipesProvider = FutureProvider.autoDispose<List<Recipe>>(
    (ref) => ref.watch(backendProvider).listRecipes());

/// Recipes (PRD §6.5.1): a dish name (matched case-insensitively against menu
/// items) linked to ingredients with free-text quantity notes.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(_recipesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () => _form(context, ref, null),
      ),
      body: AsyncView<List<Recipe>>(
        value: recipes,
        onRetry: () => ref.invalidate(_recipesProvider),
        loadingLabel: 'Loading recipes…',
        empty: NbEmpty(
          icon: Icons.menu_book_outlined,
          title: 'No recipes yet',
          quips: EmptyQuips.recipes,
          actionLabel: 'Add a recipe',
          onAction: () => _form(context, ref, null),
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final r = list[i];
            return NbSurface(
              onTap: () => _form(context, ref, r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.dishName, style: NbType.body),
                  Text('${r.ingredients.length} ingredient(s)',
                      style: NbType.label),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _form(
      BuildContext context, WidgetRef ref, Recipe? existing) async {
    final allIngredients = await ref.read(ingredientsProvider.future);
    if (!context.mounted) return;
    final dish = TextEditingController(text: existing?.dishName ?? '');
    final lines = <({int ingredientId, TextEditingController note})>[
      for (final ri in existing?.ingredients ?? const <RecipeIngredient>[])
        (
          ingredientId: ri.ingredientId,
          note: TextEditingController(text: ri.quantityNote)
        ),
    ];
    if (lines.isEmpty && allIngredients.isNotEmpty) {
      lines.add((
        ingredientId: allIngredients.first.id,
        note: TextEditingController()
      ));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New recipe' : existing.dishName,
              style: NbType.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NbTextField(label: 'Dish name', controller: dish),
                const SizedBox(height: NbSpace.md),
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NbSpace.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButton<int>(
                            value: lines[i].ingredientId,
                            isExpanded: true,
                            items: [
                              for (final ing in allIngredients)
                                DropdownMenuItem(
                                    value: ing.id, child: Text(ing.name)),
                            ],
                            onChanged: (v) => setLocal(() => lines[i] = (
                                  ingredientId: v ?? lines[i].ingredientId,
                                  note: lines[i].note
                                )),
                          ),
                        ),
                        const SizedBox(width: NbSpace.sm),
                        Expanded(
                          child: NbTextField(
                              label: 'qty note', controller: lines[i].note),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add ingredient'),
                  onPressed: allIngredients.isEmpty
                      ? null
                      : () => setLocal(() => lines.add((
                            ingredientId: allIngredients.first.id,
                            note: TextEditingController()
                          ))),
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
    final ingredients = [
      for (final l in lines)
        if (l.note.text.trim().isNotEmpty)
          RecipeIngredient(
              ingredientId: l.ingredientId, quantityNote: l.note.text.trim()),
    ];
    final saved = await runGuarded(context, () async {
      final backend = ref.read(backendProvider);
      if (existing == null) {
        await backend.createRecipe(
            RecipeDraft(dishName: dish.text.trim(), ingredients: ingredients));
      } else {
        await backend.updateRecipe(existing.id,
            dishName: dish.text.trim(), ingredients: ingredients);
      }
    }, successMessage: 'Saved.');
    if (saved) ref.invalidate(_recipesProvider);
  }
}
