import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// What a [FormInput] holds.
enum InputKind { text, integer, number }

/// Parses the text of a [FormInput]: blank → null; a number that does not
/// parse stays as text so the validator reports it.
Object? parseInput(InputKind kind, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  switch (kind) {
    case InputKind.text:
      return text;
    case InputKind.integer:
      final digits = trimmed.replaceAll(RegExp(r'[\s  ]'), '');
      return int.tryParse(digits) ?? trimmed;
    case InputKind.number:
      final value = double.tryParse(
        trimmed.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'),
      );
      if (value == null) return trimmed;
      return value == value.truncateToDouble() ? value.toInt() : value;
  }
}

String formatInput(Object? value) => switch (value) {
  null => '',
  final double d => '$d'.replaceAll('.', ','),
  _ => '$value',
};

/// A form field bound to a JSON value of the draft.
class FormInput extends StatefulWidget {
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    this.kind = InputKind.text,
    this.error,
    this.maxLines = 1,
    this.enabled = true,
    super.key,
  });

  final String label;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final InputKind kind;
  final String? error;
  final int maxLines;
  final bool enabled;

  @override
  State<FormInput> createState() => _FormInputState();
}

class _FormInputState extends State<FormInput> {
  late final _controller = TextEditingController(
    text: formatInput(widget.value),
  );

  @override
  void didUpdateWidget(FormInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A value set from outside (reset, pre-fill): show it.
    if (parseInput(widget.kind, _controller.text) != widget.value) {
      _controller.text = formatInput(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RealestyTextField(
      label: widget.label,
      controller: _controller,
      errorText: widget.error,
      maxLines: widget.maxLines,
      enabled: widget.enabled,
      keyboardType: widget.kind == InputKind.text
          ? (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text)
          : const TextInputType.numberWithOptions(signed: true, decimal: true),
      onChanged: (text) => widget.onChanged(parseInput(widget.kind, text)),
    );
  }
}
