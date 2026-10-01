import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Opens the read-only "Aperçu de mes données" of the dossier in [state].
Future<void> showDossierSummarySheet(
  BuildContext context,
  SellerTunnelState state,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => DossierSummarySheet(state: state),
  );
}

/// Read-only summary of the main answers of each tunnel step (not designed:
/// built from DS list items). No edit affordance: the dossier was sent.
class DossierSummarySheet extends StatelessWidget {
  const new({required this.state, super.key});

  final SellerTunnelState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final property = state.property!;
    final missing = l10n.submittedSummaryMissing;
    String orMissing(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? missing : text;
    }

    String area(num value) => l10n.submittedSummaryArea(
      frenchNumber(value, decimalDigits: value % 1 == 0 ? 0 : 1),
    );

    final parcels = state.parcels;
    final landArea = parcels.fold<int>(0, (sum, p) => sum + (p.areaM2 ?? 0));
    final livingRooms = state.rooms.where((r) => !r.isAnnex).toList();
    final annexes = state.rooms.where((r) => r.isAnnex).toList();
    String roomsArea(List<Room> rooms) {
      final total = rooms.fold<double>(0, (sum, r) => sum + r.areaM2);
      return frenchNumber(total, decimalDigits: total % 1 == 0 ? 0 : 1);
    }

    final assets = state.lifestyleItems
        .where((item) => item.kind == LifestyleItemKind.asset)
        .length;

    final sections = <(String, List<(String, String)>)>[
      (
        l10n.tunnelStepOwners,
        [
          for (final owner in state.owners)
            (
              l10n.submittedSummaryOwner(owner.position),
              orMissing('${owner.firstName} ${owner.lastName}'),
            ),
          if (state.owners.isEmpty) (l10n.submittedSummaryOwner(1), missing),
        ],
      ),
      (
        SellerTunnelStep.location.label(l10n),
        [
          (l10n.submittedSummaryAddress, orMissing(property.addressLabel)),
          (
            l10n.submittedSummaryParcels,
            parcels.isEmpty
                ? missing
                : parcels
                      .map(
                        (p) => p.section != null && p.numero != null
                            ? l10n.submittedSummaryParcel(p.section!, p.numero!)
                            : p.idu,
                      )
                      .join(', '),
          ),
          if (landArea > 0) (l10n.submittedSummaryLandArea, area(landArea)),
        ],
      ),
      (
        SellerTunnelStep.context.label(l10n),
        [
          (
            l10n.submittedSummaryPropertyType,
            _propertyType(l10n, property) ?? missing,
          ),
          (l10n.submittedSummaryPurchaseYear, orMissing(property.purchaseYear)),
        ],
      ),
      (
        SellerTunnelStep.technical.label(l10n),
        [
          (
            l10n.submittedSummaryConstructionYear,
            orMissing(property.constructionYear),
          ),
          (
            l10n.submittedSummaryLivingArea,
            property.livingAreaM2 == null
                ? missing
                : area(property.livingAreaM2!),
          ),
          (l10n.submittedSummaryRoomsCount, orMissing(property.roomsCount)),
          (l10n.submittedSummaryBedrooms, orMissing(property.bedroomsCount)),
          (
            l10n.submittedSummaryLevels,
            orMissing(_levels(l10n, property.levels)),
          ),
          (
            l10n.submittedSummaryHeating,
            orMissing(_energy(l10n, property.heatingEnergy)),
          ),
          (
            l10n.submittedSummarySanitation,
            orMissing(_sanitation(l10n, property.sanitation)),
          ),
        ],
      ),
      (
        SellerTunnelStep.surfaces.label(l10n),
        [
          (
            l10n.submittedSummaryRooms,
            livingRooms.isEmpty
                ? missing
                : l10n.submittedSummaryRoomsTotal(
                    livingRooms.length,
                    roomsArea(livingRooms),
                  ),
          ),
          if (annexes.isNotEmpty)
            (
              l10n.submittedSummaryAnnexes,
              l10n.submittedSummaryAnnexesTotal(
                annexes.length,
                roomsArea(annexes),
              ),
            ),
        ],
      ),
      (
        SellerTunnelStep.lifestyle.label(l10n),
        [
          (l10n.submittedSummaryAssets, l10n.submittedSummaryCount(assets)),
          (
            l10n.submittedSummaryWatchPoints,
            l10n.submittedSummaryCount(state.lifestyleItems.length - assets),
          ),
        ],
      ),
      (
        SellerTunnelStep.documents.label(l10n),
        [
          (
            l10n.submittedSummaryDocuments,
            l10n.submittedSummaryDocumentsCount(state.documents.length),
          ),
        ],
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RealestySpacing.gutter,
              RealestySpacing.md,
              RealestySpacing.sm,
              RealestySpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.submittedSummaryTitle,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.submittedSummaryClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.xs,
                RealestySpacing.gutter,
                RealestySpacing.xl,
              ),
              children: [
                InlineBanner(
                  message: property.status == PropertyStatus.draft
                      ? l10n.submittedSummaryReadOnlyDraft
                      : l10n.submittedSummaryReadOnly,
                  variant: InlineBannerVariant.info,
                  icon: RealestyIcons.lock,
                ),
                for (final (title, rows) in sections) ...[
                  const SizedBox(height: RealestySpacing.lg),
                  SectionLabel(title),
                  for (final (index, (label, value)) in rows.indexed)
                    RealestyListItem(
                      title: label,
                      subtitle: value,
                      showDivider: index < rows.length - 1,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _propertyType(AppLocalizations l10n, Property property) =>
      switch (property.propertyType) {
        PropertyType.house => l10n.contextTypeHouse,
        PropertyType.apartment => l10n.contextTypeApartment,
        PropertyType.land => l10n.contextTypeLand,
        PropertyType.other =>
          (property.propertyTypeOther?.trim().isEmpty ?? true)
              ? null
              : property.propertyTypeOther!.trim(),
        null => null,
      };

  static String? _levels(AppLocalizations l10n, PropertyLevels? levels) =>
      switch (levels) {
        PropertyLevels.singleStorey => l10n.technicalLevelsSingleStorey,
        PropertyLevels.oneUpperFloor => l10n.technicalLevelsOneUpperFloor,
        PropertyLevels.twoOrMoreUpperFloors => l10n.technicalLevelsTwoOrMore,
        null => null,
      };

  static String? _energy(AppLocalizations l10n, HeatingEnergy? energy) =>
      switch (energy) {
        HeatingEnergy.electricity => l10n.technicalEnergyElectricity,
        HeatingEnergy.gas => l10n.technicalEnergyGas,
        HeatingEnergy.fuelOil => l10n.technicalEnergyFuelOil,
        HeatingEnergy.heatPump => l10n.technicalEnergyHeatPump,
        HeatingEnergy.wood => l10n.technicalEnergyWood,
        null => null,
      };

  static String? _sanitation(AppLocalizations l10n, Sanitation? sanitation) =>
      switch (sanitation) {
        Sanitation.mainsSewer => l10n.technicalSanitationMainsSewer,
        Sanitation.septicTank => l10n.technicalSanitationSepticTank,
        Sanitation.soakaway => l10n.technicalSanitationSoakaway,
        null => null,
      };
}
