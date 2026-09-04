import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/ops.dart';
import '../settings/appearance_screen.dart';
import '../theme/tokens.dart';
import 'frosted_panel.dart';
import 'nb_feedback.dart';
import 'motion.dart';

enum _ShellAction { appearance, signOut }

/// App bar shared by every signed-in screen: the branding title, the
/// notification bell (PRD §6.5.2), and sign-out.
class NbAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const NbAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Text(title),
      actions: [
        ...?actions,
        const _NotificationBell(),
        // Appearance and sign-out live in an overflow rather than as two more
        // icons: the scan screen already carries torch and camera, and four
        // adjacent icon targets is where mis-taps start (§11.6.5). It also
        // gives every role a way to reach Appearance — scanner and counter
        // have no Settings screen of their own.
        PopupMenuButton<_ShellAction>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'More',
          onSelected: (action) => switch (action) {
            _ShellAction.appearance => Navigator.of(context).push(
                tiffinRoute<void>(context, () => const AppearanceScreen()),
              ),
            _ShellAction.signOut => ref.read(sessionProvider.notifier).logout(),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _ShellAction.appearance,
              child: ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Appearance'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _ShellAction.signOut,
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('Sign out'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final notes = ref.watch(notificationsProvider).asData?.value ?? const [];
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => _open(context, ref, notes),
        ),
        if (notes.isNotEmpty)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: t.color.reject,
                border: Border.fromBorderSide(
                    BorderSide(color: t.color.ink, width: 1.5)),
              ),
              child: Text('${notes.length}',
                  style: t.text.label
                      .copyWith(color: t.color.onReject, fontSize: 10)),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, WidgetRef ref, List<AppNotification> notes) {
    final t = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBackground(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: t.shape.radius.topLeft),
        side: BorderSide(color: t.color.border, width: t.shape.borderBold),
      ),
      builder: (_) => FrostedPanel(
          child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NbSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NOTIFICATIONS', style: t.text.heading),
              const SizedBox(height: NbSpace.md),
              if (notes.isEmpty)
                Text('Nothing right now.', style: t.text.body)
              else
                ...notes.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: NbSpace.sm),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: t.color.ink, width: t.shape.borderBase),
                      ),
                      title: Text(n.title, style: t.text.label),
                      subtitle: Text(n.message, style: t.text.body),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await runGuarded(
                            context,
                            () => ref
                                .read(backendProvider)
                                .dismissNotification(n.id),
                          );
                          ref.invalidate(notificationsProvider);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      )),
    );
  }
}
