import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/mandate/mandate_signature.dart';
import 'package:mobileapp/seller_space/sale/premium/diagnostics_rules.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_sections.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// The photo shoot slots offered (plan Q11): the next 3 working days after
/// [now], at 10 h and 14 h; the team confirms one.
List<DateTime> shootingSlots(DateTime now) {
  final slots = <DateTime>[];
  var day = DateTime(now.year, now.month, now.day);
  while (slots.length < 6) {
    day = DateTime(day.year, day.month, day.day + 1);
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      continue;
    }
    slots
      ..add(DateTime(day.year, day.month, day.day, 10))
      ..add(DateTime(day.year, day.month, day.day, 14));
  }
  return slots;
}

/// V11b · Activation du Premium: the test mandate (missing from the
/// design), a callback by an adviser instead of the SEPA direct debit (no
/// payment in v1), the photo shoot with 3 wished slots, the diagnostics
/// preselected by explicit rules, then the listing (V11a).
class PremiumView extends StatefulWidget {
  const new({required this.openUrl, this.now = DateTime.now, super.key});

  final UrlOpener openUrl;
  final DateTime Function() now;

  @override
  State<PremiumView> createState() => _PremiumViewState();
}

class _PremiumViewState extends State<PremiumView> {
  final GlobalKey _mandateKey = GlobalKey();
  SaleRequestKind _shooting = SaleRequestKind.shootingPhoto;
  final _slots = <DateTime>{};
  Set<Diagnostic>? _diagnostics;

  Future<void> _continue(Sale sale) async {
    if (!sale.isSigned) {
      showRealestySnackBar(
        context,
        context.l10n.saleErrorMandateNotSigned,
        isError: true,
      );
      final mandate = _mandateKey.currentContext;
      if (mandate != null) {
        await Scrollable.ensureVisible(mandate, duration: RealestyMotion.page);
      }
      return;
    }
    unawaited(context.push(AppRoutes.sellerSaleListing(sale.id)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final preset = presetDiagnostics(state.members, year: widget.now().year);
    final diagnostics = _diagnostics ?? preset.keys.toSet();
    return SaleScaffold(
      title: l10n.activationTitle(formulaName(l10n, sale.formula)),
      badges: [
        FormulaBadge(sale.formula),
        RealestyBadge(
          label: sale.isSigned
              ? l10n.activationSigned
              : l10n.activationInProgress,
          variant: sale.isSigned
              ? RealestyBadgeVariant.certified
              : RealestyBadgeVariant.toComplete,
        ),
      ],
      onRefresh: () => context.read<SaleCubit>().refresh(),
      bottom: RealestyButton(
        label: l10n.premiumContinue,
        onPressed: () => unawaited(_continue(sale)),
      ),
      children: [
        Text(
          l10n.activationPremiumHeadline,
          style: RealestyTextStyles.title1.copyWith(
            fontSize: 22,
            color: c.encre,
          ),
        ),
        if (sale.isTest)
          InlineBanner(
            message: l10n.saleTestBanner,
            variant: InlineBannerVariant.info,
          ),
        const FormulaSummaryCard(),
        KeyedSubtree(
          key: _mandateKey,
          child: MandateCard(openUrl: widget.openUrl),
        ),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              CardHeading(l10n.premiumSetupTitle),
              InlineBanner(
                message: l10n.premiumSetupText,
                variant: InlineBannerVariant.info,
                icon: RealestyIcons.phone,
              ),
              ServiceRequestRow(
                kind: SaleRequestKind.premiumSetup,
                title: l10n.premiumCallback,
                subtitle: l10n.premiumCallbackSubtitle,
              ),
            ],
          ),
        ),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              CardHeading(l10n.premiumShootingTitle),
              if (state.openShooting == null) ...[
                Wrap(
                  spacing: RealestySpacing.xs,
                  runSpacing: RealestySpacing.xs,
                  children: [
                    for (final kind in [
                      SaleRequestKind.shootingPhoto,
                      SaleRequestKind.shootingPhotoVideo,
                    ])
                      RealestyChoiceChip(
                        label: kind == SaleRequestKind.shootingPhoto
                            ? l10n.premiumShootingPhoto(
                                frenchNumber(kind.priceEurTtc),
                              )
                            : l10n.premiumShootingVideo(
                                frenchNumber(kind.priceEurTtc),
                              ),
                        selected: _shooting == kind,
                        onSelected: (_) => setState(() => _shooting = kind),
                      ),
                  ],
                ),
                Text(
                  l10n.premiumSlotsText,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
                Wrap(
                  spacing: RealestySpacing.xs,
                  runSpacing: RealestySpacing.xs,
                  children: [
                    for (final slot in shootingSlots(widget.now()))
                      RealestyChoiceChip(
                        label: _slotLabel(context, slot),
                        selected: _slots.contains(slot),
                        onSelected: (_) => setState(() {
                          if (!_slots.remove(slot) && _slots.length < 3) {
                            _slots.add(slot);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              ServiceRequestRow(
                kind: state.openShooting?.kind ?? _shooting,
                title: l10n.premiumShootingRequest,
                subtitle: l10n.premiumShootingSubtitle,
                preferredSlots: [..._slots]..sort(),
              ),
            ],
          ),
        ),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              CardHeading(l10n.premiumDiagnosticsTitle),
              Text(
                l10n.premiumDiagnosticsText,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
              if (!state.hasDiagnostics)
                InlineBanner(message: l10n.premiumNoDiagnostics),
              Text(
                l10n.premiumPreselection(_reasons(context, preset, state)),
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
              Wrap(
                spacing: RealestySpacing.xs,
                runSpacing: RealestySpacing.xs,
                children: [
                  for (final diagnostic in Diagnostic.values)
                    RealestyChoiceChip(
                      label: diagnosticLabel(l10n, diagnostic),
                      selected: diagnostics.contains(diagnostic),
                      onSelected:
                          state.openRequest(SaleRequestKind.diagnostics) != null
                          ? null
                          : (_) => setState(() {
                              final next = {...(_diagnostics ?? diagnostics)};
                              if (!next.remove(diagnostic)) {
                                next.add(diagnostic);
                              }
                              _diagnostics = next;
                            }),
                    ),
                ],
              ),
              ServiceRequestRow(
                kind: SaleRequestKind.diagnostics,
                title: l10n.activationDiagnostics,
                subtitle: l10n.activationDiagnosticsSubtitle,
                diagnostics: [
                  for (final d in Diagnostic.values)
                    if (diagnostics.contains(d)) d,
                ],
              ),
              RealestyButton(
                label: l10n.activationImportDiagnostics,
                variant: RealestyButtonVariant.text,
                onPressed: () => context.go(AppRoutes.sellerVault),
              ),
            ],
          ),
        ),
        const PhotoPreferencesCard(),
        if (sale.stage == SaleStage.planChosen)
          RealestyButton(
            label: l10n.activationChangeFormula,
            variant: RealestyButtonVariant.text,
            onPressed: () => unawaited(changeFormula(context)),
          ),
      ],
    );
  }

  static String _slotLabel(BuildContext context, DateTime slot) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day = DateFormat('E d MMM', locale).format(slot);
    return withRenderableSpaces(context.l10n.premiumSlot(day, slot.hour));
  }

  static String _reasons(
    BuildContext context,
    Map<Diagnostic, DiagnosticReason> preset,
    SaleState state,
  ) {
    final l10n = context.l10n;
    final year = state.mainProperty?.constructionYear;
    return [
      if (year != null) l10n.premiumReasonYear(year),
      if (year == null) l10n.premiumReasonUnknownYear,
      if (preset.containsValue(DiagnosticReason.gasHeating))
        l10n.premiumReasonGas,
    ].join(', ');
  }
}

/// "DPE", "Électricité"…
String diagnosticLabel(AppLocalizations l10n, Diagnostic diagnostic) =>
    switch (diagnostic) {
      Diagnostic.dpe => l10n.diagnosticDpe,
      Diagnostic.electricity => l10n.diagnosticElectricity,
      Diagnostic.gas => l10n.diagnosticGas,
      Diagnostic.asbestos => l10n.diagnosticAsbestos,
      Diagnostic.lead => l10n.diagnosticLead,
      Diagnostic.termites => l10n.diagnosticTermites,
      Diagnostic.risks => l10n.diagnosticRisks,
    };
