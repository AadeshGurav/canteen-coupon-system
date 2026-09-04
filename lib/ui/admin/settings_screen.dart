import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_mode.dart';
import '../../data/backend.dart';
import '../../domain/settings.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_picker.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../settings/appearance_screen.dart';
import '../theme/tokens.dart';
import 'hosting_screen.dart';
import '../shared_widgets/motion.dart';

final _settingsProvider = FutureProvider.autoDispose<SettingsSnapshot>(
    (ref) => ref.watch(backendProvider).getSettings());
final _timezonesProvider = FutureProvider.autoDispose<List<String>>(
    (ref) => ref.watch(backendProvider).timezones());

/// Runtime settings (PRD §6.8). Everything here is DB-backed and editable with
/// no restart. Restrained intensity — dense data form.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(_settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView<SettingsSnapshot>(
        value: settings,
        onRetry: () => ref.invalidate(_settingsProvider),
        builder: (s) => _SettingsForm(initial: s),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});
  final SettingsSnapshot initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _appName = TextEditingController(text: widget.initial.appName);
  late final _lunchPrice = _num(widget.initial.unitPrices.lunch);
  late final _breakfastPrice = _num(widget.initial.unitPrices.breakfast);
  late final _brunchPrice = _num(widget.initial.unitPrices.brunch);
  late final _upiId = TextEditingController(text: widget.initial.upiId);
  late final _upiPayee =
      TextEditingController(text: widget.initial.upiPayeeName);
  late final _graceUnits = _num(widget.initial.graceAllowanceUnits.toDouble());
  late bool _graceEnabled = widget.initial.graceAllowanceEnabled;
  late final _reversal = _num(widget.initial.reversalWindowMinutes.toDouble());
  late final _prepLead = _num(widget.initial.prepLeadMinutes.toDouble());
  late final _purchaseLead = _num(widget.initial.purchaseLeadDays.toDouble());
  late String _timezone = widget.initial.localTimezone;

  late final Map<String, (TextEditingController, TextEditingController)>
      _windows = {
    for (final m in const ['breakfast', 'lunch', 'brunch'])
      m: (
        TextEditingController(text: widget.initial.mealWindows[m]!.start),
        TextEditingController(text: widget.initial.mealWindows[m]!.end),
      ),
  };

  bool _busy = false;

  TextEditingController _num(double v) => TextEditingController(
      text: v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      await ref.read(backendProvider).updateSettings(SettingsPatch(
            appName: _appName.text.trim(),
            unitPrices: UnitPrices(
              lunch: double.tryParse(_lunchPrice.text) ?? 0,
              breakfast: double.tryParse(_breakfastPrice.text) ?? 0,
              brunch: double.tryParse(_brunchPrice.text) ?? 0,
            ),
            upiId: _upiId.text.trim(),
            upiPayeeName: _upiPayee.text.trim(),
            graceAllowanceEnabled: _graceEnabled,
            graceAllowanceUnits: int.tryParse(_graceUnits.text) ?? 0,
            reversalWindowMinutes: int.tryParse(_reversal.text) ?? 10,
            prepLeadMinutes: int.tryParse(_prepLead.text) ?? 60,
            purchaseLeadDays: int.tryParse(_purchaseLead.text) ?? 1,
            localTimezone: _timezone,
            mealWindows: {
              for (final e in _windows.entries)
                e.key: MealWindowConfig(
                    start: e.value.$1.text.trim(), end: e.value.$2.text.trim()),
            },
          ));
    }, successMessage: 'Settings saved.');
    if (mounted) setState(() => _busy = false);
    if (ok) ref.invalidate(_settingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final zones = ref.watch(_timezonesProvider).asData?.value ?? [_timezone];
    final isHost = ref.watch(currentModeProvider) == AppMode.host;
    final serving = isHost && ref.watch(hostRunningProvider);
    return ListView(
      padding: const EdgeInsets.all(NbSpace.lg),
      children: [
        if (isHost) ...[
          NbSurface(
            onTap: () => Navigator.of(context)
                .push(tiffinRoute<void>(context, () => const HostingScreen())),
            child: Row(
              children: [
                Icon(serving ? Icons.wifi_tethering : Icons.wifi_off,
                    color: serving ? t.color.accept : t.color.reject),
                const SizedBox(width: NbSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HOSTING & LAN', style: t.text.label),
                      Text(
                        serving
                            ? 'Serving. Manage URLs, restart, certificate.'
                            : 'Not serving. Tap to start.',
                        style: t.text.body,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: t.color.ink),
              ],
            ),
          ),
          const SizedBox(height: NbSpace.sm),
        ],
        _section(t, 'Branding'),
        NbTextField(label: 'App name', controller: _appName),
        _section(t, 'Unit prices (Rs.)'),
        NbTextField(
            label: 'Lunch',
            controller: _lunchPrice,
            keyboardType: TextInputType.number),
        const SizedBox(height: NbSpace.sm),
        NbTextField(
            label: 'Breakfast',
            controller: _breakfastPrice,
            keyboardType: TextInputType.number),
        const SizedBox(height: NbSpace.sm),
        NbTextField(
            label: 'Brunch',
            controller: _brunchPrice,
            keyboardType: TextInputType.number),
        _section(t, 'Meal windows (HH:MM, 24h)'),
        for (final m in const ['breakfast', 'lunch', 'brunch'])
          Padding(
            padding: const EdgeInsets.only(bottom: NbSpace.sm),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(m, style: t.text.label)),
                Expanded(
                    child: NbTextField(
                        label: 'start', controller: _windows[m]!.$1)),
                const SizedBox(width: NbSpace.sm),
                Expanded(
                    child:
                        NbTextField(label: 'end', controller: _windows[m]!.$2)),
              ],
            ),
          ),
        _section(t, 'Timezone (IANA)'),
        NbPickerField(
          label: 'Timezone',
          value: zones.contains(_timezone) ? _timezone : zones.first,
          options: zones,
          onSelected: (z) => setState(() => _timezone = z),
        ),
        _section(t, 'Grace allowance'),
        SwitchListTile(
          title: Text('Enabled', style: t.text.body),
          value: _graceEnabled,
          onChanged: (v) => setState(() => _graceEnabled = v),
        ),
        NbTextField(
            label: 'Default grace units',
            controller: _graceUnits,
            keyboardType: TextInputType.number),
        _section(t, 'Windows & reminders'),
        NbTextField(
            label: 'Scan reversal window (minutes)',
            controller: _reversal,
            keyboardType: TextInputType.number),
        const SizedBox(height: NbSpace.sm),
        NbTextField(
            label: 'Prep reminder lead (minutes)',
            controller: _prepLead,
            keyboardType: TextInputType.number),
        const SizedBox(height: NbSpace.sm),
        NbTextField(
            label: 'Purchase reminder lead (days)',
            controller: _purchaseLead,
            keyboardType: TextInputType.number),
        _section(t, 'UPI'),
        NbTextField(label: 'UPI ID (blank = cash only)', controller: _upiId),
        const SizedBox(height: NbSpace.sm),
        NbTextField(label: 'Payee name', controller: _upiPayee),
        const SizedBox(height: NbSpace.lg),
        NbButton(
            label: 'Save settings',
            busy: _busy,
            onPressed: _busy ? null : _save),
        _section(t, 'Device'),
        NbSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This device is running as ${isHost ? 'HOST' : 'CLIENT'}.',
                  style: t.text.body),
              const SizedBox(height: NbSpace.xs),
              Text(
                'Switching role signs you out and returns to setup. Nothing is '
                'deleted — the host database stays on this device.',
                style: t.text.body,
              ),
              const SizedBox(height: NbSpace.md),
              NbButton.secondary(
                label: 'Appearance',
                icon: Icons.palette_outlined,
                onPressed: () => Navigator.of(context).push(
                  tiffinRoute<void>(context, () => const AppearanceScreen()),
                ),
              ),
              const SizedBox(height: NbSpace.sm),
              NbButton.secondary(
                label: 'Switch device role',
                icon: Icons.swap_horiz,
                onPressed: () => _confirmSwitchRole(context, ref),
              ),
            ],
          ),
        ),
        if (isHost) ...[
          const SizedBox(height: NbSpace.md),
          NbSurface(
            intensity: NbIntensity.full,
            background: t.color.reject,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RESET ALL DATA',
                    style: t.text.label.copyWith(color: t.color.onReject)),
                const SizedBox(height: NbSpace.xs),
                Text(
                  'Permanently deletes every member, top-up, scan, bill, menu '
                  'entry and user on this host. There is no undo and no backup. '
                  'The device returns to first-run setup.',
                  style: t.text.body.copyWith(color: t.color.onReject),
                ),
                const SizedBox(height: NbSpace.md),
                NbButton(
                  label: 'Reset all data',
                  icon: Icons.delete_forever,
                  background: t.color.surface,
                  foreground: t.color.reject,
                  onPressed: () => _confirmReset(context, ref),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: NbSpace.xl),
      ],
    );
  }

  Future<void> _confirmSwitchRole(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Switch device role?'),
        content: const Text(
            'You will be signed out and taken back to Host / Client setup. '
            'Your data is not touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (ok == true) await ref.read(currentModeProvider.notifier).clear();
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetConfirmDialog(),
    );
    if (ok == true && context.mounted) {
      await runGuarded(
        context,
        () => ref.read(hostServingProvider.notifier).resetAllData(),
        successMessage: 'All data cleared. Set the device up again.',
      );
    }
  }

  Widget _section(TiffinTokens t, String label) => Padding(
        padding: const EdgeInsets.only(top: NbSpace.lg, bottom: NbSpace.sm),
        child: Text(label.toUpperCase(), style: t.text.heading),
      );
}

/// Type-to-confirm guard for the destructive data reset.
class _ResetConfirmDialog extends StatefulWidget {
  const _ResetConfirmDialog();

  @override
  State<_ResetConfirmDialog> createState() => _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends State<_ResetConfirmDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = _field.text.trim() == 'RESET';
    return AlertDialog(
      title: const Text('Reset all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This cannot be undone. Type RESET to confirm.'),
          const SizedBox(height: NbSpace.sm),
          TextField(
            controller: _field,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'RESET'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: armed ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
