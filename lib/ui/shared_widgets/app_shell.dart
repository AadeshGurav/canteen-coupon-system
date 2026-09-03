import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/ops.dart';
import '../theme/tokens.dart';
import 'nb_feedback.dart';

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
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
          onPressed: () => ref.read(sessionProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              decoration: const BoxDecoration(
                color: NbColors.reject,
                border: Border.fromBorderSide(
                    BorderSide(color: NbColors.ink, width: 1.5)),
              ),
              child: Text('${notes.length}',
                  style: NbType.label
                      .copyWith(color: NbColors.onReject, fontSize: 10)),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, WidgetRef ref, List<AppNotification> notes) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NbColors.surface,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: NbColors.ink, width: NbBorders.bold),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NbSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('NOTIFICATIONS', style: NbType.heading),
              const SizedBox(height: NbSpace.md),
              if (notes.isEmpty)
                const Text('Nothing right now.', style: NbType.body)
              else
                ...notes.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: NbSpace.sm),
                    child: ListTile(
                      shape: const RoundedRectangleBorder(
                        side: BorderSide(
                            color: NbColors.ink, width: NbBorders.base),
                      ),
                      title: Text(n.title, style: NbType.label),
                      subtitle: Text(n.message, style: NbType.body),
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
      ),
    );
  }
}
