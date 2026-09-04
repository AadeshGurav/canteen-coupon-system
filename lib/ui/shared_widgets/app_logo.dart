import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The Tiffin mark: a coupon stub with a torn perforation.
///
/// Drawn from the active theme's tokens rather than shipped as artwork, so it
/// carries each theme's own border weight, corner radius and shadow — hard and
/// square under Neobrutal, puffy and round under Clay — without four sets of
/// PNGs to keep in sync. It also stays sharp at any size.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CouponPainter(
          fill: t.color.accent,
          ink: t.color.on(t.color.accent),
          border: t.color.border,
          shadow: t.color.shadow,
          // A zero-radius theme keeps a hard corner; a round one gets a stub
          // that matches its cards.
          radius: t.shape.radius.topLeft.x.clamp(0.0, size / 3),
          borderWidth: t.shape.borderBase,
          // Neobrutalism's shadow is a hard offset with no blur; the softer
          // themes blur theirs. Reading both off the token keeps them honest.
          shadowOffset: t.shape.shadowRestrained.isEmpty
              ? Offset.zero
              : t.shape.shadowRestrained.first.offset,
          shadowBlur: t.shape.shadowRestrained.isEmpty
              ? 0
              : t.shape.shadowRestrained.first.blurRadius,
        ),
      ),
    );
  }
}

class _CouponPainter extends CustomPainter {
  _CouponPainter({
    required this.fill,
    required this.ink,
    required this.border,
    required this.shadow,
    required this.radius,
    required this.borderWidth,
    required this.shadowOffset,
    required this.shadowBlur,
  });

  final Color fill;
  final Color ink;
  final Color border;
  final Color shadow;
  final double radius;
  final double borderWidth;
  final Offset shadowOffset;
  final double shadowBlur;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = borderWidth / 2 + shadowOffset.dx.abs() / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset + size.height * 0.12,
      size.width - inset * 2,
      size.height * 0.76 - inset,
    );
    final notch = rect.height * 0.18;
    final body = _couponPath(rect, radius, notch);

    if (shadowOffset != Offset.zero) {
      final shadowPaint = Paint()..color = shadow.withValues(alpha: 0.5);
      if (shadowBlur > 0) {
        shadowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur);
      }
      canvas.drawPath(body.shift(shadowOffset), shadowPaint);
    }

    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(
      body,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // The perforation: what makes it read as a coupon rather than a card.
    final x = rect.left + rect.width * 0.42;
    final dash = rect.height / 9;
    final perforation = Paint()
      ..color = ink
      ..strokeWidth = borderWidth * 0.7
      ..strokeCap = StrokeCap.round;
    for (var y = rect.top + dash * 0.8;
        y < rect.bottom - dash * 0.4;
        y += dash * 1.7) {
      canvas.drawLine(Offset(x, y),
          Offset(x, (y + dash * 0.8).clamp(0, rect.bottom)), perforation);
    }

    // A single bar on the stub — a value line, not a letter, so the mark
    // doesn't need a font to render identically everywhere.
    final barLeft = x + rect.width * 0.12;
    final barWidth = rect.width * 0.34;
    for (final (dy, w) in [(0.38, 1.0), (0.58, 0.62)]) {
      canvas.drawLine(
        Offset(barLeft, rect.top + rect.height * dy),
        Offset(barLeft + barWidth * w, rect.top + rect.height * dy),
        Paint()
          ..color = ink
          ..strokeWidth = borderWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// A rounded rect with a semicircular bite out of each long edge.
  Path _couponPath(Rect rect, double radius, double notch) {
    final rounded = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final bites = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(rect.left + rect.width * 0.42, rect.top),
          radius: notch))
      ..addOval(Rect.fromCircle(
          center: Offset(rect.left + rect.width * 0.42, rect.bottom),
          radius: notch));
    return Path.combine(PathOperation.difference, rounded, bites);
  }

  @override
  bool shouldRepaint(_CouponPainter old) =>
      old.fill != fill ||
      old.ink != ink ||
      old.border != border ||
      old.radius != radius ||
      old.borderWidth != borderWidth ||
      old.shadowOffset != shadowOffset;
}

/// The logo beside the wordmark — the app's identity block, used on the splash
/// and the mode picker so both stay in step with the theme.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.logoSize = 48, this.style});

  final double logoSize;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: NbSpace.sm),
        Text('TIFFIN',
            style: (style ?? t.text.display).copyWith(letterSpacing: 2)),
      ],
    );
  }
}
