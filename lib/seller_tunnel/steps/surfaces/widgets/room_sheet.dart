import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// What the room sheet returns.
sealed class RoomSheetResult {
  const new();
}

/// The room was entered ("Ajouter" / "Enregistrer").
final class RoomSheetSaved extends RoomSheetResult {
  const new(this.room);

  final RoomInput room;
}

/// The edited room is to be removed ("Supprimer cette pièce").
final class RoomSheetDeleted extends RoomSheetResult {
  const new();
}

/// Opens the room form (not designed: a bottom sheet). Returns null when
/// dismissed.
///
/// Edits [initial] (which can then also be deleted) when given, adds a
/// room on [defaultLevel] otherwise. [otherNames] are the names of the
/// other rooms (to number the bedrooms).
Future<RoomSheetResult?> showRoomSheet(
  BuildContext context, {
  RoomInput? initial,
  RoomLevel defaultLevel = RoomLevel.groundFloor,
  List<String> otherNames = const [],
}) {
  return showModalBottomSheet<RoomSheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => RoomSheet(
      initial: initial,
      defaultLevel: defaultLevel,
      otherNames: otherNames,
    ),
  );
}

/// Content of [showRoomSheet]. Errors show once "Ajouter" / "Enregistrer"
/// was tapped with invalid fields.
class RoomSheet extends StatefulWidget {
  const new({
    this.initial,
    this.defaultLevel = RoomLevel.groundFloor,
    this.otherNames = const [],
    super.key,
  });

  final RoomInput? initial;
  final RoomLevel defaultLevel;
  final List<String> otherNames;

  /// Maximum length of a room name (`rooms.name`).
  static const nameMaxLength = 60;

  @override
  State<RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<RoomSheet> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _area = TextEditingController(
    text: widget.initial == null ? '' : RoomArea.input(widget.initial!.areaM2),
  );
  final _nameFocus = FocusNode();
  late RoomLevel? _level = widget.initial == null
      ? widget.defaultLevel
      : widget.initial!.level;
  late String? _covering = widget.initial?.floorCovering;
  late Glazing? _glazing = widget.initial?.glazing;
  late bool _isMain = widget.initial?.isMain ?? false;
  late bool _isAnnex = widget.initial?.isAnnex ?? false;
  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _areaKey = GlobalKey();
  RoomSuggestion? _suggestion;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String? get _nameError =>
      _name.text.trim().isEmpty ? context.l10n.surfacesErrorName : null;

  String? get _areaError {
    final l10n = context.l10n;
    final area = RoomArea.parse(_area.text);
    if (area == null) return l10n.surfacesErrorArea;
    if (area < RoomArea.min || area > RoomArea.max) {
      return l10n.surfacesErrorAreaRange(
        RoomArea.input(RoomArea.min),
        RoomArea.input(RoomArea.max),
      );
    }
    return null;
  }

  void _submit() {
    if (_nameError == null && _areaError == null) {
      Navigator.of(context).pop(
        RoomSheetSaved(
          RoomInput(
            name: _name.text.trim(),
            level: _level,
            areaM2: RoomArea.parse(_area.text)!,
            floorCovering: _covering,
            glazing: _glazing,
            isMain: _isMain,
            isAnnex: _isAnnex,
          ),
        ),
      );
    } else {
      final key = _nameError != null ? _nameKey : _areaKey;
      setState(() => _submitted = true);
      // After the frame, so that the error text is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: RealestyMotion.page,
            alignment: 0.1,
          );
        }
      });
    }
  }

  void _suggestionPicked(RoomSuggestion suggestion) {
    final l10n = context.l10n;
    setState(() {
      _suggestion = suggestion;
      _isMain = suggestion.isMain;
      _isAnnex = suggestion.isAnnex;
      if (suggestion == RoomSuggestion.other) {
        _name.clear();
        _nameFocus.requestFocus();
        return;
      }
      final label = suggestion.label(l10n);
      if (suggestion.isNumbered) {
        // After the highest number (a plain "Chambre" counts as 1).
        final pattern = RegExp('^${RegExp.escape(label)}(?: (\\d+))?\$');
        var highest = 0;
        for (final name in widget.otherNames) {
          final match = pattern.firstMatch(name.trim());
          if (match == null) continue;
          final number = int.parse(match.group(1) ?? '1');
          if (number > highest) highest = number;
        }
        _name.text = '$label ${highest + 1}';
      } else {
        _name.text = label;
      }
    });
  }

  /// Refreshes the errors while typing, once they are shown.
  void _changed(String _) {
    if (_submitted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final isEdit = widget.initial != null;
    final covering = FloorCovering.parse(_covering);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          0,
          RealestySpacing.gutter,
          RealestySpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Semantics(
              header: true,
              child: Text(
                isEdit
                    ? l10n.surfacesSheetEditTitle
                    : l10n.surfacesSheetAddTitle,
                style: RealestyTextStyles.title2.copyWith(color: c.encre),
              ),
            ),
            Wrap(
              spacing: RealestySpacing.xs,
              children: [
                for (final suggestion in RoomSuggestion.values)
                  RealestyChoiceChip(
                    label: suggestion.label(l10n),
                    selected: _suggestion == suggestion,
                    onSelected: (_) => _suggestionPicked(suggestion),
                  ),
              ],
            ),
            RealestyTextField(
              key: _nameKey,
              label: l10n.surfacesNameLabel,
              hint: l10n.surfacesNameHint,
              controller: _name,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(RoomSheet.nameMaxLength),
              ],
              onChanged: _changed,
              errorText: _submitted ? _nameError : null,
            ),
            // An annex is never a main room: each box clears the other.
            RealestyCheckbox(
              value: _isMain,
              label: l10n.surfacesMainRoomLabel,
              onChanged: (value) => setState(() {
                _isMain = value;
                if (value) _isAnnex = false;
              }),
            ),
            RealestyCheckbox(
              value: _isAnnex,
              label: l10n.surfacesAnnexLabel,
              onChanged: (value) => setState(() {
                _isAnnex = value;
                if (value) _isMain = false;
              }),
            ),
            RealestyTextField(
              key: _areaKey,
              label: l10n.surfacesAreaLabel,
              controller: _area,
              suffixText: 'm²',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              inputFormatters: [_areaFormatter],
              onChanged: _changed,
              onSubmitted: (_) => _submit(),
              errorText: _submitted ? _areaError : null,
            ),
            RealestySelect<RoomLevel>(
              label: l10n.surfacesLevelLabel,
              value: _level,
              hint: l10n.surfacesNotSpecified,
              options: [
                for (final level in RoomLevel.values)
                  RealestySelectOption(value: level, label: level.label(l10n)),
              ],
              onChanged: (level) => setState(() => _level = level),
            ),
            RealestySelect<String?>(
              label: l10n.surfacesCoveringLabel,
              value: _covering,
              options: [
                RealestySelectOption(
                  value: null,
                  label: l10n.surfacesNotSpecified,
                ),
                // A covering that is not in the list (e.g. scanned) is kept.
                if (_covering != null && covering == null)
                  RealestySelectOption(value: _covering, label: _covering!),
                for (final option in FloorCovering.values)
                  RealestySelectOption(
                    value: option.value,
                    label: option.label(l10n),
                  ),
              ],
              onChanged: (value) => setState(() => _covering = value),
            ),
            RealestySelect<Glazing?>(
              label: l10n.surfacesGlazingLabel,
              value: _glazing,
              options: [
                RealestySelectOption(
                  value: null,
                  label: l10n.surfacesNotSpecified,
                ),
                for (final glazing in Glazing.values)
                  RealestySelectOption(
                    value: glazing,
                    label: glazing.label(l10n),
                  ),
              ],
              onChanged: (value) => setState(() => _glazing = value),
            ),
            const SizedBox(height: RealestySpacing.xxs),
            RealestyButton(
              label: isEdit ? l10n.surfacesSheetSave : l10n.surfacesSheetAdd,
              onPressed: _submit,
            ),
            if (isEdit)
              RealestyButton(
                label: l10n.surfacesSheetDelete,
                variant: RealestyButtonVariant.text,
                height: RealestySpacing.minTouchTarget,
                onPressed: () =>
                    Navigator.of(context).pop(const RoomSheetDeleted()),
              ),
          ],
        ),
      ),
    );
  }

  /// Up to 3 digits, then a comma (or dot) and up to 2 decimals.
  static final _areaFormatter = TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        RegExp(r'^\d{0,3}([.,]\d{0,2})?$').hasMatch(newValue.text)
        ? newValue
        : oldValue,
  );
}
