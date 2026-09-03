import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/role.dart';
import '../../domain/ops.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

final _usersProvider = FutureProvider.autoDispose<List<AppUser>>(
    (ref) => ref.watch(backendProvider).listUsers());

/// Login-account management (PRD §4). Admin-only.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(_usersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NbColors.accent,
        foregroundColor: NbColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('New user'),
        onPressed: () => _form(context, ref, null),
      ),
      body: AsyncView<List<AppUser>>(
        value: users,
        onRetry: () => ref.invalidate(_usersProvider),
        loadingLabel: 'Loading users…',
        empty: NbEmpty(
          icon: Icons.admin_panel_settings,
          title: 'Only you so far',
          quips: EmptyQuips.users,
          actionLabel: 'Add a user',
          onAction: () => _form(context, ref, null),
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final u = list[i];
            return NbSurface(
              onTap: () => _form(context, ref, u),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.username, style: NbType.body),
                        Text('${u.role.wire} · ${u.status}',
                            style: NbType.label),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await runGuarded(
                        context,
                        () => ref.read(backendProvider).deleteUser(u.id),
                        successMessage: 'User deleted.',
                      );
                      if (ok) ref.invalidate(_usersProvider);
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
      BuildContext context, WidgetRef ref, AppUser? existing) async {
    final username = TextEditingController(text: existing?.username ?? '');
    final password = TextEditingController();
    var role = existing?.role ?? Role.counter;
    var status = existing?.status ?? 'active';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New user' : existing.username,
              style: NbType.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing == null)
                  NbTextField(label: 'Username', controller: username),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                  label: existing == null
                      ? 'Password'
                      : 'New password (blank = keep)',
                  controller: password,
                  obscure: true,
                ),
                const SizedBox(height: NbSpace.sm),
                DropdownButton<Role>(
                  value: role,
                  isExpanded: true,
                  items: [
                    for (final r in Role.values)
                      DropdownMenuItem(value: r, child: Text(r.wire)),
                  ],
                  onChanged: (r) => setLocal(() => role = r ?? role),
                ),
                if (existing != null)
                  DropdownButton<String>(
                    value: status,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('active')),
                      DropdownMenuItem(
                          value: 'inactive', child: Text('inactive')),
                    ],
                    onChanged: (s) => setLocal(() => status = s ?? status),
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

    final saved = await runGuarded(context, () async {
      final backend = ref.read(backendProvider);
      if (existing == null) {
        await backend.createUser(UserDraft(
          username: username.text.trim(),
          password: password.text,
          role: role,
        ));
      } else {
        await backend.updateUser(
          existing.id,
          UserPatch(
            password: password.text.isEmpty ? null : password.text,
            role: role,
            status: status,
          ),
        );
      }
    }, successMessage: 'User saved.');
    if (saved) ref.invalidate(_usersProvider);
  }
}
