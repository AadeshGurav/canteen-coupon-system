import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/appearance_providers.dart';
import '../../app/providers.dart';
import '../../services/settings_service.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/appearance.dart';
import '../theme/theme_catalog.dart';
import '../theme/tokens.dart';
import 'theme_preview.dart';

/// Settings ▸ Appearance. Available to every role on every device, because how
/// a screen looks is a property of the screen, not of who signed in.
///
/// When the host enforces an appearance the controls stay visible but go
/// read-only, with the reason stated — silently ignoring a tap is worse than
/// disabling it (CLAUDE.md §11.1 heuristic 1).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final device = ref.watch(deviceAppearanceProvider);
    final effective = ref.watch(effectiveAppearanceProvider);
    final enforced = ref.watch(appearanceIsEnforcedProvider);
    final isAdmin = ref.watch(sessionProvider)?.role.isAdmin ?? false;
    final controller = ref.read(deviceAppearanceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(NbSpace.lg),
        children: [
          if (enforced) ...[
            NbSurface(
              background: t.color.warn,
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: t.color.onWarn),
                  const SizedBox(width: NbSpace.sm),
                  Expanded(
                    child: Text(
                      'The host sets the look for every device here. Your own '
                      'choices are saved and will apply if that is turned off.',
                      style: t.text.body.copyWith(color: t.color.onWarn),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NbSpace.lg),
          ],
          Text('THEME', style: t.text.label),
          const SizedBox(height: NbSpace.sm),
          for (final id in TiffinThemeId.values) ...[
            ThemePreviewCard(
              id: id,
              brightness: effective
                  .brightness(MediaQuery.platformBrightnessOf(context)),
              selected: effective.theme == id,
              enabled: !enforced,
              onTap: () => controller.setTheme(id),
            ),
            const SizedBox(height: NbSpace.sm),
          ],
          const SizedBox(height: NbSpace.md),
          Text('LIGHT OR DARK', style: t.text.label),
          const SizedBox(height: NbSpace.sm),
          _ModeSelector(
            value: effective.mode,
            enabled: !enforced,
            onChanged: controller.setMode,
          ),
          const SizedBox(height: NbSpace.lg),
          Text('MOTION', style: t.text.label),
          const SizedBox(height: NbSpace.sm),
          NbSurface(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Animations', style: t.text.body),
              subtitle: Text(
                effective.motion
                    ? 'Screens slide, tiles fade in, buttons press.'
                    : 'Everything switches instantly.',
                style: t.text.body.copyWith(color: t.color.inkMuted),
              ),
              value: effective.motion,
              onChanged:
                  enforced ? null : (v) => controller.setMotion(enabled: v),
            ),
          ),
          const SizedBox(height: NbSpace.xs),
          Text(
            'Your phone\'s own "reduce motion" accessibility setting always '
            'wins, whatever is chosen here.',
            style: t.text.body.copyWith(color: t.color.inkMuted),
          ),
          if (isAdmin) ...[
            const SizedBox(height: NbSpace.xl),
            _EnforceCard(enforced: enforced, appearance: device),
          ],
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ThemeMode value;
  final bool enabled;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (final (mode, label, icon) in const [
          (ThemeMode.system, 'System', Icons.brightness_auto),
          (ThemeMode.light, 'Light', Icons.light_mode),
          (ThemeMode.dark, 'Dark', Icons.dark_mode),
        ]) ...[
          Expanded(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: NbSurface(
                intensity:
                    value == mode ? NbIntensity.full : NbIntensity.restrained,
                background: value == mode ? t.color.accent : t.color.surface,
                padding: const EdgeInsets.symmetric(vertical: NbSpace.md),
                onTap: enabled ? () => onChanged(mode) : null,
                child: Column(
                  children: [
                    // Selection is carried by fill, border weight AND a check
                    // — never colour alone (§12.2).
                    Icon(icon,
                        color: value == mode
                            ? t.color.on(t.color.accent)
                            : t.color.ink),
                    const SizedBox(height: NbSpace.xs),
                    Text(label,
                        style: t.text.label.copyWith(
                            color: value == mode
                                ? t.color.on(t.color.accent)
                                : t.color.ink)),
                  ],
                ),
              ),
            ),
          ),
          if (mode != ThemeMode.dark) const SizedBox(width: NbSpace.sm),
        ],
      ],
    );
  }
}

/// Host-admin control: push this device's appearance to every device.
class _EnforceCard extends ConsumerStatefulWidget {
  const _EnforceCard({required this.enforced, required this.appearance});

  final bool enforced;
  final Appearance appearance;

  @override
  ConsumerState<_EnforceCard> createState() => _EnforceCardState();
}

class _EnforceCardState extends ConsumerState<_EnforceCard> {
  bool _busy = false;

  Future<void> _apply({required bool enforce}) async {
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(backendProvider).updateSettings(SettingsPatch(
            enforceAppearance: enforce,
            appearanceTheme: widget.appearance.theme.wire,
            appearanceMode: widget.appearance.mode.name,
            appearanceMotion: widget.appearance.motion,
          )),
      successMessage: enforce
          ? 'Every device will use this look.'
          : 'Devices can choose their own look again.',
    );
    if (ok) ref.invalidate(appearancePolicyProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return NbSurface(
      tone: NbTone.system,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FOR EVERY DEVICE', style: t.text.label),
          const SizedBox(height: NbSpace.xs),
          Text(
            widget.enforced
                ? 'Every device on this host is using the look set here. Turn '
                    'this off to let each phone choose its own again.'
                : 'Each phone currently picks its own look. Turn this on to '
                    'make them all match the settings above.',
            style: t.text.body,
          ),
          const SizedBox(height: NbSpace.md),
          if (widget.enforced)
            NbButton.secondary(
              label: 'Let devices choose',
              icon: Icons.lock_open,
              busy: _busy,
              onPressed: _busy ? null : () => _apply(enforce: false),
            )
          else
            NbButton(
              label: 'Use this look everywhere',
              icon: Icons.lock_outline,
              busy: _busy,
              onPressed: _busy ? null : () => _apply(enforce: true),
            ),
        ],
      ),
    );
  }
}
