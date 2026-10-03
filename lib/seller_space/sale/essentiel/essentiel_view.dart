import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/mandate/mandate_signature.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_sections.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// V11 · Activation de L’Essentiel: the formula, the test mandate (signed
/// in a sheet), the photo preferences and assistant, the services à la
/// carte (requests, no payment), the upsell to Le Premium, and "Activer et
/// préparer mon annonce" once the mandate is signed.
class EssentielView extends StatefulWidget {
  const new({required this.openUrl, super.key});

  final UrlOpener openUrl;

  @override
  State<EssentielView> createState() => _EssentielViewState();
}

class _EssentielViewState extends State<EssentielView> {
  final GlobalKey _mandateKey = GlobalKey();

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
    final sale = context.select<SaleCubit, Sale>((cubit) => cubit.state.sale!);
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
        label: l10n.activationContinue,
        variant: RealestyButtonVariant.accent,
        onPressed: () => unawaited(_continue(sale)),
      ),
      children: [
        Text(
          l10n.activationEssentielHeadline,
          style: RealestyTextStyles.title1.copyWith(
            fontSize: 22,
            color: c.encre,
          ),
        ),
        Text(
          l10n.activationEssentielText,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        if (sale.isTest)
          InlineBanner(
            message: l10n.saleTestBanner,
            variant: InlineBannerVariant.info,
          ),
        const ActivationSteps(),
        AgentBubble(message: l10n.activationEssentielAgent),
        const FormulaSummaryCard(),
        KeyedSubtree(
          key: _mandateKey,
          child: MandateCard(openUrl: widget.openUrl),
        ),
        const PhotoPreferencesCard(),
        const ServiceOptionsCard(),
        if (sale.stage == SaleStage.planChosen) const UpsellCard(),
      ],
    );
  }
}
