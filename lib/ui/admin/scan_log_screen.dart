import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/ledger.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

final _scansProvider = FutureProvider.autoDispose<List<ScanRecord>>(
    (ref) => ref.watch(backendProvider).recentScans(limit: 300));

/// Scan audit log + reversal (PRD §6.4). Reversal is only offered on an
/// accepted, not-yet-reversed scan; the host still enforces the time window.
class ScanLogScreen extends ConsumerWidget {
  const ScanLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final scans = ref.watch(_scansProvider);
    final fmt = DateFormat('MMM d, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Scan log')),
      body: AsyncView<List<ScanRecord>>(
        value: scans,
        onRetry: () => ref.invalidate(_scansProvider),
        loadingLabel: 'Loading the scan log…',
        empty: const NbEmpty(
          icon: Icons.qr_code_scanner,
          title: 'No scans yet',
          quips: EmptyQuips.scans,
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) {
            final s = list[i];
            final reversible = s.result == 'accepted' && !s.reversed;
            return NbSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${s.memberName} · ${s.mealType.wire}',
                            style: t.text.body),
                      ),
                      if (s.reversed)
                        Text('REVERSED',
                            style: t.text.label.copyWith(color: t.color.reject))
                      else if (s.viaGrace)
                        Text('GRACE',
                            style: t.text.label.copyWith(color: t.color.warn)),
                    ],
                  ),
                  Text(fmt.format(s.scannedAt.toLocal()), style: t.text.label),
                  if (reversible) ...[
                    const SizedBox(height: NbSpace.sm),
                    NbButton.secondary(
                      label: 'Reverse',
                      onPressed: () async {
                        final ok = await runGuarded(
                          context,
                          () async {
                            final r = await ref
                                .read(backendProvider)
                                .reverseScan(s.id);
                            if (!r.success) {
                              throw _Msg(r.message);
                            }
                          },
                          successMessage: 'Scan reversed.',
                        );
                        if (ok) ref.invalidate(_scansProvider);
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Msg implements Exception {
  _Msg(this.message);
  final String message;
  @override
  String toString() => message;
}
