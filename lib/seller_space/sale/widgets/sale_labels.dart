import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// "L’Essentiel", "Le Premium", "L’Expert".
String formulaName(AppLocalizations l10n, SaleFormula formula) =>
    switch (formula) {
      SaleFormula.essentiel => l10n.saleFormulaEssentiel,
      SaleFormula.premium => l10n.saleFormulaPremium,
      SaleFormula.expert => l10n.saleFormulaExpert,
    };

/// "L’Essentiel · 1 %"… (badge of the formula).
String formulaBadgeLabel(AppLocalizations l10n, SaleFormula formula) =>
    switch (formula) {
      SaleFormula.essentiel => l10n.saleFormulaBadgeEssentiel,
      SaleFormula.premium => l10n.saleFormulaBadgePremium,
      SaleFormula.expert => l10n.saleFormulaBadgeExpert,
    };

/// The badge colors of [formula].
RealestyBadgeVariant formulaBadgeVariant(SaleFormula formula) =>
    switch (formula) {
      SaleFormula.essentiel => RealestyBadgeVariant.essentiel,
      SaleFormula.premium => RealestyBadgeVariant.premium,
      SaleFormula.expert => RealestyBadgeVariant.expert,
    };

/// The badge of [formula].
class FormulaBadge extends StatelessWidget {
  const new(this.formula, {super.key});

  final SaleFormula formula;

  @override
  Widget build(BuildContext context) => RealestyBadge(
    label: formulaBadgeLabel(context.l10n, formula),
    variant: formulaBadgeVariant(formula),
  );
}

/// Where [sale] stands, in a few words.
String saleStageLabel(BuildContext context, Sale sale) {
  final l10n = context.l10n;
  return switch (sale.stage) {
    SaleStage.planChosen => l10n.saleStagePlanChosen,
    SaleStage.mandateSigned when sale.formula == SaleFormula.expert =>
      l10n.saleStageExpertSigned,
    SaleStage.mandateSigned => l10n.saleStageMandateSigned,
    SaleStage.published => l10n.saleStagePublished(
      longDate(context, sale.publishedAt ?? DateTime.now()),
    ),
    SaleStage.withdrawn => l10n.saleStageWithdrawn,
  };
}

/// The message of a refused sale action.
String saleFailureMessage(
  AppLocalizations l10n,
  SaleFailure failure,
) => switch (failure.reason) {
  SaleFailureReason.propertyNotCertified => l10n.saleErrorNotCertified,
  SaleFailureReason.mainPropertyNotCertified => l10n.saleErrorMainNotCertified,
  SaleFailureReason.lotSoldTogether => l10n.saleErrorLotSoldTogether,
  SaleFailureReason.lotOnSale => l10n.saleErrorLotOnSale,
  SaleFailureReason.memberOnSale => l10n.saleErrorMemberOnSale,
  SaleFailureReason.mandateAlreadySigned => l10n.saleErrorMandateSigned,
  SaleFailureReason.termsNotAccepted => l10n.saleErrorTerms,
  SaleFailureReason.signatureMissing => l10n.saleErrorSignature,
  SaleFailureReason.identityDocumentMissing => l10n.saleErrorIdentityDocument,
  SaleFailureReason.identityNotVerified => l10n.saleErrorIdentityNotVerified,
  SaleFailureReason.requestAlreadyOpen => l10n.saleErrorRequestOpen,
  SaleFailureReason.publishIncomplete => l10n.listingPublishIncomplete,
  SaleFailureReason.mandateNotSigned => l10n.saleErrorMandateNotSigned,
  SaleFailureReason.photoLimitReached => l10n.saleErrorPhotoLimit,
  SaleFailureReason.saleNotFound => l10n.saleNotFound,
  SaleFailureReason.unknown => l10n.saleErrorGeneric,
};
