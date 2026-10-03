import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/lot_card.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_actions.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Name of [target] ("Maison · 12 rue des Lilas", "Lot : Maison + terrain").
String vaultTargetLabel(
  AppLocalizations l10n,
  SellerPropertiesState properties,
  VaultTarget target,
) {
  final lot = properties.lotById(target.lotId);
  if (lot != null) {
    return lotName(l10n, lot, properties.membersOf(lot.id).length);
  }
  final property = properties.propertyById(target.propertyId ?? '');
  return property == null
      ? l10n.myPropertiesUntitled
      : propertyShortLabel(l10n, property);
}

/// The properties shown for [target].
List<Property> vaultTargetMembers(
  SellerPropertiesState properties,
  VaultTarget target,
) {
  final lotId = target.lotId;
  if (lotId != null) return properties.membersOf(lotId);
  final property = properties.propertyById(target.propertyId ?? '');
  return property == null ? const [] : [property];
}

/// The chip choosing the property or the lot of the vault (several
/// properties).
class VaultTargetSelector extends StatelessWidget {
  const new({
    required this.properties,
    required this.target,
    required this.onChanged,
    super.key,
  });

  final SellerPropertiesState properties;
  final VaultTarget target;
  final ValueChanged<VaultTarget> onChanged;

  Future<void> _choose(BuildContext context) async {
    final l10n = context.l10n;
    final chosen = await showVaultOptions<VaultTarget>(
      context,
      title: l10n.vaultSelectorTitle,
      options: [
        for (final lot in properties.lots)
          DocumentOption(
            value: VaultTarget.lot(lot.id),
            title: lotName(l10n, lot, properties.membersOf(lot.id).length),
            subtitle: l10n.vaultSelectorLot,
            icon: RealestyIcons.buildings,
          ),
        for (final property in properties.properties)
          DocumentOption(
            value: VaultTarget.property(property.id),
            title: propertyShortLabel(l10n, property),
            subtitle: propertyStatusLabel(l10n, property),
            icon: propertyTypeIcon(property.propertyType),
          ),
      ],
    );
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final l10n = context.l10n;
    final label = vaultTargetLabel(l10n, properties, target);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: l10n.vaultSelectorSemantics(label),
        excludeSemantics: true,
        child: RealestyPressable(
          onPressed: () => _choose(context),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.sm),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(RealestyRadius.pill),
              border: Border.all(color: c.bordureCarte),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: RealestySpacing.xxs,
              children: [
                RealestyIcon(
                  target.isLot ? RealestyIcons.buildings : RealestyIcons.home,
                  size: 16,
                  color: c.encre,
                ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RealestyTextStyles.chip.copyWith(color: c.encre),
                  ),
                ),
                RealestyIcon(
                  RealestyIcons.chevronDown,
                  size: 16,
                  color: c.texteDiscret,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
