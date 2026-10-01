import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// What the item sheet returns.
sealed class LifestyleItemSheetResult {
  const new();
}

/// The label was entered ("Ajouter" / "Enregistrer"), trimmed.
final class LifestyleItemSaved extends LifestyleItemSheetResult {
  const new(this.label);

  final String label;
}

/// The edited item is to be removed ("Supprimer").
final class LifestyleItemDeleted extends LifestyleItemSheetResult {
  const new();
}

/// Opens the asset / watch point form (not designed: a bottom sheet with
/// one text field). Edits [initial] (which can then also be deleted) when
/// given, adds an item of [kind] otherwise. Returns null when dismissed.
Future<LifestyleItemSheetResult?> showLifestyleItemSheet(
  BuildContext context, {
  required LifestyleItemKind kind,
  String? initial,
}) {
  return showModalBottomSheet<LifestyleItemSheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => LifestyleItemSheet(kind: kind, initial: initial),
  );
}

/// Content of [showLifestyleItemSheet]. The error shows once "Ajouter" /
/// "Enregistrer" was tapped with fewer than 3 characters.
class LifestyleItemSheet extends StatefulWidget {
  const new({required this.kind, this.initial, super.key});

  final LifestyleItemKind kind;
  final String? initial;

  @override
  State<LifestyleItemSheet> createState() => _LifestyleItemSheetState();
}

class _LifestyleItemSheetState extends State<LifestyleItemSheet> {
  late final _label = TextEditingController(text: widget.initial);
  bool _submitted = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _isValid => isValidLifestyleLabel(_label.text);

  void _submit() {
    if (_isValid) {
      Navigator.of(context).pop(LifestyleItemSaved(_label.text.trim()));
    } else {
      setState(() => _submitted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.initial != null;
    final isAsset = widget.kind == LifestyleItemKind.asset;
    final title = switch ((isAsset, isEdit)) {
      (true, false) => l10n.lifestyleAddAsset,
      (true, true) => l10n.lifestyleEditAssetTitle,
      (false, false) => l10n.lifestyleAddWatchPointTitle,
      (false, true) => l10n.lifestyleEditWatchPointTitle,
    };
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
                title,
                style: RealestyTextStyles.title2.copyWith(
                  color: context.realestyColors.encre,
                ),
              ),
            ),
            RealestyTextField(
              label: isAsset
                  ? l10n.lifestyleAssetLabel
                  : l10n.lifestyleWatchPointLabel,
              hint: isAsset
                  ? l10n.lifestyleAssetHint
                  : l10n.lifestyleWatchPointHint,
              controller: _label,
              autofocus: true,
              maxLines: 3,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
                const CharLengthFormatter(lifestyleItemMaxLength),
              ],
              onChanged: (_) {
                if (_submitted) setState(() {});
              },
              onSubmitted: (_) => _submit(),
              errorText: _submitted && !_isValid
                  ? l10n.lifestyleItemTooShort(lifestyleItemMinLength)
                  : null,
            ),
            const SizedBox(height: RealestySpacing.xxs),
            RealestyButton(
              label: isEdit ? l10n.lifestyleSheetSave : l10n.lifestyleSheetAdd,
              onPressed: _submit,
            ),
            if (isEdit)
              RealestyButton(
                label: l10n.lifestyleSheetDelete,
                variant: RealestyButtonVariant.text,
                height: RealestySpacing.minTouchTarget,
                onPressed: () =>
                    Navigator.of(context).pop(const LifestyleItemDeleted()),
              ),
          ],
        ),
      ),
    );
  }
}
