import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../theme/tokens.dart';
import 'nb_button.dart';
import 'nb_surface.dart';

/// Renders an [AsyncValue] as loading / a specific error / empty / data — never
/// a bare spinner over a blank screen, never a blank screen for "no rows yet"
/// (CLAUDE.md §11.4, §11.1 #1). The error path shows the [AppException] message
/// verbatim and a retry.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.empty,
    this.isEmpty,
    this.loadingLabel,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  /// Shown when the loaded data is "empty". If [isEmpty] is null and [T] is an
  /// Iterable, emptiness is detected automatically.
  final Widget? empty;
  final bool Function(T data)? isEmpty;

  /// Text under the spinner while loading (e.g. "Loading members…").
  final String? loadingLabel;

  bool _emptyCheck(T data) {
    if (isEmpty != null) return isEmpty!(data);
    if (data is Iterable) return data.isEmpty;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => NbLoading(label: loadingLabel),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(NbSpace.lg),
          child: ErrorPanel(error: error, onRetry: onRetry),
        ),
      ),
      data: (data) =>
          (empty != null && _emptyCheck(data)) ? empty! : builder(data),
    );
  }
}

/// The one loading state — a spinner plus a line saying what's happening, so
/// the user is never left guessing (Doherty Threshold, CLAUDE.md §11.2).
class NbLoading extends StatelessWidget {
  const NbLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child:
                CircularProgressIndicator(color: NbColors.ink, strokeWidth: 4),
          ),
          const SizedBox(height: NbSpace.md),
          Text(label ?? 'Loading…', style: NbType.label),
        ],
      ),
    );
  }
}

/// Empty-state block — a bit of personality instead of a void (Aesthetic-
/// Usability Effect, CLAUDE.md §11.2). Give it a [title]; a random quip from
/// [quips] fills the subline.
class NbEmpty extends StatelessWidget {
  const NbEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.quips,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final List<String> quips;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final quip = quips[Random().nextInt(quips.length)];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NbSpace.lg),
        child: NbSurface(
          intensity: NbIntensity.full,
          background: NbColors.surfaceMuted,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: NbColors.ink),
              const SizedBox(height: NbSpace.sm),
              Text(title, textAlign: TextAlign.center, style: NbType.heading),
              const SizedBox(height: NbSpace.xs),
              Text(quip, textAlign: TextAlign.center, style: NbType.body),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: NbSpace.md),
                NbButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Funny empty-state quips per domain — kept in one place so the tone stays
/// consistent. Pair with a [NbEmpty].
class EmptyQuips {
  const EmptyQuips._();

  static const members = [
    'Not a soul on the list yet. Add your first hungry human.',
    'Emptier than the canteen at 3pm. Tap + to add someone.',
    'Zero members. Big "new school" energy.',
  ];
  static const topups = [
    'No top-ups yet. The ledger is squeaky clean.',
    'Nobody has paid up. Suspicious. Or just new.',
  ];
  static const scans = [
    'No scans yet. The scanner is well-rested.',
    'Nothing scanned. Peaceful, isn\'t it?',
  ];
  static const menu = [
    'No menu planned. Chef\'s surprise, then?',
    'Blank calendar. The kitchen awaits your genius.',
  ];
  static const categories = [
    'No categories. "Jain", "Normal", "Staff" — your call.',
  ];
  static const ingredients = [
    'Pantry\'s empty on paper. Add what you actually buy.',
  ];
  static const recipes = [
    'No recipes. The dishes are keeping their secrets.',
  ];
  static const purchase = [
    'Shopping list is empty. Either you\'re stocked, or menus need planning.',
    'Nothing to buy. Rare. Enjoy it.',
  ];
  static const expenses = [
    'No expenses logged. Profit looks amazing from here.',
  ];
  static const refunds = [
    'No refunds. Everyone\'s eating what they paid for.',
  ];
  static const users = [
    'Just you so far. Add a counter or scanner account when you need one.',
  ];
  static const notifications = [
    'All quiet. Nothing needs you right now.',
  ];
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (error) {
      HostUnreachableException e => ('HOST UNREACHABLE', e.message),
      AuthException e => ('SESSION PROBLEM', e.message),
      AppException e => ('ERROR · ${e.code}', e.message),
      _ => ('SOMETHING BROKE', '$error'),
    };
    final isHostDown = error is HostUnreachableException;
    return NbSurface(
      background: NbColors.warn,
      intensity: NbIntensity.full,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: NbColors.onWarn),
              const SizedBox(width: NbSpace.sm),
              Flexible(
                child: Text(title,
                    style: NbType.label.copyWith(color: NbColors.onWarn)),
              ),
            ],
          ),
          const SizedBox(height: NbSpace.sm),
          Text(message, style: NbType.body.copyWith(color: NbColors.onWarn)),
          if (onRetry != null) ...[
            const SizedBox(height: NbSpace.md),
            NbButton(
              label: isHostDown ? 'Retry' : 'Try again',
              icon: Icons.refresh,
              background: NbColors.ink,
              foreground: NbColors.surface,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// A short-lived confirmation/error line (Peak-End Rule, CLAUDE.md §11.2).
void showNbSnack(
  BuildContext context,
  String message, {
  bool ok = true,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: ok ? NbColors.accept : NbColors.reject,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: NbColors.ink, width: NbBorders.base),
          borderRadius: NbBorders.radius,
        ),
        content: Row(
          children: [
            Icon(ok ? Icons.check : Icons.close,
                color: ok ? NbColors.onAccept : NbColors.onReject),
            const SizedBox(width: NbSpace.sm),
            Expanded(
              child: Text(message,
                  style: NbType.body.copyWith(
                      color: ok ? NbColors.onAccept : NbColors.onReject)),
            ),
          ],
        ),
      ),
    );
}

/// Runs [action] with visible feedback the whole way:
///  * an immediate "Working…" line (so a slow action never looks frozen),
///  * a success line ([successMessage] or "Done."),
///  * on failure, the error's own message + code — never a silent no-op.
/// Returns true on success.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
  String workingMessage = 'Working…',
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(
      duration: const Duration(minutes: 1),
      backgroundColor: NbColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: NbColors.ink, width: NbBorders.base),
      ),
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: NbColors.surface),
          ),
          const SizedBox(width: NbSpace.sm),
          Text(workingMessage,
              style: NbType.body.copyWith(color: NbColors.surface)),
        ],
      ),
    ));

  try {
    await action();
    if (context.mounted) {
      showNbSnack(context, successMessage ?? 'Done.');
    } else {
      messenger?.clearSnackBars();
    }
    return true;
  } on AppException catch (e) {
    if (context.mounted) {
      showNbSnack(context, '${e.message}  [${e.code}]',
          ok: false, duration: const Duration(seconds: 5));
    } else {
      messenger?.clearSnackBars();
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      showNbSnack(context, 'Unexpected: $e',
          ok: false, duration: const Duration(seconds: 5));
    } else {
      messenger?.clearSnackBars();
    }
    return false;
  }
}
