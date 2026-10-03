import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/models/sale_entry.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Called when the seller picks [formula] for [target]; returns the error
/// message to show, or null when done (the sheet then closes).
typedef OfferChoiceCallback = Future<String?> Function(
  SaleTarget target,
  SaleFormula formula,
);

/// V10 · Choix de la formule, as a sheet: the targets (this property on
/// its own / the whole lot) when there are two, one tab per formula, the
/// formula's card with its estimated commission, and "Choisir …".
Future<void> showOfferChoiceSheet(
  BuildContext context, {
  required List<SaleTarget> targets,
  required OfferChoiceCallback onChoose,
  SaleFormula? current,
}) {
  final valuations = context.read<ValuationRepository>();
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
    builder: (_) => RepositoryProvider.value(
      value: valuations,
      child: OfferChoiceSheet(
        targets: targets,
        onChoose: onChoose,
        current: current,
      ),
    ),
  );
}

/// The content of [showOfferChoiceSheet].
class OfferChoiceSheet extends StatefulWidget {
  const new({
    required this.targets,
    required this.onChoose,
    this.current,
    super.key,
  });

  final List<SaleTarget> targets;
  final OfferChoiceCallback onChoose;

  /// The formula of the sale whose formula is being changed, if any.
  final SaleFormula? current;

  @override
  State<OfferChoiceSheet> createState() => _OfferChoiceSheetState();
}

class _OfferChoiceSheetState extends State<OfferChoiceSheet> {
  late int _target = 0;

  /// Default tab: Le Premium, as the design (plan Q8).
  late SaleFormula _formula = widget.current ?? SaleFormula.premium;
  bool _saving = false;

  /// Certified value of each target (sum of the members' values).
  final Map<int, int?> _values = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadValues());
  }

  Future<void> _loadValues() async {
    final repository = context.read<ValuationRepository>();
    for (final (index, target) in widget.targets.indexed) {
      try {
        final valuations = await Future.wait([
          for (final member in target.certifiedMembers)
            repository.getLatestValuation(member.id),
        ]).timeout(const Duration(seconds: 15));
        final values = [for (final v in valuations.nonNulls) v.valueEur];
        _values[index] = values.isEmpty ? null : values.reduce((a, b) => a + b);
      } on Object {
        // The commission is then not shown.
        _values[index] = null;
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _choose() async {
    setState(() => _saving = true);
    final error = await widget.onChoose(widget.targets[_target], _formula);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
    showRealestySnackBar(context, error, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final value = _values[_target];
    return SafeArea(
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
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.offerChoiceTitle,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.offerChoiceClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            InlineBanner(
              message: l10n.saleTestBanner,
              variant: InlineBannerVariant.info,
            ),
            if (widget.targets.length > 1)
              RealestySegmentedControl<int>(
                segments: [
                  for (final (index, target) in widget.targets.indexed)
                    RealestySegment(
                      value: index,
                      label: target.isLot
                          ? l10n.offerChoiceTargetLot(target.members.length)
                          : l10n.offerChoiceTargetProperty,
                    ),
                ],
                selected: _target,
                onChanged: (index) => setState(() => _target = index),
              ),
            RealestySegmentedControl<SaleFormula>(
              segments: [
                RealestySegment(
                  value: SaleFormula.essentiel,
                  label: l10n.offerChoiceTabEssentiel,
                ),
                RealestySegment(
                  value: SaleFormula.premium,
                  label: l10n.offerChoiceTabPremium,
                ),
                RealestySegment(
                  value: SaleFormula.expert,
                  label: l10n.offerChoiceTabExpert,
                ),
              ],
              selected: _formula,
              onChanged: (formula) => setState(() => _formula = formula),
            ),
            OfferPlanCard(
              badgeLabel: formulaBadgeLabel(l10n, _formula),
              badgeVariant: formulaBadgeVariant(_formula),
              tagline: switch (_formula) {
                SaleFormula.essentiel => l10n.offerChoiceEssentielTagline,
                SaleFormula.premium => l10n.offerChoicePremiumTagline,
                SaleFormula.expert => l10n.offerChoiceExpertTagline,
              },
              name: formulaName(l10n, _formula),
              rate: l10n.offerChoiceRate(_formula.feePercent),
              rateCaption: l10n.offerChoiceRateCaption,
              fees: switch (_formula) {
                SaleFormula.essentiel => l10n.offerChoiceEssentielFees,
                SaleFormula.premium => l10n.offerChoicePremiumFees(
                  frenchNumber(SaleFormula.premiumSetupFeeEur),
                  frenchNumber(SaleFormula.premiumMonthlyFeeEur),
                ),
                SaleFormula.expert => l10n.offerChoiceExpertFees,
              },
              commission: value == null
                  ? null
                  : _formula == SaleFormula.expert
                  ? l10n.offerChoiceExpertCommission(
                      frenchNumber(_formula.commissionOn(value)),
                    )
                  : l10n.offerChoiceCommission(
                      frenchNumber(_formula.commissionOn(value)),
                    ),
              features: switch (_formula) {
                SaleFormula.essentiel => l10n.offerChoiceEssentielFeatures,
                SaleFormula.premium => l10n.offerChoicePremiumFeatures,
                SaleFormula.expert => l10n.offerChoiceExpertFeatures,
              }.split('\n'),
            ),
            RealestyButton(
              label: _formula == widget.current
                  ? l10n.offerChoiceKeep
                  : l10n.offerChoiceChoose(formulaName(l10n, _formula)),
              isLoading: _saving,
              onPressed: _saving
                  ? null
                  : _formula == widget.current
                  ? () => Navigator.of(context).pop()
                  : () => unawaited(_choose()),
            ),
          ],
        ),
      ),
    );
  }
}
