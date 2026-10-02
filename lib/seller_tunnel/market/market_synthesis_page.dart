import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/market/cubit/market_synthesis_cubit.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_comparables.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_format.dart';
import 'package:mobileapp/seller_tunnel/market/widgets/market_range_bar.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V8b · Synthèse du marché: how the property compares with the DVF sales
/// of its sector (non-certified estimate, EPIC-05). Read-only, from the
/// `market_snapshots` result; self-contained behind `/vendeur/marche`.
///
/// Hidden in v1 (no data source): "Partager", the average selling delay,
/// listings, the full report (V9b) and the agent's floating button.
class MarketSynthesisPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final propertyId = context.read<SellerTunnelCubit>().state.property!.id;
    return BlocProvider(
      create: (context) {
        final cubit = MarketSynthesisCubit(
          propertyRepository: context.read<PropertyRepository>(),
          propertyId: propertyId,
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const MarketSynthesisView(),
    );
  }
}

class MarketSynthesisView extends StatelessWidget {
  const new({super.key});

  /// Comparable sales shown before "Voir les N ventes".
  static const shownComparables = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<MarketSynthesisCubit>().state;
    void back() => context.go(SellerTunnelStep.submitted.path);
    final snapshot = state.snapshot;
    return TunnelScaffold(
      header: _Header(onBack: back),
      actionBar: _ActionBar(onBack: back),
      children: switch (state.status) {
        MarketSynthesisStatus.loading => [
          Padding(
            padding: const EdgeInsets.only(top: RealestySpacing.xxl),
            child: Center(
              child: CircularProgressIndicator(
                color: context.realestyColors.vertTexte,
              ),
            ),
          ),
        ],
        MarketSynthesisStatus.ready when snapshot != null => _content(
          context,
          snapshot,
        ),
        MarketSynthesisStatus.failure => [
          _Message(
            message: l10n.marketLoadError,
            onRetry: () => context.read<MarketSynthesisCubit>().load(),
          ),
        ],
        MarketSynthesisStatus.ready || MarketSynthesisStatus.unavailable => [
          _Message(message: l10n.marketUnavailable),
        ],
      },
    );
  }

  List<Widget> _content(BuildContext context, MarketSnapshot snapshot) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final area = snapshot.livingAreaM2 ?? 0;
    final median = snapshot.medianEur ?? 0;
    final ownM2 = area > 0 ? (median / area).round() : 0;
    final computedAt = snapshot.computedAt;
    final low = snapshot.priceM2Low;
    final sectorMedian = snapshot.priceM2Median;
    final high = snapshot.priceM2High;
    final comparables = snapshot.comparables;
    final sales12m = snapshot.sales12m;
    final yoy = snapshot.yoyChangePct;
    final explanation = snapshot.explanation?.trim() ?? '';
    final dataUntil = snapshot.dataUntil;
    return [
      Wrap(
        spacing: RealestySpacing.xs,
        runSpacing: RealestySpacing.xs,
        children: [
          RealestyBadge(
            label: l10n.marketBadge,
            variant: RealestyBadgeVariant.toComplete,
          ),
          if (computedAt != null)
            RealestyBadge(
              label: l10n.marketComputedOn(fullDate(computedAt)),
              icon: RealestyIcons.clock,
            ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.marketHeading,
              style: RealestyTextStyles.title1.copyWith(
                fontSize: 24,
                height: 1.2,
                color: c.encre,
              ),
            ),
          ),
          Text(
            l10n
                .marketSummary(
                  marketTypeLabel(l10n, snapshot.propertyType),
                  frenchNumber(area),
                  snapshot.city ?? '',
                  frenchNumber(median),
                  frenchNumber(ownM2),
                )
                .replaceAll(' ·  · ', ' · '),
            style: RealestyTextStyles.body.copyWith(
              fontSize: 14,
              color: c.texteDiscret,
            ),
          ),
        ],
      ),
      if (low != null && sectorMedian != null && high != null)
        _SectorCard(
          snapshot: snapshot,
          low: low,
          median: sectorMedian,
          high: high,
          own: ownM2,
        ),
      if (sales12m != null || yoy != null)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.xs,
            children: [
              if (sales12m != null)
                Expanded(
                  child: _Tile(
                    value: frenchNumber(sales12m),
                    label: l10n.marketSales12m,
                  ),
                ),
              if (yoy != null)
                Expanded(
                  child: _Tile(
                    value: marketSignedPercent(l10n, yoy),
                    label: l10n.marketYoy,
                  ),
                ),
            ],
          ),
        ),
      if (comparables.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.marketComparablesTitle,
                style: RealestyTextStyles.title2.copyWith(
                  fontSize: 17,
                  color: c.encre,
                ),
              ),
            ),
            MarketComparablesCard(
              sales: comparables.take(shownComparables).toList(),
            ),
            if (comparables.length > shownComparables)
              RealestyButton(
                label: l10n.marketSeeAll(comparables.length),
                variant: RealestyButtonVariant.text,
                onPressed: () =>
                    showMarketComparablesSheet(context, comparables),
              ),
          ],
        ),
      if (snapshot.factors.isNotEmpty) _FactorsCard(factors: snapshot.factors),
      if (explanation.isNotEmpty)
        _ExplanationCard(text: withRenderableSpaces(explanation)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(RealestyRadius.field),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            RealestyIcon(RealestyIcons.infoCircle, size: 18, color: c.encre2),
            Expanded(
              child: Text(
                dataUntil == null
                    ? l10n.marketSourcesNoDate
                    : l10n.marketSources(marketLongMonth(l10n, dataUntil)),
                style: RealestyTextStyles.bodySmall.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: c.encre,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const new({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          10,
          RealestySpacing.gutter,
          RealestySpacing.xs,
        ),
        child: Row(
          spacing: RealestySpacing.xs,
          children: [
            RealestyIconButton(
              icon: RealestyIcons.chevronLeft,
              semanticLabel: l10n.backButtonLabel,
              onPressed: onBack,
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.marketTitle,
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.segment.copyWith(
                    fontFamily: RealestyFonts.sora,
                    fontSize: 16,
                    color: c.encre,
                  ),
                ),
              ),
            ),
            // Keeps the title centred ("Partager" is hidden in v1).
            const SizedBox(width: RealestySpacing.minTouchTarget),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const new({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ivoire,
        border: Border(top: BorderSide(color: c.bordureCarte)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: RealestySpacing.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            14,
            RealestySpacing.gutter,
            0,
          ),
          child: RealestyButton(
            label: context.l10n.marketBackToDossier,
            onPressed: onBack,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(RealestyColors c) => BoxDecoration(
  color: c.surface,
  borderRadius: BorderRadius.circular(RealestyRadius.card),
  border: Border.all(color: c.bordureCarte),
);

class _SectorCard extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.low,
    required this.median,
    required this.high,
    required this.own,
  });

  final MarketSnapshot snapshot;
  final int low;
  final int median;
  final int high;
  final int own;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final count = snapshot.comparablesCount ?? snapshot.comparables.length;
    final years = ((snapshot.months ?? 36) / 12).round();
    final radius = snapshot.radiusM;
    final basis = snapshot.scope == MarketScope.radius && radius != null
        ? l10n.marketBasisRadius(count, marketDistance(l10n, radius), years)
        : l10n.marketBasisCommune(count, snapshot.city ?? '', years);
    final smallText = RealestyTextStyles.badge.copyWith(
      fontWeight: FontWeight.w400,
      color: c.texteDiscret,
    );
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: _cardDecoration(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Text(
            l10n.marketSectorTitle.toUpperCase(),
            style: RealestyTextStyles.caption.copyWith(color: c.texteDiscret),
          ),
          MarketRangeBar(
            low: low,
            median: median,
            high: high,
            own: own,
            semanticLabel: l10n.marketBandSemantics(
              frenchNumber(low),
              frenchNumber(high),
              frenchNumber(median),
              frenchNumber(own),
            ),
          ),
          ExcludeSemantics(
            child: Row(
              spacing: RealestySpacing.xs,
              children: [
                Expanded(
                  child: Text(
                    l10n.marketPriceM2(frenchNumber(low)),
                    style: smallText,
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: Text(
                    l10n.marketSectorMedian(frenchNumber(median)),
                    textAlign: TextAlign.center,
                    style: smallText.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.encre,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.marketPriceM2(frenchNumber(high)),
                    textAlign: TextAlign.right,
                    style: smallText,
                  ),
                ),
              ],
            ),
          ),
          Text(basis, style: smallText),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const new({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.button),
          border: Border.all(color: c.bordureCarte),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(
              value,
              style: RealestyTextStyles.title2.copyWith(
                fontSize: 18,
                color: c.encre,
              ),
            ),
            Text(
              label,
              style: RealestyTextStyles.badge.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: c.texteDiscret,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactorsCard extends StatelessWidget {
  const new({required this.factors});

  final List<MarketFactor> factors;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: _cardDecoration(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.l10n.marketFactorsTitle,
              style: RealestyTextStyles.title2.copyWith(
                fontSize: 16,
                color: c.encre,
              ),
            ),
          ),
          for (final factor in factors)
            Row(
              spacing: 10,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: factor.positive ? c.vertTeinte : c.attentionFond,
                  ),
                  child: Text(
                    factor.positive ? '+' : '−',
                    style: RealestyTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: factor.positive ? c.vertTexte : c.attention,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    factor.label,
                    style: RealestyTextStyles.body.copyWith(
                      fontSize: 14,
                      color: c.encre,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: _cardDecoration(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.marketExplanationTitle,
              style: RealestyTextStyles.title2.copyWith(
                fontSize: 16,
                color: c.encre,
              ),
            ),
          ),
          Text(
            text,
            style: RealestyTextStyles.body.copyWith(
              fontSize: 14,
              height: 1.5,
              color: c.encre,
            ),
          ),
          Text(
            l10n.marketExplanationNote,
            style: RealestyTextStyles.badge.copyWith(
              fontWeight: FontWeight.w400,
              color: c.texteDiscret,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const new({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.only(top: RealestySpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.md,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: RealestyTextStyles.body.copyWith(color: c.encre),
          ),
          if (onRetry != null)
            RealestyButton(
              label: context.l10n.retryButton,
              variant: RealestyButtonVariant.secondary,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
