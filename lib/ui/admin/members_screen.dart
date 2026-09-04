import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/member.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';
import '../shared_widgets/motion.dart';

final _membersProvider = FutureProvider.autoDispose<List<Member>>((ref) async {
  return ref.watch(backendProvider).listMembers();
});

/// Member CRUD (PRD §6.1). Restrained intensity — this is a data surface.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final members = ref.watch(_membersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: t.color.accent,
        foregroundColor: t.color.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () => _openForm(context, ref, null),
      ),
      body: AsyncView<List<Member>>(
        value: members,
        onRetry: () => ref.invalidate(_membersProvider),
        loadingLabel: 'Loading members…',
        empty: NbEmpty(
          icon: Icons.people_outline,
          title: 'No members yet',
          quips: EmptyQuips.members,
          actionLabel: 'Add the first member',
          onAction: () => _openForm(context, ref, null),
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(NbSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: NbSpace.sm),
          itemBuilder: (_, i) => _MemberTile(
            member: list[i],
            onChanged: () => ref.invalidate(_membersProvider),
          ),
        ),
      ),
    );
  }

  static Future<void> _openForm(
      BuildContext context, WidgetRef ref, Member? existing) async {
    final saved = await Navigator.of(context).push<bool>(
      tiffinRoute<bool>(context, () => _MemberForm(existing: existing)),
    );
    if (saved ?? false) ref.invalidate(_membersProvider);
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.onChanged});

  final Member member;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final b = member.balances;
    return NbSurface(
      onTap: () => MembersScreen._openForm(context, ref, member),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(member.name, style: t.text.heading),
              ),
              if (!member.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: NbSpace.sm, vertical: 2),
                  color: t.color.surfaceMuted,
                  child: Text('INACTIVE', style: t.text.label),
                ),
            ],
          ),
          Text(
            member.type == 'student'
                ? 'Student · ${member.className ?? '—'} · roll ${member.rollNumber ?? '—'}'
                : 'Staff · ${member.staffId ?? '—'}',
            style: t.text.label,
          ),
          const SizedBox(height: NbSpace.sm),
          Text(
              'Lunch ${b.lunch}   Breakfast ${b.breakfast}   Brunch ${b.brunch}',
              style: t.text.body),
          const SizedBox(height: NbSpace.sm),
          Wrap(
            spacing: NbSpace.sm,
            children: [
              NbButton.secondary(
                label: 'Credit',
                onPressed: () => _credit(context, ref),
              ),
              NbButton.secondary(
                label: 'QR',
                onPressed: () => _showQr(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _credit(BuildContext context, WidgetRef ref) async {
    final t = context.tokens;
    final lunch = TextEditingController(text: '0');
    final breakfast = TextEditingController(text: '0');
    final brunch = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Credit ${member.name}', style: t.text.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NbNumberField(label: 'Lunch units', controller: lunch),
            const SizedBox(height: NbSpace.sm),
            NbNumberField(label: 'Breakfast units', controller: breakfast),
            const SizedBox(height: NbSpace.sm),
            NbNumberField(label: 'Brunch units', controller: brunch),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          NbButton(
            label: 'Add units',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(backendProvider).creditMember(
            member.id,
            UnitCounts(
              lunch: int.tryParse(lunch.text) ?? 0,
              breakfast: int.tryParse(breakfast.text) ?? 0,
              brunch: int.tryParse(brunch.text) ?? 0,
            ),
          ),
      successMessage: 'Units added.',
    );
    onChanged();
  }

  Future<void> _showQr(BuildContext context, WidgetRef ref) async {
    final t = context.tokens;
    Uint8List? png;
    try {
      png = Uint8List.fromList(
          await ref.read(backendProvider).memberQrPng(member.id));
    } catch (e) {
      if (context.mounted) showNbSnack(context, '$e', ok: false);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(member.name, style: t.text.heading),
        content: Image.memory(png!, width: 260, height: 260),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm({this.existing});
  final Member? existing;

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  late String _type = widget.existing?.type ?? 'student';
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _className =
      TextEditingController(text: widget.existing?.className ?? '');
  late final _rollNumber =
      TextEditingController(text: widget.existing?.rollNumber ?? '');
  late final _staffId =
      TextEditingController(text: widget.existing?.staffId ?? '');
  late final _grace = TextEditingController(
      text: widget.existing?.graceAllowanceOverride?.toString() ?? '');
  late String _status = widget.existing?.status ?? 'active';
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      final backend = ref.read(backendProvider);
      if (_isEdit) {
        await backend.updateMember(
          widget.existing!.id,
          MemberPatch(
            name: _name.text.trim(),
            className: _type == 'student' ? _className.text.trim() : null,
            rollNumber: _type == 'student' ? _rollNumber.text.trim() : null,
            staffId: _type == 'staff' ? _staffId.text.trim() : null,
            status: _status,
            graceAllowanceOverride:
                _grace.text.isEmpty ? null : int.parse(_grace.text),
          ),
        );
      } else {
        await backend.createMember(MemberDraft(
          type: _type,
          name: _name.text.trim(),
          className: _type == 'student' ? _className.text.trim() : null,
          rollNumber: _type == 'student' ? _rollNumber.text.trim() : null,
          staffId: _type == 'staff' ? _staffId.text.trim() : null,
          graceAllowanceOverride:
              _grace.text.isEmpty ? null : int.parse(_grace.text),
        ));
      }
    }, successMessage: _isEdit ? 'Member updated.' : 'Member created.');
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await runGuarded(
      context,
      () => ref.read(backendProvider).deleteMember(widget.existing!.id),
      successMessage: 'Member deleted.',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit member' : 'New member')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(NbSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'student', label: Text('Student')),
                ButtonSegment(value: 'staff', label: Text('Staff')),
              ],
              selected: {_type},
              onSelectionChanged:
                  _isEdit ? null : (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: NbSpace.md),
            NbTextField(label: 'Name', controller: _name, autofocus: true),
            const SizedBox(height: NbSpace.md),
            if (_type == 'student') ...[
              NbTextField(label: 'Class', controller: _className),
              const SizedBox(height: NbSpace.md),
              NbTextField(label: 'Roll number', controller: _rollNumber),
            ] else
              NbTextField(label: 'Staff ID', controller: _staffId),
            const SizedBox(height: NbSpace.md),
            NbTextField(
              label: 'Grace override (blank = global default)',
              controller: _grace,
              keyboardType: TextInputType.number,
            ),
            if (_isEdit) ...[
              const SizedBox(height: NbSpace.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'inactive', label: Text('Inactive')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
            ],
            const SizedBox(height: NbSpace.lg),
            NbButton(
                label: 'Save', busy: _busy, onPressed: _busy ? null : _save),
            if (_isEdit) ...[
              const SizedBox(height: NbSpace.sm),
              NbButton(
                label: 'Delete',
                background: t.color.reject,
                foreground: t.color.onReject,
                onPressed: _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
