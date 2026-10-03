import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/view/dossier_page.dart';
import 'package:realesty_backoffice/dossier/view/dossier_tab.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/queue/queue.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Property, status, lot, owners, assignment and the main actions.
class DossierHeader extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final busy = context.select<DossierCubit, bool>(
      (cubit) => cubit.state.busy,
    );
    final canStart = context.can(BackOfficeCapability.startReview);
    final area = dossier.areaM2;
    final title = [
      propertyTypeLabel(
        l10n,
        dossier.propertyType,
        dossier.property['property_type_other'] as String?,
      ),
      if (area != null) squareMeters(area),
      ?dossier.city,
    ].join(' · ');
    final small = RealestyTextStyles.bodySmall.copyWith(color: c.encre2);
    final submitted = dossier.submittedAt;
    final lot = dossier.lot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => context.go(BoRoutes.queue),
          icon: const RealestyIcon(RealestyIcons.chevronLeft, size: 16),
          label: Text(l10n.dossierBack),
        ),
        const SizedBox(height: RealestySpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title, style: RealestyTextStyles.title1),
                      ),
                      const SizedBox(width: RealestySpacing.sm),
                      DossierStatusChip(dossier.status),
                    ],
                  ),
                  const SizedBox(height: RealestySpacing.xxs),
                  Text(
                    [
                      if (submitted != null)
                        l10n.dossierSentOn(dateTimeFr(submitted)),
                      if (dossier.assignment != null)
                        l10n.dossierAssignedTo(dossier.assignment!.displayName)
                      else
                        l10n.dossierNotAssigned,
                      dossier.owners.map((o) => o.displayName).join(', '),
                    ].where((t) => t.isNotEmpty).join(' · '),
                    style: small,
                  ),
                ],
              ),
            ),
            if (canStart && dossier.status == DossierStatus.submitted) ...[
              RealestyButton(
                label: l10n.dossierTake,
                expand: false,
                isLoading: busy,
                variant: RealestyButtonVariant.secondary,
                onPressed: () => runGuarded(
                  context,
                  context.read<DossierCubit>().startReview,
                  success: l10n.dossierTaken,
                ),
              ),
              const SizedBox(width: RealestySpacing.sm),
            ],
            if (dossier.status != DossierStatus.certified)
              RealestyButton(
                label: l10n.dossierWriteValuation,
                expand: false,
                onPressed: () => context.go(
                  BoRoutes.dossier(dossier.id, DossierTab.valuation.segment),
                ),
              ),
          ],
        ),
        if (lot != null) ...[
          const SizedBox(height: RealestySpacing.sm),
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                [
                  l10n.dossierLot(
                    lot.name,
                    lot.members
                        .where((m) => m.status == DossierStatus.certified)
                        .length,
                    lot.members.length,
                  ),
                  if (lot.saleMode == 'ensemble')
                    l10n.dossierLotTogether
                  else
                    l10n.dossierLotEither,
                ].join(' · '),
                style: small,
              ),
              for (final member in lot.members)
                if (member.id != dossier.id)
                  ActionChip(
                    label: Text(
                      l10n.dossierLotMember(
                        propertyTypeLabel(l10n, member.propertyType),
                        member.status.label(l10n),
                      ),
                    ),
                    onPressed: member.accessible
                        ? () => context.go(BoRoutes.dossier(member.id))
                        : null,
                  ),
            ],
          ),
        ],
        if (dossier.sellerDeactivated) ...[
          const SizedBox(height: RealestySpacing.sm),
          InlineBanner(message: l10n.dossierSellerDeactivated),
        ],
        if (dossier.role == StaffRole.partnerExpert) ...[
          const SizedBox(height: RealestySpacing.sm),
          InlineBanner(
            message: l10n.dossierPartnerNotice,
            variant: InlineBannerVariant.info,
          ),
        ],
      ],
    );
  }
}
