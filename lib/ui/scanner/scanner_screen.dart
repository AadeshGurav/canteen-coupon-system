import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../../domain/ledger.dart';
import '../shared_widgets/app_shell.dart';
import '../shared_widgets/motion.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// The counter scan point (PRD §6.4). Native camera, full-intensity
/// neobrutalism result state (PRD §14.2): the accept/reject verdict fills the
/// screen and is readable at a glance — colour + icon + border weight + text,
/// never colour alone (PRD §14.3).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key, this.isRoleHome = false});

  /// True when this is the scanner role's home screen rather than a screen
  /// pushed from the admin/counter home. A role home has nothing to pop back
  /// to, so it must carry sign-out itself — otherwise a scanner-role login is
  /// stranded with no way out.
  final bool isRoleHome;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  ScanResult? _result;
  String? _errorMessage;
  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _result != null || _errorMessage != null) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;

    // Debounce the same physical card being read repeatedly.
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inSeconds < 3) return;
    _lastCode = code;
    _lastAt = now;

    setState(() => _busy = true);
    try {
      final result = await ref.read(backendProvider).scan(code);
      if (mounted) setState(() => _result = result);
    } on AppException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() => setState(() {
        _result = null;
        _errorMessage = null;
        _lastCode = null;
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cameraActions = [
      IconButton(
        icon: const Icon(Icons.flash_on),
        tooltip: 'Torch',
        onPressed: () => _controller.toggleTorch(),
      ),
      IconButton(
        icon: const Icon(Icons.cameraswitch),
        tooltip: 'Switch camera',
        onPressed: () => _controller.switchCamera(),
      ),
    ];
    final username = ref.watch(sessionProvider)?.username ?? '';
    return Scaffold(
      backgroundColor: t.color.ink,
      // As a role home there is no back button, so use the shared bar that
      // carries sign-out; pushed from admin/counter the parent already has it.
      appBar: widget.isRoleHome
          ? NbAppBar(title: 'Scan · $username', actions: cameraActions)
          : AppBar(title: const Text('SCAN'), actions: cameraActions),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const _ReticleOverlay(),
          if (_busy)
            Center(
              child: CircularProgressIndicator(color: t.color.surface),
            ),
          // The verdict is the peak moment of the whole app (Peak-End,
          // §11.2), so it pops rather than appears. The camera itself stays
          // still — it is a live preview under a performance budget.
          if (_result != null)
            MotionSwitcher(
              scaleIn: true,
              child: _ResultOverlay(
                key: ValueKey(_result!.outcome),
                result: _result!,
                onNext: _clear,
              ),
            ),
          if (_errorMessage != null)
            _MessageOverlay(
              title: 'SCAN ERROR',
              message: _errorMessage!,
              color: t.color.warn,
              onColor: t.color.onWarn,
              onNext: _clear,
            ),
        ],
      ),
    );
  }
}

class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: t.color.surface, width: t.shape.borderBold),
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({super.key, required this.result, required this.onNext});

  final ScanResult result;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accepted = result.outcome.isAccepted;
    final bg = accepted ? t.color.accept : t.color.reject;
    final fg = accepted ? t.color.onAccept : t.color.onReject;

    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(NbSpace.lg),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(accepted ? Icons.check_circle : Icons.cancel,
                  size: 120, color: fg),
              const SizedBox(height: NbSpace.md),
              Text(
                accepted ? 'ACCEPTED' : 'REJECTED',
                textAlign: TextAlign.center,
                style: t.text.display.copyWith(color: fg, fontSize: 48),
              ),
              const SizedBox(height: NbSpace.md),
              if (result.memberName != null)
                Text(result.memberName!,
                    textAlign: TextAlign.center,
                    style: t.text.heading.copyWith(color: fg)),
              const SizedBox(height: NbSpace.sm),
              Text(
                result.message,
                textAlign: TextAlign.center,
                style: t.text.body.copyWith(color: fg, fontSize: 18),
              ),
              if (result.viaGrace) ...[
                const SizedBox(height: NbSpace.md),
                Align(
                  alignment: Alignment.center,
                  child: NbSurface(
                    background: t.color.warn,
                    intensity: NbIntensity.full,
                    padding: const EdgeInsets.symmetric(
                        horizontal: NbSpace.md, vertical: NbSpace.sm),
                    child: Text('ON GRACE ALLOWANCE',
                        style: t.text.label.copyWith(color: t.color.onWarn)),
                  ),
                ),
              ],
              const SizedBox(height: NbSpace.xl),
              NbButton(
                label: 'Next',
                icon: Icons.qr_code_scanner,
                background: fg,
                foreground: bg,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageOverlay extends StatelessWidget {
  const _MessageOverlay({
    required this.title,
    required this.message,
    required this.color,
    required this.onColor,
    required this.onNext,
  });

  final String title;
  final String message;
  final Color color;
  final Color onColor;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: color,
        padding: const EdgeInsets.all(NbSpace.lg),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.error_outline, size: 96, color: onColor),
              const SizedBox(height: NbSpace.md),
              Text(title,
                  textAlign: TextAlign.center,
                  style: t.text.display.copyWith(color: onColor, fontSize: 40)),
              const SizedBox(height: NbSpace.md),
              Text(message,
                  textAlign: TextAlign.center,
                  style: t.text.body.copyWith(color: onColor, fontSize: 18)),
              const SizedBox(height: NbSpace.xl),
              NbButton(
                label: 'Try again',
                background: onColor,
                foreground: color,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
