import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../../services/backup_service.dart';
import '../../services/report_service.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

/// Admin ▸ Reports & backup. Host-only: both read the whole database.
///
/// Two jobs kept deliberately separate. The spreadsheet is for people — read
/// it, print it, pivot it — and is export-only, because a round trip through
/// Excel loses types and ids and would be a route to corrupt balances. The
/// backup file is for machines, and is the supported way to move a canteen to
/// a new phone.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _sections = {...ReportSection.all};
  DateTimeRange? _range;
  bool _busy = false;

  final _passphrase = TextEditingController();
  bool _protect = true;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  /// Hands [bytes] to the OS share sheet — the one path that reaches email,
  /// Drive, WhatsApp and "Save to Files" without this app needing storage
  /// permissions of its own.
  ///
  /// Uses `printing`, already here for top-up bills, rather than share_plus:
  /// that pulls package_info_plus, which does not compile under this Flutter's
  /// built-in Kotlin changes. Despite the name, sharePdf shares whatever bytes
  /// and filename it is given.
  Future<void> _share(List<int> bytes, String name, String subject) async {
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: name,
      subject: subject,
    );
  }

  Future<void> _exportReport() async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final container = await ref.read(hostContainerProvider.future);
      final bytes = await container.reports.build(
        start: _range?.start,
        end: _range?.end,
        sections: _sections,
      );
      await _share(bytes, container.reports.fileName(), 'Tiffin report');
    }, successMessage: 'Report ready.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportBackup() async {
    if (_protect && _passphrase.text.length < 4) {
      showNbSnack(context, 'Choose a password, or turn protection off.',
          ok: false);
      return;
    }
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final container = await ref.read(hostContainerProvider.future);
      final bytes = await container.backups
          .export(passphrase: _protect ? _passphrase.text : null);
      await _share(bytes, container.backups.fileName(), 'Tiffin backup');
    }, successMessage: 'Backup ready. Keep it somewhere safe.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile();
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final container = await ref.read(hostContainerProvider.future);
    if (!mounted) return;

    // Read the manifest before asking for anything: it tells the admin what
    // they are about to overwrite their canteen with.
    final BackupManifest manifest;
    try {
      manifest = container.backups.inspect(bytes);
    } on AppException catch (e) {
      if (mounted) showNbSnack(context, e.message, ok: false);
      return;
    }

    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreConfirmDialog(manifest: manifest),
    );
    if (passphrase == null || !mounted) return;

    setState(() => _busy = true);
    await runGuarded(context, () async {
      await ref.read(hostServingProvider.notifier).restoreFromBackup(
            bytes,
            passphrase: passphrase.isEmpty ? null : passphrase,
          );
    }, successMessage: 'Restored. Sign in again to continue.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rangeLabel = _range == null
        ? 'Everything'
        : '${DateFormat('d MMM y').format(_range!.start)} – '
            '${DateFormat('d MMM y').format(_range!.end)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & backup')),
      body: ListView(
        padding: const EdgeInsets.all(NbSpace.lg),
        children: [
          NbSurface(
            tone: NbTone.money,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SPREADSHEET REPORT', style: t.text.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  'An .xlsx you can open in Excel or Google Sheets. For '
                  'reading and printing — it is not a way to put data back.',
                  style: t.text.body,
                ),
                const SizedBox(height: NbSpace.md),
                Row(
                  children: [
                    Expanded(child: Text(rangeLabel, style: t.text.body)),
                    TextButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: const Text('Dates'),
                      onPressed: _busy ? null : _pickRange,
                    ),
                    if (_range != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'All dates',
                        onPressed: () => setState(() => _range = null),
                      ),
                  ],
                ),
                const SizedBox(height: NbSpace.sm),
                Wrap(
                  spacing: NbSpace.sm,
                  children: [
                    for (final section in ReportSection.values)
                      FilterChip(
                        label: Text(section.label),
                        selected: _sections.contains(section),
                        onSelected: _busy
                            ? null
                            : (on) => setState(() => on
                                ? _sections.add(section)
                                : _sections.remove(section)),
                      ),
                  ],
                ),
                const SizedBox(height: NbSpace.md),
                NbButton(
                  label: 'Export spreadsheet',
                  icon: Icons.table_view,
                  busy: _busy,
                  onPressed: _busy ? null : _exportReport,
                ),
              ],
            ),
          ),
          const SizedBox(height: NbSpace.lg),
          NbSurface(
            tone: NbTone.system,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BACKUP', style: t.text.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  'A complete copy of this canteen — members, balances, '
                  'history, settings and accounts. Use it to move to a new '
                  'phone, or to recover from one that is lost.',
                  style: t.text.body,
                ),
                const SizedBox(height: NbSpace.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _protect,
                  onChanged: _busy ? null : (v) => setState(() => _protect = v),
                  title: Text('Protect with a password', style: t.text.body),
                  subtitle: Text(
                    _protect
                        ? 'Nobody can open the file without it — including you, '
                            'so write it down.'
                        : 'The file will hold member names and account details '
                            'in the clear.',
                    style: t.text.body.copyWith(color: t.color.inkMuted),
                  ),
                ),
                if (_protect) ...[
                  const SizedBox(height: NbSpace.sm),
                  NbTextField(
                      label: 'Backup password', controller: _passphrase),
                ],
                const SizedBox(height: NbSpace.md),
                NbButton(
                  label: 'Export backup',
                  icon: Icons.save_alt,
                  busy: _busy,
                  onPressed: _busy ? null : _exportBackup,
                ),
                const SizedBox(height: NbSpace.lg),
                Text('RESTORE', style: t.text.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  'Replaces everything on this device with the contents of a '
                  'backup file. The current data is kept beside it as a copy.',
                  style: t.text.body,
                ),
                const SizedBox(height: NbSpace.md),
                NbButton.secondary(
                  label: 'Restore from a backup',
                  icon: Icons.restore,
                  busy: _busy,
                  onPressed: _busy ? null : _restore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }
}

/// Typed confirmation before a restore, showing what the file actually holds.
class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({required this.manifest});

  final BackupManifest manifest;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = widget.manifest;
    final armed = _confirm.text.trim().toUpperCase() == 'REPLACE' &&
        (!m.encrypted || _passphrase.text.isNotEmpty);

    return AlertDialog(
      title: Text('Replace everything?', style: t.text.heading),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This backup was made on '
              '${DateFormat('d MMM y, HH:mm').format(m.createdAt.toLocal())} '
              'by Tiffin ${m.appVersion}, and holds ${m.totalRows} rows '
              '(${m.rowCounts['members'] ?? 0} members).',
              style: t.text.body,
            ),
            const SizedBox(height: NbSpace.sm),
            Text(
              'Everything currently on this device will be replaced. A copy of '
              'the current data is kept next to it.',
              style: t.text.body.copyWith(color: t.color.reject),
            ),
            if (m.encrypted) ...[
              const SizedBox(height: NbSpace.md),
              NbTextField(
                label: 'Backup password',
                controller: _passphrase,
                obscure: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: NbSpace.md),
            NbTextField(
              label: 'Type REPLACE to confirm',
              controller: _confirm,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        NbButton(
          label: 'Restore',
          background: t.color.reject,
          onPressed:
              armed ? () => Navigator.pop(context, _passphrase.text) : null,
        ),
      ],
    );
  }
}
