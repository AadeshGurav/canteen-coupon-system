import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Labelled text field on the neobrutalism input theme. Postel's Law
/// (CLAUDE.md §11.2): forgiving input — trims on its own, accepts what the
/// caller's [keyboardType]/[formatters] allow.
class NbTextField extends StatelessWidget {
  const NbTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.formatters,
    this.onChanged,
    this.errorText,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: NbSpace.xs),
          child: Text(label.toUpperCase(), style: t.text.label),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          inputFormatters: formatters,
          onChanged: onChanged,
          autofocus: autofocus,
          style: t.text.body,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

class NbNumberField extends StatelessWidget {
  const NbNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return NbTextField(
      label: label,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: false),
      formatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (v) => onChanged?.call(int.tryParse(v) ?? 0),
    );
  }
}
