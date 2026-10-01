import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/owner_field_error_text.dart';
import 'package:mobileapp/ui/ui.dart';

/// What the co-owner sheet returns.
sealed class CoOwnerSheetResult {
  const new();
}

/// The co-owner was entered ("Ajouter" / "Enregistrer").
final class CoOwnerSaved extends CoOwnerSheetResult {
  const new(this.coOwner);

  final OwnerDraft coOwner;
}

/// The edited co-owner is to be removed ("Supprimer ce co-propriétaire").
final class CoOwnerDeleted extends CoOwnerSheetResult {
  const new();
}

/// Opens the co-owner form (not designed: a bottom sheet with the owner 1
/// fields, the e-mail being optional). Returns null when dismissed.
///
/// Edits [initial] (which can then also be deleted) when given, adds a
/// co-owner otherwise.
Future<CoOwnerSheetResult?> showCoOwnerSheet(
  BuildContext context, {
  OwnerDraft? initial,
}) {
  return showModalBottomSheet<CoOwnerSheetResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => CoOwnerSheet(initial: initial),
  );
}

/// Content of [showCoOwnerSheet]. Errors show once "Ajouter" /
/// "Enregistrer" was tapped with invalid fields.
class CoOwnerSheet extends StatefulWidget {
  const new({this.initial, super.key});

  final OwnerDraft? initial;

  @override
  State<CoOwnerSheet> createState() => _CoOwnerSheetState();
}

class _CoOwnerSheetState extends State<CoOwnerSheet> {
  late final _firstName = TextEditingController(
    text: widget.initial?.firstName,
  );
  late final _lastName = TextEditingController(text: widget.initial?.lastName);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _email = TextEditingController(text: widget.initial?.email);
  bool _submitted = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  OwnerDraft get _draft => OwnerDraft(
    firstName: _firstName.text,
    lastName: _lastName.text,
    phone: _phone.text,
    email: _email.text,
  );

  void _submit() {
    final draft = _draft;
    if (draft.isValid(emailRequired: false)) {
      Navigator.of(context).pop(CoOwnerSaved(draft));
    } else {
      setState(() => _submitted = true);
    }
  }

  /// Refreshes the errors while typing, once they are shown.
  void _changed(String _) {
    if (_submitted) setState(() {});
  }

  String? _error(OwnerFieldError? error) =>
      _submitted ? error?.message(context.l10n) : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.initial != null;
    final nameFormatters = [
      LengthLimitingTextInputFormatter(ownerNameMaxLength),
    ];
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
                isEdit ? l10n.ownersEditCoOwnerTitle : l10n.ownersAddCoOwner,
                style: RealestyTextStyles.title2.copyWith(
                  color: context.realestyColors.encre,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: RealestySpacing.sm,
              children: [
                Expanded(
                  child: RealestyTextField(
                    label: l10n.ownersFirstNameLabel,
                    controller: _firstName,
                    autofocus: !isEdit,
                    textInputAction: TextInputAction.next,
                    inputFormatters: nameFormatters,
                    onChanged: _changed,
                    errorText: _error(validateOwnerName(_firstName.text)),
                  ),
                ),
                Expanded(
                  child: RealestyTextField(
                    label: l10n.ownersLastNameLabel,
                    controller: _lastName,
                    textInputAction: TextInputAction.next,
                    inputFormatters: nameFormatters,
                    onChanged: _changed,
                    errorText: _error(validateOwnerName(_lastName.text)),
                  ),
                ),
              ],
            ),
            RealestyTextField(
              label: l10n.ownersPhoneLabel,
              hint: l10n.ownersPhoneHint,
              leadingIcon: RealestyIcons.phone,
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onChanged: _changed,
              errorText: _error(validateOwnerPhone(_phone.text)),
            ),
            RealestyTextField(
              label: l10n.ownersEmailOptionalLabel,
              hint: l10n.ownersEmailHint,
              leadingIcon: RealestyIcons.chat,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onChanged: _changed,
              onSubmitted: (_) => _submit(),
              errorText: _error(
                validateOwnerEmail(_email.text, required: false),
              ),
            ),
            const SizedBox(height: RealestySpacing.xxs),
            RealestyButton(
              label: isEdit ? l10n.ownersSheetSave : l10n.ownersSheetAdd,
              onPressed: _submit,
            ),
            if (isEdit)
              RealestyButton(
                label: l10n.ownersSheetDelete,
                variant: RealestyButtonVariant.text,
                height: RealestySpacing.minTouchTarget,
                onPressed: () =>
                    Navigator.of(context).pop(const CoOwnerDeleted()),
              ),
          ],
        ),
      ),
    );
  }
}
