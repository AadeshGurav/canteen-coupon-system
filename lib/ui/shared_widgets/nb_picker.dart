import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'frosted_panel.dart';
import 'nb_text_field.dart';

/// A tappable field that opens a searchable list — the "combo box" pattern for
/// lists too long to scroll blind (the IANA timezone list is ~600 entries).
///
/// A plain [DropdownButton] builds every entry up front and offers no way to
/// find one; this builds rows lazily and filters as you type.
class NbPickerField extends StatelessWidget {
  const NbPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.emptyHint = 'Not set',
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return NbSurfaceField(
      label: label,
      onTap: () async {
        final picked = await showNbSearchPicker(
          context: context,
          title: label,
          options: options,
          selected: value,
        );
        if (picked != null) onSelected(picked);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : emptyHint,
              style: t.text.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.search, size: 20, color: t.color.ink),
        ],
      ),
    );
  }
}

/// The bordered, labelled shell shared by [NbPickerField] and any other
/// tap-to-edit control, so it lines up with [NbTextField] on the same form.
class NbSurfaceField extends StatelessWidget {
  const NbSurfaceField({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.text.label),
        const SizedBox(height: NbSpace.xs),
        InkWell(
          onTap: onTap,
          child: Container(
            // Matches NbTextField's contentPadding so labels align on a form.
            padding: const EdgeInsets.symmetric(
                horizontal: NbSpace.md, vertical: NbSpace.md),
            constraints: const BoxConstraints(minHeight: 48), // §11.6.5
            decoration: BoxDecoration(
              color: t.color.surface,
              border: Border.all(color: t.color.ink, width: t.shape.borderBase),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Modal search-and-pick over [options]. A bottom sheet rather than a centred
/// dialog so it lands in the thumb zone and leaves room for the keyboard
/// (CLAUDE.md §11.6.6). Returns null if dismissed.
Future<String?> showNbSearchPicker({
  required BuildContext context,
  required String title,
  required List<String> options,
  String? selected,
}) {
  final t = context.tokens;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: sheetBackground(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: t.shape.radius.topLeft),
      side: BorderSide(color: t.color.border, width: t.shape.borderBold),
    ),
    builder: (_) => FrostedPanel(
      child: _SearchPickerSheet(
          title: title, options: options, selected: selected),
    ),
  );
}

class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String? selected;

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final _query = TextEditingController();
  late List<String> _matches = widget.options;

  @override
  void initState() {
    super.initState();
    _query.addListener(_filter);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Matches on any word boundary, so "kolkata" and "asia/kol" both find
  /// `Asia/Kolkata` — people rarely remember which half of a zone name it is.
  void _filter() {
    final q = _query.text.trim().toLowerCase().replaceAll(' ', '_');
    setState(() {
      _matches = q.isEmpty
          ? widget.options
          : [
              for (final o in widget.options)
                if (o.toLowerCase().contains(q)) o
            ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Leave room for the keyboard: the sheet shrinks instead of hiding the list.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NbSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.title, style: t.text.heading)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: NbSpace.sm),
                NbTextField(
                  label: 'Search',
                  controller: _query,
                  autofocus: true,
                ),
                const SizedBox(height: NbSpace.sm),
                if (_matches.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text('Nothing matches "${_query.text}".',
                          style: t.text.body),
                    ),
                  )
                else
                  Expanded(
                    // Lazy: only the visible rows are built, so a 600-entry
                    // list scrolls smoothly on a mid-range phone.
                    child: ListView.builder(
                      itemCount: _matches.length,
                      itemExtent: 48, // §11.6.5 minimum touch target
                      itemBuilder: (_, i) {
                        final option = _matches[i];
                        final isSelected = option == widget.selected;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          title: Text(option, style: t.text.body),
                          trailing: isSelected
                              ? Icon(Icons.check, color: t.color.accent)
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
