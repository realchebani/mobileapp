import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/valuation_form/cubit/valuation_form_cubit.dart';
import 'package:realesty_backoffice/valuation_form/view/certified_view.dart';
import 'package:realesty_backoffice/valuation_form/view/form_sections.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// The « Avis de valeur » tab: the form, or the certified valuation and its
/// PDF.
class ValuationFormPage extends StatelessWidget {
  const new({required this.dossier, this.autosaveDelay, super.key});

  final Dossier dossier;

  /// Tests shorten it.
  final Duration? autosaveDelay;

  @override
  Widget build(BuildContext context) {
    if (dossier.status == DossierStatus.certified) {
      return CertifiedView(dossier: dossier);
    }
    return BlocProvider(
      create: (context) => ValuationFormCubit(
        repository: context.read(),
        propertyId: dossier.id,
        draft: dossier.draft,
        autosaveDelay: autosaveDelay ?? const Duration(seconds: 5),
      ),
      child: ValuationFormView(dossier: dossier),
    );
  }
}

class ValuationFormView extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ValuationFormCubit>().state;
    final me = context.select<SessionCubit, StaffMe?>((s) => s.state.me);
    final partner = me?.role == StaffRole.partnerExpert;
    final enabled =
        (me?.can(BackOfficeCapability.editDraft) ?? false) &&
        !(partner && state.isSubmitted) &&
        state.saveStatus != SaveStatus.conflict;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ActionBar(dossier: dossier, partner: partner),
        const SizedBox(height: RealestySpacing.md),
        if (state.saveStatus == SaveStatus.conflict) ...[
          InlineBanner(
            message: state.conflictBy == null
                ? l10n.formConflictAnonymous
                : l10n.formConflict(state.conflictBy!),
          ),
          const SizedBox(height: RealestySpacing.xs),
          RealestyButton(
            label: l10n.formReload,
            expand: false,
            variant: RealestyButtonVariant.secondary,
            onPressed: () => runGuarded(context, () async {
              final dossierCubit = context.read<DossierCubit>();
              final form = context.read<ValuationFormCubit>();
              await dossierCubit.load();
              form.reset(dossierCubit.state.dossier?.draft);
            }),
          ),
          const SizedBox(height: RealestySpacing.md),
        ],
        if (state.isSubmitted) ...[
          InlineBanner(
            variant: InlineBannerVariant.info,
            message: partner
                ? l10n.formSubmittedSelf
                : l10n.formSubmitted(state.submittedByName ?? ''),
          ),
          const SizedBox(height: RealestySpacing.md),
        ] else if (state.approvalNote != null) ...[
          InlineBanner(message: l10n.formReturned(state.approvalNote!)),
          const SizedBox(height: RealestySpacing.md),
        ],
        Text(l10n.formIntro, style: RealestyTextStyles.bodySmall),
        const SizedBox(height: RealestySpacing.md),
        FormSections(dossier: dossier, enabled: enabled),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const new({required this.dossier, required this.partner});

  final Dossier dossier;
  final bool partner;

  Future<void> _certify(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ValuationFormCubit>();
    final p = cubit.state.payload;
    if (cubit.state.errors.isNotEmpty) {
      cubit.revealErrors();
      showRealestySnackBar(context, l10n.formFixErrors, isError: true);
      return;
    }
    final me = context.read<SessionCubit>().state.me;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.formCertifyTitle),
        content: SizedBox(
          width: 480,
          child: Text(
            l10n.formCertifyBody(
              euros(p['value_eur'] as int),
              euros(p['low_eur'] as int),
              euros(p['high_eur'] as int),
              cubit.state.submittedByName ?? me?.displayName ?? '',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.formCertify),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final dossierCubit = context.read<DossierCubit>();
    final done = await runGuarded(
      context,
      cubit.certify,
      success: l10n.formCertifyDone,
    );
    if (done && context.mounted) await runGuarded(context, dossierCubit.load);
  }

  Future<void> _return(BuildContext context) async {
    final l10n = context.l10n;
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const ReturnDialog(),
    );
    if (note == null || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<ValuationFormCubit>().returnDraft(note),
      success: l10n.formReturnDone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<ValuationFormCubit>().state;
    final cubit = context.read<ValuationFormCubit>();
    final canCertify = context.select<SessionCubit, bool>(
      (s) => s.state.me?.can(BackOfficeCapability.certify) ?? false,
    );
    final errors = state.errors.length;
    final status = switch (state.saveStatus) {
      SaveStatus.saved when state.version == 0 => l10n.formNotSaved,
      SaveStatus.saved => l10n.formSaved(state.version),
      SaveStatus.dirty => l10n.formDirty,
      SaveStatus.saving => l10n.formSaving,
      SaveStatus.failure || SaveStatus.conflict => l10n.formSaveFailed,
    };
    final busy = state.action != FormAction.none;
    return BoCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: RealestyTextStyles.label),
                Text(
                  l10n.formErrors(errors),
                  style: RealestyTextStyles.bodySmall.copyWith(
                    color: errors == 0 ? c.vertTexte : c.erreur,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed:
                state.saveStatus == SaveStatus.dirty ||
                    state.saveStatus == SaveStatus.failure
                ? () => runGuarded(context, cubit.save)
                : null,
            child: Text(l10n.formSaveNow),
          ),
          const SizedBox(width: RealestySpacing.sm),
          if (canCertify && state.isSubmitted) ...[
            RealestyButton(
              label: l10n.formReturn,
              expand: false,
              variant: RealestyButtonVariant.secondary,
              isLoading: state.action == FormAction.returning,
              onPressed: busy ? null : () => _return(context),
            ),
            const SizedBox(width: RealestySpacing.sm),
          ],
          if (canCertify)
            RealestyButton(
              label: l10n.formCertify,
              expand: false,
              isLoading: state.action == FormAction.certifying,
              onPressed: busy ? null : () => _certify(context),
            )
          else if (partner && !state.isSubmitted)
            RealestyButton(
              label: l10n.formSubmit,
              expand: false,
              isLoading: state.action == FormAction.submitting,
              onPressed: busy
                  ? null
                  : () {
                      if (errors > 0) {
                        cubit.revealErrors();
                        showRealestySnackBar(
                          context,
                          l10n.formFixErrors,
                          isError: true,
                        );
                        return;
                      }
                      unawaited(
                        runGuarded(
                          context,
                          cubit.submitForApproval,
                          success: l10n.formSubmitDone,
                        ),
                      );
                    },
            ),
        ],
      ),
    );
  }
}

/// Asks the comment for the author of a draft sent back.
class ReturnDialog extends StatefulWidget {
  const new({super.key});

  @override
  State<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<ReturnDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.formReturnTitle),
      content: SizedBox(
        width: 480,
        child: RealestyTextField(
          label: l10n.formReturnNote,
          controller: _note,
          maxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_note.text.trim().isEmpty ? null : _note.text.trim()),
          child: Text(l10n.formReturn),
        ),
      ],
    );
  }
}
