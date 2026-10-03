import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Opens the PDF of the mandate (rendered first when needed).
typedef UrlOpener = Future<bool> Function(Uri url);

/// The test signature of the mandate (V11 / V11b sheet, V11c inline): test
/// notice, signer and co-owners, the terms checkbox, the signature pad and
/// "Signer". "Signer" is always enabled: a missing checkbox or signature
/// shows its error. [onSigned] runs once the mandate is signed.
class MandateSignatureForm extends StatefulWidget {
  const new({
    required this.buttonLabel,
    this.onSigned,
    this.enabled = true,
    super.key,
  });

  final String buttonLabel;
  final VoidCallback? onSigned;

  /// False while the signature is not possible yet (identity).
  final bool enabled;

  @override
  State<MandateSignatureForm> createState() => _MandateSignatureFormState();
}

class _MandateSignatureFormState extends State<MandateSignatureForm> {
  final _pad = SignaturePadController();
  bool _accepted = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    final l10n = context.l10n;
    final cubit = context.read<SaleCubit>();
    if (!_accepted || _pad.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final png = await _pad.toPng();
    if (!mounted || png == null) return;
    await cubit.signMandate(signaturePng: png, accepted: _accepted);
    final failure = cubit.state.failure;
    if (!mounted) return;
    if (failure != null) {
      showRealestySnackBar(
        context,
        saleFailureMessage(l10n, failure),
        isError: true,
      );
      return;
    }
    showRealestySnackBar(context, l10n.mandateSigned);
    widget.onSigned?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final userId = context.select<ProfileCubit, String?>(
      (cubit) => cubit.state.profile?.id,
    );
    final signer = state.signerFor(userId ?? '');
    final others = [
      for (final owner in state.owners)
        if (owner != signer) '${owner.firstName} ${owner.lastName}',
    ];
    final busy = state.busy == SaleAction.sign;
    final enabled = widget.enabled && !busy;
    final padError = _showErrors && _pad.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.sm,
      children: [
        InlineBanner(message: l10n.mandateTestNotice),
        if (signer != null)
          Text(
            l10n.mandateSigner('${signer.firstName} ${signer.lastName}'),
            style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
          ),
        if (others.isNotEmpty)
          Text(
            l10n.mandateOthersOffline(others.join(', ')),
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
        SignaturePad(
          controller: _pad,
          hint: l10n.mandateSignatureHint,
          clearLabel: l10n.mandateSignatureClear,
          semanticLabel: l10n.mandateSignatureArea,
          enabled: enabled,
          hasError: padError,
        ),
        if (padError)
          Text(
            l10n.saleErrorSignature,
            style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
          ),
        RealestyCheckbox(
          value: _accepted,
          label: l10n.mandateAccept(formulaName(l10n, sale.formula)),
          onChanged: enabled
              ? (value) => setState(() => _accepted = value)
              : null,
        ),
        if (_showErrors && !_accepted)
          Text(
            l10n.saleErrorTerms,
            style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
          ),
        RealestyButton(
          label: widget.buttonLabel,
          isLoading: busy,
          onPressed: enabled ? () => unawaited(_sign()) : null,
        ),
      ],
    );
  }
}

/// The signature of the mandate in a sheet (L’Essentiel, Le Premium).
Future<void> showMandateSignatureSheet(BuildContext context) {
  final cubit = context.read<SaleCubit>();
  final profile = context.read<ProfileCubit>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (sheetContext) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider.value(value: profile),
      ],
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.lg,
            RealestySpacing.gutter,
            RealestySpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              Text(
                sheetContext.l10n.mandateSheetTitle,
                style: RealestyTextStyles.title2.copyWith(
                  color: sheetContext.realestyColors.encre,
                ),
              ),
              MandateSignatureForm(
                buttonLabel: sheetContext.l10n.mandateSign,
                onSigned: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The terms of the mandate (V11 / V11b / V11c): type, duration,
/// termination, price, fee; then either the signature button (or the
/// identity requirement), or "Mandat signé le …" with its PDF.
class MandateCard extends StatelessWidget {
  const new({required this.openUrl, this.inlineSignature = false, super.key});

  final UrlOpener openUrl;

  /// L’Expert signs in the card itself (V11c); the 1 % formulas in a sheet.
  final bool inlineSignature;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final expert = sale.formula == SaleFormula.expert;
    final mandate = state.mandate;
    final signed = sale.isSigned && mandate != null;
    final price = state.basePrice;
    final userId = context.select<ProfileCubit, String?>(
      (cubit) => cubit.state.profile?.id,
    );
    final signer = state.signerFor(userId ?? '');
    final identityOk = !expert || (signer != null && state.isVerified(signer));
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  expert ? l10n.mandateTitleExpert : l10n.mandateTitle,
                  style: RealestyTextStyles.title2.copyWith(
                    fontSize: 17,
                    color: c.encre,
                  ),
                ),
              ),
              if (signed)
                RealestyBadge(
                  label: l10n.mandateSignedBadge,
                  variant: RealestyBadgeVariant.certified,
                )
              else
                RealestyBadge(
                  label: l10n.mandateToSign,
                  variant: RealestyBadgeVariant.toComplete,
                ),
            ],
          ),
          KeyValueRow(label: l10n.mandateType, value: l10n.mandateExclusive),
          KeyValueRow(
            label: l10n.mandateDuration,
            value: expert
                ? l10n.mandateDurationMonths(SaleFormula.expertDurationMonths)
                : l10n.mandateNoCommitment,
          ),
          KeyValueRow(
            label: l10n.mandateTermination,
            value: expert
                ? l10n.mandateTerminationExpert
                : l10n.mandateTerminationAnytime,
          ),
          if (price != null)
            KeyValueRow(
              label: l10n.mandatePrice,
              value: l10n.reportEuros(frenchNumber(price)),
            ),
          KeyValueRow(
            label: l10n.mandateFee,
            value: l10n.mandateFeeValue(sale.formula.feePercent),
            divider: false,
          ),
          if (!signed && !expert)
            Text(
              l10n.mandateWhyExclusive,
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          if (signed) ...[
            Text(
              l10n.mandateSignedOn(fullDate(mandate.signedAt)),
              style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
            ),
            RealestyButton(
              label: l10n.mandateOpenPdf,
              variant: RealestyButtonVariant.secondary,
              leadingIcon: RealestyIcons.file,
              height: 44,
              isLoading: state.busy == SaleAction.mandatePdf,
              onPressed: () => unawaited(_openPdf(context)),
            ),
          ] else if (!state.hasIdentityDocument) ...[
            InlineBanner(message: l10n.saleErrorIdentityDocument),
            RealestyButton(
              label: l10n.mandateOpenVault,
              variant: RealestyButtonVariant.secondary,
              height: 44,
              onPressed: () => context.go(AppRoutes.sellerVault),
            ),
          ] else if (!identityOk) ...[
            InlineBanner(
              message: l10n.saleErrorIdentityNotVerified,
              variant: InlineBannerVariant.info,
            ),
            if (inlineSignature)
              MandateSignatureForm(
                buttonLabel: l10n.mandateSignExpert,
                enabled: false,
              ),
          ] else if (inlineSignature)
            MandateSignatureForm(buttonLabel: l10n.mandateSignExpert)
          else
            RealestyButton(
              label: l10n.mandateSignOnline,
              onPressed: () => unawaited(showMandateSignatureSheet(context)),
            ),
        ],
      ),
    );
  }

  Future<void> _openPdf(BuildContext context) async {
    final message = context.l10n.mandatePdfError;
    final cubit = context.read<SaleCubit>();
    await cubit.openMandate();
    final url = cubit.state.failure == null ? cubit.state.mandateUrl : null;
    if (url != null && await openUrl(Uri.parse(url))) return;
    if (context.mounted) {
      showRealestySnackBar(context, message, isError: true);
    }
  }
}
