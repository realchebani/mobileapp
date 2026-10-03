import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubits.dart';
import 'package:mobileapp/seller_space/sale/models/sale_entry.dart';
import 'package:mobileapp/seller_space/sale/offer_choice/offer_choice_sheet.dart';
import 'package:mobileapp/seller_space/sale/sale_access.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/withdraw_sheet.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// V10 for a new sale: the seller picks a target and a formula; the sale is
/// created and its activation screen opens.
Future<void> openSaleChoice(
  BuildContext context,
  List<SaleTarget> targets, {
  String Function()? newId,
}) async {
  final repository = saleRepositoryOf(context)!;
  final sales = salesCubitOf(context);
  final router = GoRouter.of(context);
  final l10n = context.l10n;
  final saleId = (newId ?? generateUuidV4)();
  String? created;
  await showOfferChoiceSheet(
    context,
    targets: targets,
    onChoose: (target, formula) async {
      try {
        created = await repository
            .chooseFormula(
              saleId: saleId,
              formula: formula,
              propertyId: target.propertyId,
              lotId: target.lotId,
            )
            .timeout(const Duration(seconds: 15));
        return null;
      } on SaleFailure catch (failure) {
        return saleFailureMessage(l10n, failure);
      } on Object {
        return l10n.saleErrorGeneric;
      }
    },
  );
  final id = created;
  if (id == null) return;
  unawaited(sales?.load());
  unawaited(router.push(AppRoutes.sellerSale(id)));
}

/// "Ma vente" (V9, lot page): formula, where the sale stands, "Continuer"
/// and "Retirer de la vente".
class SaleCard extends StatelessWidget {
  const new({required this.sale, this.memberCount, super.key});

  final Sale sale;

  /// Number of properties of a lot sale.
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final memberCount = this.memberCount;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sale.isLot ? l10n.saleCardLotTitle : l10n.saleCardTitle,
                  style: RealestyTextStyles.listTitle.copyWith(
                    color: c.encre,
                    fontSize: 16,
                  ),
                ),
              ),
              FormulaBadge(sale.formula),
            ],
          ),
          Text(
            saleStageLabel(context, sale),
            style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
          ),
          if (memberCount != null)
            Text(
              l10n.saleCardLotMembers(memberCount),
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          if (sale.isTest)
            Text(
              l10n.saleCardTest,
              style: RealestyTextStyles.caption.copyWith(color: c.attention),
            ),
          const SizedBox(height: RealestySpacing.xxs),
          RealestyButton(
            label: l10n.saleCardOpen,
            height: 44,
            onPressed: () => context.push(
              sale.isSigned && sale.formula.selfPublished
                  ? AppRoutes.sellerSaleListing(sale.id)
                  : AppRoutes.sellerSale(sale.id),
            ),
          ),
          RealestyButton(
            label: l10n.saleCardWithdraw,
            variant: RealestyButtonVariant.text,
            height: 44,
            onPressed: () {
              final cubit = context.read<SaleCubits>().of(sale.id);
              final message = l10n.saleWithdrawDone;
              unawaited(
                showWithdrawSaleSheet(
                  context,
                  onWithdraw: (reason) async {
                    await cubit.withdraw(reason: reason);
                    return cubit.state.failure;
                  },
                ).then((withdrawn) {
                  if (withdrawn && context.mounted) {
                    showRealestySnackBar(context, message);
                  }
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The sale part of V9 for [property]: "Ma vente" when it is on sale (on
/// its own or with its lot), "Mettre mon bien / le lot en vente" when it
/// can be; nothing otherwise. Without sales (flavor without
/// `SALES_ENABLED`), a certified property keeps the "coming soon" card.
class PropertySaleCard extends StatelessWidget {
  const new({required this.property, super.key});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SalesBuilder(
      builder: (context, sales) {
        if (sales == null) {
          if (property.status != PropertyStatus.certified) {
            return const SizedBox.shrink();
          }
          return ActionCard(
            icon: RealestyIcons.trending,
            title: l10n.dashboardSellTitle,
            subtitle: l10n.dashboardSellSubtitle,
            variant: ActionCardVariant.accent,
            onPressed: () =>
                showRealestySnackBar(context, l10n.dashboardSellSoon),
          );
        }
        final state = context.watch<SellerPropertiesCubit>().state;
        final entry = SaleEntry.of(
          property: property,
          properties: state.properties,
          lots: state.lots,
          sales: sales,
        );
        final active = entry.activeSale;
        if (active != null) {
          final lot = entry.lot;
          return SaleCard(
            sale: active,
            memberCount: active.isLot && lot != null
                ? SaleEntry.lotMembers(lot, state.properties).length
                : null,
          );
        }
        if (entry.targets.isEmpty) return const SizedBox.shrink();
        final onlyLot = entry.targets.every((target) => target.isLot);
        return ActionCard(
          icon: RealestyIcons.trending,
          title: onlyLot ? l10n.saleSellLotTitle : l10n.dashboardSellTitle,
          subtitle: l10n.dashboardSellSubtitle,
          variant: ActionCardVariant.accent,
          onPressed: () => unawaited(openSaleChoice(context, entry.targets)),
        );
      },
    );
  }
}

/// The sale part of the lot page: "Ma vente", "Mettre le lot en vente", or
/// why it cannot be put on sale yet; nothing without sales.
class LotSaleCard extends StatelessWidget {
  const new({required this.lot, super.key});

  final PropertyLot lot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return SalesBuilder(
      builder: (context, sales) {
        if (sales == null) return const SizedBox.shrink();
        final properties = context
            .watch<SellerPropertiesCubit>()
            .state
            .properties;
        final members = SaleEntry.lotMembers(lot, properties);
        final active = sales.where((s) => s.lotId == lot.id).firstOrNull;
        if (active != null) {
          return SaleCard(sale: active, memberCount: members.length);
        }
        final target = SaleEntry.lotTarget(
          lot,
          properties: properties,
          sales: sales,
        );
        if (target == null) {
          return Text(
            members.isNotEmpty &&
                    members.first.status == PropertyStatus.certified
                ? l10n.saleLotMemberOnSale
                : l10n.saleLotWaitingMain,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          );
        }
        return ActionCard(
          icon: RealestyIcons.trending,
          title: l10n.saleSellLotTitle,
          subtitle: l10n.saleCardLotMembers(members.length),
          variant: ActionCardVariant.accent,
          onPressed: () => unawaited(openSaleChoice(context, [target])),
        );
      },
    );
  }
}

/// "Mettre en vente" from V9b: the active sale of [property] opens, else
/// V10; without sales, the "coming soon" message.
void startSaleFor(BuildContext context, Property property) {
  final l10n = context.l10n;
  final sales = salesCubitOf(context);
  if (sales == null) {
    showRealestySnackBar(context, l10n.dashboardSellSoon);
    return;
  }
  final state = context.read<SellerPropertiesCubit>().state;
  final entry = SaleEntry.of(
    property: property,
    properties: state.properties,
    lots: state.lots,
    sales: sales.state.sales,
  );
  final active = entry.activeSale;
  if (active != null) {
    unawaited(context.push(AppRoutes.sellerSale(active.id)));
  } else if (entry.targets.isNotEmpty) {
    unawaited(openSaleChoice(context, entry.targets));
  } else {
    showRealestySnackBar(context, l10n.saleErrorNotCertified);
  }
}
