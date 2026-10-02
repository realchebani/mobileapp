import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/cubit/valuation_cubit.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/dossier_card.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/property_summary_card.dart';
import 'package:mobileapp/seller_space/notifications/notifications_bell.dart';
import 'package:mobileapp/seller_space/widgets/route_available.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/ai_estimate_card.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// V9 · Dashboard propriétaire, root of the "Mon bien" tab once the
/// dossier is sent. Two variants:
/// - *pending* (submitted / in review): AI trend (or a message), link to
///   the market summary (V8b, when its route exists) and "Suivi de mon
///   dossier" → V8;
/// - *certified*: the certified value card → V9b, and "Mettre mon bien en
///   vente" (formula choice, EPIC-08).
///
/// Uses the dossier ([SellerTunnelCubit]), the [ValuationCubit] and the
/// [NotificationsCubit] of the seller space; pull to refresh reloads them.
class DashboardPage extends StatelessWidget {
  const new({
    this.marketSynthesisAvailable,
    this.onBack,
    this.footer,
    super.key,
  });

  /// Whether V8b can be opened; by default, whether the app router has
  /// its route (built by EPIC-05).
  final bool? marketSynthesisAvailable;

  /// Back to "Mes biens" (seller with several properties).
  final VoidCallback? onBack;

  /// Shown at the end (lot of the property, "Ajouter un bien").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final state = context.watch<SellerTunnelCubit>().state;
    final property = state.property!;
    final certified = property.status == PropertyStatus.certified;
    final showMarket =
        marketSynthesisAvailable ??
        isRouteAvailable(context, AppRoutes.sellerMarket(property.id));
    return _ReloadOnResume(
      // Back from the background: the expert may have certified meanwhile.
      onResume: () => _refresh(context, reportFailure: false),
      child: ColoredBox(
        color: c.ivoire,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: c.vertTexte,
            onRefresh: () => _refresh(context),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.md,
                RealestySpacing.gutter,
                RealestySpacing.xl,
              ),
              children: [
                _Header(onBack: onBack),
                const SizedBox(height: RealestySpacing.md),
                ..._spaced([
                  AgentBubble(message: _agentMessage(context.l10n, property)),
                  PropertySummaryCard(property: property),
                  if (certified)
                    const _CertifiedHero()
                  else
                    _PendingHero(property: property, showMarket: showMarket),
                  if (certified)
                    ActionCard(
                      icon: RealestyIcons.trending,
                      title: context.l10n.dashboardSellTitle,
                      subtitle: context.l10n.dashboardSellSubtitle,
                      variant: ActionCardVariant.accent,
                      // TODO(EPIC-08): open V10 (formula choice).
                      onPressed: () => showRealestySnackBar(
                        context,
                        context.l10n.dashboardSellSoon,
                      ),
                    ),
                  DossierCard(
                    state: state,
                    onOpen: () => showDossierSummarySheet(context, state),
                  ),
                  ?footer,
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> children) => [
    for (final (index, child) in children.indexed) ...[
      if (index > 0) const SizedBox(height: 14),
      child,
    ],
  ];

  static String _agentMessage(AppLocalizations l10n, Property property) =>
      switch (property.status) {
        PropertyStatus.certified => l10n.dashboardAgentCertified,
        PropertyStatus.inReview => l10n.dashboardAgentInReview,
        PropertyStatus.draft ||
        PropertyStatus.submitted => l10n.dashboardAgentSubmitted,
      };

  /// Reloads the dossier, the notifications and (once certified) the
  /// valuation; a snackbar tells when the dossier could not be refreshed
  /// (only for an explicit pull, when [reportFailure]).
  static Future<void> _refresh(
    BuildContext context, {
    bool reportFailure = true,
  }) async {
    final tunnel = context.read<SellerTunnelCubit>();
    final valuation = context.read<ValuationCubit>();
    final notifications = context.read<NotificationsCubit>();
    final message = context.l10n.dashboardRefreshError;
    final notificationsLoaded = notifications.load();
    var refreshed = true;
    try {
      await tunnel.refresh();
    } on Object {
      refreshed = false;
    }
    await notificationsLoaded;
    final property = tunnel.state.property!;
    if (property.status == PropertyStatus.certified) {
      await valuation.load(property.id);
    }
    if (!refreshed && reportFailure && context.mounted) {
      showRealestySnackBar(context, message, isError: true);
    }
  }
}

/// Calls [onResume] when the app comes back to the foreground.
class _ReloadOnResume extends StatefulWidget {
  const new({required this.onResume, required this.child});

  final VoidCallback onResume;
  final Widget child;

  @override
  State<_ReloadOnResume> createState() => _ReloadOnResumeState();
}

class _ReloadOnResumeState extends State<_ReloadOnResume> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onResume: () => widget.onResume());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const new({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final firstName = context.select<ProfileCubit, String?>(
      (cubit) => cubit.state.profile?.firstName?.trim(),
    );
    final ownerFirstName = context.select<SellerTunnelCubit, String?>((cubit) {
      for (final owner in cubit.state.owners) {
        if (owner.position == 1) return owner.firstName.trim();
      }
      return null;
    });
    final name = [
      firstName,
      ownerFirstName,
    ].whereType<String>().where((name) => name.isNotEmpty).firstOrNull;
    return Row(
      children: [
        if (onBack != null) ...[
          RealestyIconButton(
            icon: RealestyIcons.chevronLeft,
            semanticLabel: l10n.propertyHomeBack,
            onPressed: onBack,
          ),
          const SizedBox(width: RealestySpacing.xs),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardGreeting,
                style: RealestyTextStyles.label.copyWith(color: c.texteDiscret),
              ),
              Semantics(
                header: true,
                child: Text(
                  name ?? l10n.dashboardTitleFallback,
                  style: RealestyTextStyles.title1.copyWith(
                    fontSize: 24,
                    color: c.encre,
                  ),
                ),
              ),
            ],
          ),
        ),
        const NotificationsBell(),
      ],
    );
  }
}

/// Before certification: the AI trend, the market summary link and the
/// follow-up row (→ V8).
class _PendingHero extends StatelessWidget {
  const new({required this.property, required this.showMarket});

  final Property property;
  final bool showMarket;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final low = property.aiEstimateLowEur;
    final median = property.aiEstimateMedianEur;
    final high = property.aiEstimateHighEur;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        if (low != null && median != null && high != null)
          AiEstimateCard(
            low: low,
            median: median,
            high: high,
            computedAt: property.aiEstimateComputedAt,
          )
        else
          InlineBanner(
            message: l10n.dashboardNoEstimate,
            variant: InlineBannerVariant.info,
          ),
        if (showMarket)
          RealestyButton(
            label: l10n.dashboardMarketLink,
            variant: RealestyButtonVariant.text,
            trailingIcon: RealestyIcons.chevronRight,
            onPressed: () => context.push(AppRoutes.sellerMarket(property.id)),
          ),
        const SizedBox(height: RealestySpacing.xxs),
        ActionCard(
          icon: RealestyIcons.clock,
          title: l10n.dashboardTrackTitle,
          subtitle: property.status == PropertyStatus.inReview
              ? l10n.submittedStepReviewInProgress
              : l10n.submittedStepReviewEstimate,
          onPressed: () => context.goToTunnelStep(SellerTunnelStep.submitted),
        ),
      ],
    );
  }
}

/// Once certified: the certified value (→ V9b), or its loading / error
/// state.
class _CertifiedHero extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<ValuationCubit>().state;
    final valuation = state.valuation;
    if (valuation != null) {
      return CertifiedValueCard(
        valuation: valuation,
        onOpen: () => context.go(
          AppRoutes.sellerReport(
            context.read<SellerTunnelCubit>().state.property!.id,
          ),
        ),
      );
    }
    return switch (state.status) {
      ValuationStatus.failure => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          InlineBanner(message: l10n.dashboardValuationError),
          RealestyButton(
            label: l10n.retryButton,
            variant: RealestyButtonVariant.secondary,
            onPressed: () => context.read<ValuationCubit>().load(
              context.read<SellerTunnelCubit>().state.property!.id,
            ),
          ),
        ],
      ),
      ValuationStatus.success => InlineBanner(
        message: l10n.reportMissing,
        variant: InlineBannerVariant.info,
      ),
      ValuationStatus.initial || ValuationStatus.loading => Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.encre,
          borderRadius: BorderRadius.circular(20),
        ),
        child: CircularProgressIndicator(color: c.lueur),
      ),
    };
  }
}

/// V9 · "Avis de valeur certifié" dark card.
class CertifiedValueCard extends StatelessWidget {
  const new({required this.valuation, required this.onOpen, super.key});

  final Valuation valuation;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final aiTrend = valuation.aiTrendEur;
    return HeroValueCard(
      caption: l10n.dashboardHeroCaption,
      badgeLabel: l10n.dashboardHeroBadge,
      value: euros(l10n, valuation.valueEur),
      details: [
        l10n.dashboardHeroRange(
          frenchNumber(valuation.lowEur),
          frenchNumber(valuation.highEur),
        ),
        if (aiTrend != null) l10n.dashboardHeroAiTrend(frenchNumber(aiTrend)),
      ].join(' · '),
      expertInitials:
          valuation.expertInitials ??
          InitialsAvatar.of(valuation.expertDisplayName),
      expertLabel: l10n.dashboardHeroExpert(
        valuation.expertDisplayName,
        fullDate(valuation.certifiedAt),
      ),
      actionLabel: l10n.dashboardHeroAction,
      actionIcon: RealestyIcons.file,
      onAction: onOpen,
    );
  }
}
