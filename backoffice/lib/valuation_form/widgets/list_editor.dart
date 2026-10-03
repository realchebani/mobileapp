import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/valuation_form/widgets/error_text.dart';
import 'package:realesty_backoffice/valuation_form/widgets/form_input.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// A column of a [ListEditor].
class ListColumn {
  const new(
    this.key,
    this.label, {
    this.kind = InputKind.text,
    this.flex = 2,
    this.isBool = false,
    this.choices,
  });

  final String key;
  final String label;
  final InputKind kind;
  final int flex;

  /// A check box instead of a text field.
  final bool isBool;

  /// A drop-down (value → label) instead of a text field.
  final Map<String, String>? choices;
}

/// Edits a list of the draft (`method_steps`, `comparables`…): add,
/// remove, move up; each cell shows its validation error.
class ListEditor extends StatefulWidget {
  const new({
    required this.listKey,
    required this.title,
    required this.columns,
    required this.items,
    required this.errors,
    required this.onChanged,
    this.newItem = const {},
    this.enabled = true,
    this.action,
    super.key,
  });

  final String listKey;
  final String title;
  final List<ListColumn> columns;
  final List<JsonMap> items;
  final List<ValidationError> errors;

  /// The new list; null when it becomes empty.
  final ValueChanged<List<JsonMap>?> onChanged;
  final JsonMap newItem;
  final bool enabled;

  /// A button next to the title (pre-fill, import).
  final Widget? action;

  @override
  State<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<ListEditor> {
  var _next = 0;
  late List<int> _ids = [for (final _ in widget.items) _next++];

  @override
  void didUpdateWidget(ListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ids.length != widget.items.length) {
      _ids = [for (final _ in widget.items) _next++];
    }
  }

  void _emit(List<JsonMap> items) =>
      widget.onChanged(items.isEmpty ? null : items);

  void _set(int index, String key, Object? value) {
    final items = [...widget.items];
    final item = {...items[index]};
    if (value == null) {
      item.remove(key);
    } else {
      item[key] = value;
    }
    items[index] = item;
    _emit(items);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final listError = errorAt(l10n, widget.errors, widget.listKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: RealestyTextStyles.label),
            ),
            ?widget.action,
          ],
        ),
        if (listError != null)
          Text(listError, style: TextStyle(color: c.erreur)),
        for (var i = 0; i < widget.items.length; i++)
          Padding(
            key: ValueKey('${widget.listKey}-${_ids[i]}'),
            padding: const EdgeInsets.only(top: RealestySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in widget.columns) ...[
                  Expanded(flex: column.flex, child: _cell(context, i, column)),
                  const SizedBox(width: RealestySpacing.xs),
                ],
                IconButton(
                  tooltip: l10n.formMoveUp,
                  onPressed: !widget.enabled || i == 0
                      ? null
                      : () {
                          final items = [...widget.items];
                          final item = items.removeAt(i);
                          items.insert(i - 1, item);
                          setState(() {
                            final id = _ids.removeAt(i);
                            _ids.insert(i - 1, id);
                          });
                          _emit(items);
                        },
                  icon: const RealestyIcon(
                    RealestyIcons.chevronDown,
                    size: 16,
                  ).rotated,
                ),
                IconButton(
                  tooltip: l10n.formRemoveRow,
                  onPressed: !widget.enabled
                      ? null
                      : () {
                          setState(() => _ids.removeAt(i));
                          _emit([...widget.items]..removeAt(i));
                        },
                  icon: const RealestyIcon(RealestyIcons.trash, size: 16),
                ),
              ],
            ),
          ),
        const SizedBox(height: RealestySpacing.xs),
        TextButton.icon(
          onPressed: !widget.enabled
              ? null
              : () {
                  setState(() => _ids.add(_next++));
                  _emit([
                    ...widget.items,
                    {...widget.newItem},
                  ]);
                },
          icon: const RealestyIcon(RealestyIcons.plus, size: 16),
          label: Text(l10n.formAddRow),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, int index, ListColumn column) {
    final l10n = context.l10n;
    final value = widget.items[index][column.key];
    final error = errorAt(
      l10n,
      widget.errors,
      '${widget.listKey}[$index].${column.key}',
    );
    if (column.isBool) {
      return Row(
        children: [
          Checkbox(
            value: value == true,
            semanticLabel: column.label,
            onChanged: widget.enabled
                ? (checked) => _set(index, column.key, checked ?? false)
                : null,
          ),
          Flexible(
            child: Text(column.label, style: RealestyTextStyles.bodySmall),
          ),
        ],
      );
    }
    if (column.choices case final Map<String, String> choices) {
      return DropdownButtonFormField<String>(
        initialValue: choices.containsKey(value) ? value as String : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: column.label, errorText: error),
        items: [
          for (final MapEntry(key: code, value: label) in choices.entries)
            DropdownMenuItem(value: code, child: Text(label)),
        ],
        onChanged: widget.enabled
            ? (code) => _set(index, column.key, code)
            : null,
      );
    }
    return FormInput(
      label: column.label,
      value: value,
      kind: column.kind,
      error: error,
      enabled: widget.enabled,
      onChanged: (v) => _set(index, column.key, v),
    );
  }
}

extension on Widget {
  Widget get rotated => RotatedBox(quarterTurns: 2, child: this);
}
