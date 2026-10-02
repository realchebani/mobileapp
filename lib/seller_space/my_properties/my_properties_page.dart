import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/cubit/notifications_cubit.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/lot_card.dart';
import 'package:mobileapp/seller_space/lot/create_lot_sheet.dart';
import 'package:mobileapp/seller_space/lot/models/lot_estimate.dart';
import 'package:mobileapp/seller_space/my_properties/widgets/property_row.dart';
import 'package:mobileapp/seller_space/notifications/notifications_bell.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Mes biens" (EPIC-13): root of the "Mon bien" tab when the seller has
/// several properties. Sale lots first (with their properties), then the
/// other properties; each row shows the type, the address, the status and
/// a dot for an unread notification, and a draft can be deleted (with a
/// confirmation in the row). "Ajouter un bien" until the test phase limit.
class MyPropertiesPage extends StatelessWidget {
  const new({super.key});

  /// Reloads the properties and the notifications; tells the user when
  /// the properties could not be refreshed.
  static Future<void> _refresh(BuildContext context) async {
    final message = context.l10n.myPropertiesRefreshError;
    final notifications = context.read<NotificationsCubit>().load();
    try {
      await context.read<SellerPropertiesCubit>().refresh();
    } on Object {
      if (context.mounted) {
        showRealestySnackBar(context, message, isError: true);
      }
    }
    await notifications;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SellerPropertiesCubit>().state;
    final unreadIds = context.select<NotificationsCubit, Set<String>>(
      (cubit) => {
        for (final notification in cubit.state.notifications)
          if (!notification.isRead && notification.propertyId != null)
            notification.propertyId!,
      },
    );
    final standalone = state.standaloneProperties;
    Widget rows(List<Property> properties) => SellerSpaceCard(
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
      child: Column(
        children: [
          for (final (index, property) in properties.indexed)
            PropertyRow(
              key: ValueKey(property.id),
              property: property,
              // A property of a lot the expert is valuing stays.
              canDelete: !state.isLotFrozen(property.lotId),
              hasUnread: unreadIds.contains(property.id),
              showDivider: index < properties.length - 1,
            ),
        ],
      ),
    );
    return ColoredBox(
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SellerSpaceTitle(l10n.myPropertiesTitle),
                        Text(
                          l10n.myPropertiesSummary(state.properties.length),
                          style: RealestyTextStyles.label.copyWith(
                            color: c.texteDiscret,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const NotificationsBell(),
                ],
              ),
              const SizedBox(height: RealestySpacing.lg),
              if (state.lots.isNotEmpty) ...[
                SectionLabel(l10n.myPropertiesLotsLabel),
                const SizedBox(height: RealestySpacing.xs),
                for (final lot in state.lots) ...[
                  _LotBlock(lot: lot, rows: rows),
                  const SizedBox(height: RealestySpacing.md),
                ],
              ],
              if (standalone.isNotEmpty) ...[
                SectionLabel(l10n.myPropertiesStandaloneLabel),
                const SizedBox(height: RealestySpacing.xs),
                rows(standalone),
                const SizedBox(height: RealestySpacing.lg),
              ],
              if (state.canAddProperty)
                RealestyButton(
                  label: l10n.myPropertiesAdd,
                  leadingIcon: RealestyIcons.plus,
                  onPressed: () => context.push(AppRoutes.sellerNewProperty),
                )
              else
                InlineBanner(
                  message: l10n.myPropertiesLimit(
                    PropertyRepository.maxProperties,
                  ),
                  variant: InlineBannerVariant.info,
                ),
              if (state.lotCandidates.length >= 2) ...[
                const SizedBox(height: RealestySpacing.xs),
                RealestyButton(
                  label: l10n.myPropertiesCreateLot,
                  variant: RealestyButtonVariant.text,
                  leadingIcon: RealestyIcons.grid,
                  onPressed: () => showCreateLotSheet(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A lot: its card (→ fiche du lot) and the rows of its properties.
class _LotBlock extends StatelessWidget {
  const new({required this.lot, required this.rows});

  final PropertyLot lot;
  final Widget Function(List<Property> properties) rows;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SellerPropertiesCubit>().state;
    final members = state.membersOf(lot.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        LotCard(
          lot: lot,
          members: members,
          estimate: LotEstimate.of(
            members: members,
            parcels: state.parcels,
            mainPropertyId: lot.mainPropertyId,
          ),
          onPressed: () => context.go(AppRoutes.sellerLot(lot.id)),
        ),
        if (members.isNotEmpty) rows(members),
      ],
    );
  }
}
