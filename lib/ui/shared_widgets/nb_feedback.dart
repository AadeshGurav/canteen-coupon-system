import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../theme/tokens.dart';
import 'nb_button.dart';
import 'nb_surface.dart';

/// Renders an [AsyncValue] as loading / a specific error / data — never a bare
/// spinner over a blank screen (CLAUDE.md §11.4). The error path shows the
/// [AppException] message verbatim (it's written to be user-safe) and a retry.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(NbSpace.xl),
          child: CircularProgressIndicator(color: NbColors.ink),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(NbSpace.lg),
          child: ErrorPanel(error: error, onRetry: onRetry),
        ),
      ),
      data: builder,
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      AppException e => e.message,
      _ => 'Something went wrong. $error',
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
              Text(isHostDown ? 'HOST UNREACHABLE' : 'ERROR',
                  style: NbType.label.copyWith(color: NbColors.onWarn)),
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

/// A short-lived confirmation line (Peak-End Rule, CLAUDE.md §11.2 — invest in
/// the "it worked" moment).
void showNbSnack(BuildContext context, String message, {bool ok = true}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
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

/// Runs [action], showing a snack on success or the error's message on failure.
/// Returns true on success.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  try {
    await action();
    if (context.mounted && successMessage != null) {
      showNbSnack(context, successMessage);
    }
    return true;
  } on AppException catch (e) {
    if (context.mounted) showNbSnack(context, e.message, ok: false);
    return false;
  } catch (e) {
    if (context.mounted) showNbSnack(context, '$e', ok: false);
    return false;
  }
}
