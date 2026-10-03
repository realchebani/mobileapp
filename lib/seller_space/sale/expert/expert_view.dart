import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/mandate/mandate_signature.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart';
import 'package:mobileapp/ui/ui.dart';

/// V11c · L’Expert: identity → mandate → agent timeline, the mandate with
/// its inline test signature (disabled until the team verified the
/// identity), then "Un agent vous contacte sous 24 h".
class ExpertView extends StatelessWidget {
  const new({required this.openUrl, super.key});

  final UrlOpener openUrl;

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
    final verified = signer != null && state.isVerified(signer);
    final signedAt = state.mandate?.signedAt;
    final signerName = '${signer?.firstName ?? ''} ${signer?.lastName ?? ''}'
        .trim();
    return SaleScaffold(
      title: l10n.activationTitle(formulaName(l10n, sale.formula)),
      badges: [FormulaBadge(sale.formula)],
      onRefresh: () => context.read<SaleCubit>().refresh(),
      children: [
        Text(
          l10n.expertHeadline,
          style: RealestyTextStyles.title1.copyWith(
            fontSize: 22,
            color: c.encre,
          ),
        ),
        Text(
          l10n.expertText,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        if (sale.isTest)
          InlineBanner(
            message: l10n.saleTestBanner,
            variant: InlineBannerVariant.info,
          ),
        SellerSpaceCard(
          child: SubmittedTimeline(
            entries: [
              TimelineEntry(
                title: l10n.expertStepIdentity,
                subtitle: verified
                    ? signerName
                    : state.hasIdentityDocument
                    ? l10n.expertStepIdentityPending
                    : l10n.expertStepIdentityMissing,
                state: verified
                    ? TimelineNodeState.done
                    : TimelineNodeState.current,
              ),
              TimelineEntry(
                title: l10n.expertStepMandate,
                subtitle: signedAt == null
                    ? l10n.expertStepMandateToSign
                    : l10n.mandateSignedOn(fullDate(signedAt)),
                state: sale.isSigned
                    ? TimelineNodeState.done
                    : verified
                    ? TimelineNodeState.current
                    : TimelineNodeState.todo,
              ),
              TimelineEntry(
                title: l10n.expertStepAgent,
                subtitle: l10n.expertStepAgentSubtitle,
                state: sale.isSigned
                    ? TimelineNodeState.current
                    : TimelineNodeState.todo,
              ),
            ],
          ),
        ),
        MandateCard(openUrl: openUrl, inlineSignature: true),
        if (sale.isSigned) ...[
          InlineBanner(
            message: l10n.saleStageExpertSigned,
            variant: InlineBannerVariant.info,
          ),
          RealestyButton(
            label: l10n.saleBackHome,
            variant: RealestyButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.seller),
          ),
        ],
      ],
    );
  }
}
