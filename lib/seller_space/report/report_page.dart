import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/cubit/valuation_cubit.dart';
import 'package:mobileapp/seller_space/report/tabs/price_tab.dart';
import 'package:mobileapp/seller_space/report/tabs/property_tab.dart';
import 'package:mobileapp/seller_space/report/tabs/sector_tab.dart';
import 'package:mobileapp/seller_space/report/tabs/synthesis_tab.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_card.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL (the signed URL of the PDF report).
typedef ReportUrlOpener = Future<bool> Function(Uri uri);

/// The tabs of V9b.
enum ReportTab { synthesis, property, sector, price }

/// V9b · Rapport d’avis de valeur (tab "Mon bien", `/vendeur/rapport`):
/// the expert's structured report, read from the [ValuationCubit] of the
/// seller space, with the optional PDF.
class ReportPage extends StatefulWidget {
  const new({this.openUrl = launchUrl, super.key});

  final ReportUrlOpener openUrl;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  ReportTab _tab = ReportTab.synthesis;
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final tunnel = context.watch<SellerTunnelCubit>().state;
    final property = tunnel.property!;
    final valuationState = context.watch<ValuationCubit>().state;
    final certified = property.status == PropertyStatus.certified;
    final valuation = certified ? valuationState.valuation : null;
    final Widget body;
    if (valuation != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          _Hero(
            property: property,
            valuation: valuation,
            opening: _opening,
            onDownload: () => _openReport(valuation),
          ),
          RealestySegmentedControl<ReportTab>(
            selected: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
            segments: [
              RealestySegment(
                value: ReportTab.synthesis,
                label: l10n.reportTabSynthesis,
              ),
              RealestySegment(
                value: ReportTab.property,
                label: l10n.reportTabProperty,
              ),
              RealestySegment(
                value: ReportTab.sector,
                label: l10n.reportTabSector,
              ),
              RealestySegment(
                value: ReportTab.price,
                label: l10n.reportTabPrice,
              ),
            ],
          ),
          switch (_tab) {
            ReportTab.synthesis => SynthesisTab(
              valuation: valuation,
              // EPIC-08: the sale, or V10.
              onSell: () => startSaleFor(context, property),
            ),
            ReportTab.property => PropertyTab(
              valuation: valuation,
              property: property,
              rooms: tunnel.rooms,
            ),
            ReportTab.sector => SectorTab(valuation: valuation),
            ReportTab.price => PriceTab(valuation: valuation),
          },
        ],
      );
    } else if (certified && valuationState.status == ValuationStatus.failure) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          InlineBanner(message: l10n.dashboardValuationError),
          RealestyButton(
            label: l10n.retryButton,
            onPressed: () => context.read<ValuationCubit>().load(property.id),
          ),
        ],
      );
    } else if (certified && valuationState.status != ValuationStatus.success) {
      body = Padding(
        padding: const EdgeInsets.all(RealestySpacing.xxl),
        child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
      );
    } else {
      body = InlineBanner(
        message: l10n.reportMissing,
        variant: InlineBannerVariant.info,
      );
    }
    return ColoredBox(
      color: c.ivoire,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.xs,
            RealestySpacing.gutter,
            RealestySpacing.xl,
          ),
          children: [
            Row(
              spacing: RealestySpacing.xs,
              children: [
                RealestyIconButton(
                  icon: RealestyIcons.chevronLeft,
                  semanticLabel: l10n.reportBack,
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(context.propertyHomeLocation(property.id)),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.reportTitle,
                      textAlign: TextAlign.center,
                      style: RealestyTextStyles.title2.copyWith(
                        fontSize: 16,
                        color: c.encre,
                      ),
                    ),
                  ),
                ),
                // Keeps the title centred ("Partager" comes later).
                const SizedBox(width: RealestySpacing.minTouchTarget),
              ],
            ),
            const SizedBox(height: RealestySpacing.md),
            body,
          ],
        ),
      ),
    );
  }

  Future<void> _openReport(Valuation valuation) async {
    final repository = context.read<ValuationRepository>();
    final message = context.l10n.reportDownloadError;
    setState(() => _opening = true);
    bool opened;
    try {
      final url = await repository
          .getReportUrl(valuation.reportStoragePath!)
          .timeout(const Duration(seconds: 15));
      opened = await widget.openUrl(Uri.parse(url));
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) showRealestySnackBar(context, message, isError: true);
  }
}

class _Hero extends StatelessWidget {
  const new({
    required this.property,
    required this.valuation,
    required this.opening,
    required this.onDownload,
  });

  final Property property;
  final Valuation valuation;
  final bool opening;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final priceM2 = valuation.priceM2Eur;
    final pages = valuation.reportPages;
    final area = property.livingAreaM2;
    final postcodeCity = [
      property.addressPostcode,
      property.addressCity,
    ].whereType<String>().join(' ');
    final typeAndArea = [
      ?propertyTypeLabel(l10n, property),
      if (area != null) squareMeters(l10n, area),
    ].join(' ');
    final subtitle = [
      postcodeCity,
      typeAndArea,
    ].where((part) => part.isNotEmpty).join(' · ');
    final street = [
      property.addressHousenumber,
      property.addressStreet,
    ].whereType<String>().join(' ');
    final title = street.isNotEmpty
        ? street
        : propertyAddress(property) ?? l10n.dashboardTitleFallback;
    return HeroValueCard(
      header: Row(
        spacing: RealestySpacing.sm,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.imagePlaceholder,
              borderRadius: BorderRadius.circular(RealestyRadius.field),
            ),
            child: RealestyIcon(RealestyIcons.home, color: c.encre2),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RealestyTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.nuitTexte,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.nuitTexteDiscret,
                    ),
                  ),
              ],
            ),
          ),
          HeroBadge(label: l10n.dashboardHeroBadge),
        ],
      ),
      caption: l10n.reportCaption,
      value: euros(l10n, valuation.valueEur),
      details: [
        l10n.reportRange(
          frenchNumber(valuation.lowEur),
          frenchNumber(valuation.highEur),
        ),
        if (priceM2 != null) l10n.reportPriceM2(frenchNumber(priceM2)),
      ].join(' · '),
      expertInitials:
          valuation.expertInitials ??
          InitialsAvatar.of(valuation.expertDisplayName),
      expertLabel: l10n.dashboardHeroExpert(
        valuation.expertDisplayName,
        longDate(context, valuation.certifiedAt),
      ),
      actionLabel: !valuation.hasReport
          ? null
          : pages == null
          ? l10n.reportDownloadNoPages
          : l10n.reportDownload(pages),
      actionIcon: RealestyIcons.download,
      onAction: opening ? null : onDownload,
    );
  }
}
