import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The motion this device should actually use, right now.
///
/// Three things can switch it off and any one of them wins: the device's own
/// Appearance setting, a host policy, and the phone's system "reduce motion"
/// accessibility preference. The OS preference is read here rather than baked
/// into the theme because it belongs to the viewer, not the app, and it can
/// change while the app is running (CLAUDE.md §11.5.0 rule 6).
MotionTokens motionOf(BuildContext context) {
  final tokens = context.tokens.motion;
  if (tokens.isStill) return MotionTokens.still;
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? MotionTokens.still
      : tokens;
}

/// Fades and lifts a widget into place, optionally staggered by [index].
///
/// Everything routes through this rather than each screen rolling its own, so
/// "animations off" is one branch in one place instead of a flag threaded
/// through every list.
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 0.06),
  });

  final Widget child;

  /// Position in a list or grid. Later items start later, which is what makes
  /// a grid read as arriving rather than blinking.
  final int index;

  /// Where it travels from, as a fraction of its own size.
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final motion = motionOf(context);
    if (motion.isStill) return child;

    // Cap the stagger: the fourteenth tile of a grid must not sit visibly
    // waiting its turn.
    final delay = motion.staggerStep * (index.clamp(0, 8));

    return _DelayedBuilder(
      delay: delay,
      duration: motion.normal,
      curve: motion.entrance,
      builder: (context, t) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: FractionalTranslation(
          translation: Offset(offset.dx * (1 - t), offset.dy * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// Drives 0 → 1 once, holding at 0 for [delay] first.
///
/// The wait is an [Interval] on the curve rather than a `Future.delayed`, so
/// there is no timer to cancel: disposing the controller stops everything, and
/// a widget test never ends with a pending timer it has to pump away.
class _DelayedBuilder extends StatefulWidget {
  const _DelayedBuilder({
    required this.delay,
    required this.duration,
    required this.curve,
    required this.builder,
  });

  final Duration delay;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext, double) builder;

  @override
  State<_DelayedBuilder> createState() => _DelayedBuilderState();
}

class _DelayedBuilderState extends State<_DelayedBuilder>
    with SingleTickerProviderStateMixin {
  late final Duration _total = widget.delay + widget.duration;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  )..forward();

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _total == Duration.zero
          ? 0
          : widget.delay.inMicroseconds / _total.inMicroseconds,
      1,
      curve: widget.curve,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => widget.builder(context, _animation.value),
      );
}

/// Shrinks its child while pressed, by the amount the theme asks for.
///
/// Touch feedback has to land within ~100ms or the tap feels dropped, which is
/// why this exists even though Neobrutal deliberately has no ripple.
class PressEffect extends StatefulWidget {
  const PressEffect({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final motion = motionOf(context);
    if (widget.onTap == null) return widget.child;
    if (motion.isStill || motion.pressScale == 1.0) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? motion.pressScale : 1.0,
        duration: motion.fast,
        curve: motion.curve,
        child: widget.child,
      ),
    );
  }
}

/// Cross-fades between states — a loading spinner giving way to data, or a
/// scan verdict replacing the camera.
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({super.key, required this.child, this.scaleIn = false});

  final Widget child;

  /// Adds a slight pop, for a moment that should feel like an answer arriving.
  final bool scaleIn;

  @override
  Widget build(BuildContext context) {
    final motion = motionOf(context);
    if (motion.isStill) return child;

    return AnimatedSwitcher(
      duration: motion.normal,
      switchInCurve: motion.entrance,
      switchOutCurve: motion.curve,
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (!scaleIn) return fade;
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: fade,
        );
      },
      child: child,
    );
  }
}

/// Pushes a screen with the active theme's own transition, replacing the bare
/// [MaterialPageRoute] every screen used to push.
///
/// A function rather than a Route subclass because the duration lives in the
/// theme, which needs a context — so it can only be resolved at push time.
Route<T> tiffinRoute<T>(BuildContext context, Widget Function() build) {
  final duration = motionOf(context).page;
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => build(),
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondary, child) {
      final motion = motionOf(context);
      if (motion.isStill) return child;
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: motion.curve)),
          child: child,
        ),
      );
    },
  );
}
