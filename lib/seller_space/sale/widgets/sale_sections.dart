import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/models/sale_entry.dart';
import 'package:mobileapp/seller_space/sale/offer_choice/offer_choice_sheet.dart';
import 'package:mobileapp/seller_space/sale/premium/diagnostics_rules.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Shows the snackbar of an action result: [failure]'s message, or
/// [success] when given.
void showSaleResult(
  BuildContext context,
  SaleFailure? failure, {
  String? success,
}) {
  if (!context.mounted) return;
  final l10n = context.l10n;
  if (failure != null) {
    showRealestySnackBar(
      context,
      saleFailureMessage(l10n, failure),
      isError: true,
    );
  } else if (success != null) {
    showRealestySnackBar(context, success);
  }
}

/// "Votre formule": fees, subscription, commission on the certified value,
/// mandate, and the included features (V11, V11b).
class FormulaSummaryCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<SaleCubit>().state;
    final formula = state.sale!.formula;
    final price = state.basePrice;
    final premium = formula == SaleFormula.premium;
    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Row(
            children: [
              Expanded(child: CardHeading(l10n.activationFormulaTitle)),
              FormulaBadge(formula),
            ],
          ),
          KeyValueRow(
            label: l10n.activationSetupFee,
            value: premium
                ? l10n.activationIndicative(
                    l10n.reportEuros(
                      frenchNumber(SaleFormula.premiumSetupFeeEur),
                    ),
                  )
                : l10n.reportEuros('0'),
          ),
          KeyValueRow(
            label: l10n.activationSubscription,
            value: premium
                ? l10n.activationIndicative(
                    l10n.activationMonthly(
                      frenchNumber(SaleFormula.premiumMonthlyFeeEur),
                    ),
                  )
                : l10n.activationNone,
          ),
          KeyValueRow(
            label: l10n.activationCommission,
            value: price == null
                ? l10n.activationCommissionRate(formula.feePercent)
                : l10n.activationCommissionAmount(
                    formula.feePercent,
                    frenchNumber(formula.commissionOn(price)),
                  ),
          ),
          KeyValueRow(
            label: l10n.activationMandate,
            value: l10n.activationMandateValue,
            divider: false,
          ),
          for (final feature in switch (formula) {
            SaleFormula.essentiel => l10n.offerChoiceEssentielFeatures,
            SaleFormula.premium => l10n.offerChoicePremiumFeatures,
            SaleFormula.expert => l10n.offerChoiceExpertFeatures,
          }.split('\n'))
            _Feature(feature),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RealestySpacing.xs,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RealestyIcon(
            RealestyIcons.check,
            size: 16,
            color: c.vertTexte,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
          ),
        ),
      ],
    );
  }
}

/// "Vos photos": the photo preferences (retouching, virtual staging: "Bientôt",
/// plan Q9) and the photo assistant (listing photos, EPIC-15 photo screen).
class PhotoPreferencesCard extends StatelessWidget {
  const new({this.showAssistant = true, super.key});

  final bool showAssistant;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final busy = state.busy == SaleAction.listing;
    Future<void> save(String column, {required bool value}) async {
      final cubit = context.read<SaleCubit>();
      await cubit.updateListing({column: value});
      if (context.mounted) showSaleResult(context, cubit.state.failure);
    }

    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          CardHeading(l10n.activationPhotosTitle),
          Text(
            l10n.activationPhotosText,
            style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
          ),
          SwitchRow(
            title: l10n.activationRetouch,
            subtitle: l10n.activationRetouchSubtitle,
            badge: RealestyBadge(label: l10n.activationSoon),
            value: sale.aiRetouchWanted,
            onChanged: busy
                ? null
                : (value) => unawaited(
                    save(SaleColumns.aiRetouchWanted, value: value),
                  ),
          ),
          SwitchRow(
            title: l10n.activationStaging,
            subtitle: l10n.activationStagingSubtitle,
            badge: RealestyBadge(label: l10n.activationSoon),
            value: sale.homeStagingWanted,
            onChanged: busy
                ? null
                : (value) => unawaited(
                    save(SaleColumns.homeStagingWanted, value: value),
                  ),
          ),
          if (showAssistant)
            RealestyButton(
              label: l10n.activationPhotosAssistant,
              variant: RealestyButtonVariant.secondary,
              onPressed: () =>
                  context.push(AppRoutes.sellerSaleListingPhotos(sale.id)),
            ),
        ],
      ),
    );
  }
}

/// A service of [kind]: asked ("Un conseiller vous recontacte"), planned
/// ("Rendez-vous le …"), or the button to ask it.
class ServiceRequestRow extends StatelessWidget {
  const new({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.diagnostics = const [],
    this.preferredSlots = const [],
    super.key,
  });

  final SaleRequestKind kind;
  final String title;
  final String subtitle;
  final List<Diagnostic> diagnostics;
  final List<DateTime> preferredSlots;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final request = state.openRequest(kind);
    final busy = state.busy != null;
    final scheduled = request?.scheduledAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xxs,
      children: [
        Row(
          spacing: RealestySpacing.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              l10n.activationPriceTtc(frenchNumber(kind.priceEurTtc)),
              style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
            ),
          ],
        ),
        if (request == null)
          Align(
            alignment: Alignment.centerRight,
            child: RealestyButton(
              label: l10n.activationAdd,
              variant: RealestyButtonVariant.secondary,
              height: 40,
              expand: false,
              onPressed: busy
                  ? null
                  : () async {
                      final cubit = context.read<SaleCubit>();
                      await cubit.requestService(
                        kind,
                        diagnostics: diagnostics,
                        preferredSlots: preferredSlots,
                      );
                      if (context.mounted) {
                        showSaleResult(
                          context,
                          cubit.state.failure,
                          success: l10n.activationRequestSent,
                        );
                      }
                    },
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  scheduled == null
                      ? l10n.activationRequested
                      : l10n.activationScheduled(
                          fullDate(scheduled),
                          timeOfDay(l10n, scheduled),
                        ),
                  style: RealestyTextStyles.bodySmall.copyWith(
                    color: c.vertTexte,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (request.status == SaleRequestStatus.requested)
                RealestyButton(
                  label: l10n.activationCancelRequest,
                  variant: RealestyButtonVariant.text,
                  height: 40,
                  expand: false,
                  onPressed: busy
                      ? null
                      : () async {
                          final cubit = context.read<SaleCubit>();
                          await cubit.cancelRequest(request);
                          if (context.mounted) {
                            showSaleResult(context, cubit.state.failure);
                          }
                        },
                ),
            ],
          ),
      ],
    );
  }
}

/// "Options à la carte" of L’Essentiel: photo shoots and diagnostics as
/// requests (no payment), and the import of existing diagnostics (vault).
class ServiceOptionsCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final members = context.select<SaleCubit, List<Property>>(
      (cubit) => cubit.state.members,
    );
    final diagnostics = presetDiagnostics(
      members,
      year: DateTime.now().year,
    ).keys.toList();
    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Row(
            children: [
              Expanded(child: CardHeading(l10n.activationOptionsTitle)),
              RealestyBadge(label: l10n.activationOptional),
            ],
          ),
          Text(
            l10n.activationOptionsText,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: context.realestyColors.texteDiscret,
            ),
          ),
          ServiceRequestRow(
            kind: SaleRequestKind.shootingPhoto,
            title: l10n.activationShootingPhoto,
            subtitle: l10n.activationShootingPhotoSubtitle,
          ),
          ServiceRequestRow(
            kind: SaleRequestKind.shootingPhotoVideo,
            title: l10n.activationShootingVideo,
            subtitle: l10n.activationShootingVideoSubtitle,
          ),
          ServiceRequestRow(
            kind: SaleRequestKind.diagnostics,
            title: l10n.activationDiagnostics,
            subtitle: l10n.activationDiagnosticsSubtitle,
            diagnostics: diagnostics,
          ),
          RealestyButton(
            label: l10n.activationImportDiagnostics,
            variant: RealestyButtonVariant.text,
            onPressed: () => context.go(AppRoutes.sellerVault),
          ),
        ],
      ),
    );
  }
}

/// The sale target of the [SaleCubit] state (to change the formula).
SaleTarget? saleTargetOf(SaleState state) {
  final sale = state.sale;
  if (sale == null || state.members.isEmpty) return null;
  return SaleTarget.forSale(sale, state.members);
}

/// Opens V10 to change the formula of the sale (mandate not signed).
Future<void> changeFormula(BuildContext context) async {
  final cubit = context.read<SaleCubit>();
  final l10n = context.l10n;
  final target = saleTargetOf(cubit.state);
  if (target == null) return;
  await showOfferChoiceSheet(
    context,
    targets: [target],
    current: cubit.state.sale!.formula,
    onChoose: (_, formula) async {
      await cubit.changeFormula(formula);
      final failure = cubit.state.failure;
      return failure == null ? null : saleFailureMessage(l10n, failure);
    },
  );
}

/// "Besoin d’être plus accompagné ?" → Le Premium (while not signed).
class UpsellCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return RealestyPressable(
      onPressed: () => unawaited(changeFormula(context)),
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.md),
        decoration: BoxDecoration(
          color: c.premiumFond,
          borderRadius: BorderRadius.circular(RealestyRadius.card),
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            RealestyIcon(RealestyIcons.star, color: c.premium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    l10n.activationUpsellTitle,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  Text(
                    l10n.activationUpsellText,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.encre2,
                    ),
                  ),
                ],
              ),
            ),
            RealestyIcon(RealestyIcons.chevronRight, color: c.texteDiscret),
          ],
        ),
      ),
    );
  }
}
