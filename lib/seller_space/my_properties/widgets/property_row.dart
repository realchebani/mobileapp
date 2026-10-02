import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/notifications/notifications_bell.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubits.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// A property of "Mes biens": type icon, "Maison · 12 rue des Lilas", its
/// status, a dot for an unread notification; opens its home. A draft has
/// a delete button, confirmed in the row itself.
class PropertyRow extends StatefulWidget {
  const new({
    required this.property,
    this.hasUnread = false,
    this.showDivider = true,
    super.key,
  });

  final Property property;
  final bool hasUnread;
  final bool showDivider;

  @override
  State<PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<PropertyRow> {
  bool _confirming = false;
  bool _deleting = false;

  Future<void> _delete() async {
    final l10n = context.l10n;
    final properties = context.read<SellerPropertiesCubit>();
    final cubits = context.read<SellerTunnelCubits>();
    setState(() => _deleting = true);
    try {
      await properties.deleteProperty(widget.property);
      await cubits.forget(widget.property.id);
    } on Object {
      if (!mounted) return;
      setState(() => _deleting = false);
      showRealestySnackBar(
        context,
        l10n.myPropertiesDeleteError,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final property = widget.property;
    final isDraft = property.status == PropertyStatus.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RealestyListItem(
          title: propertyShortLabel(l10n, property),
          subtitle: propertyStatusLabel(l10n, property),
          leadingIcon: propertyTypeIcon(property.propertyType),
          tone: property.status == PropertyStatus.certified
              ? RealestyListTileTone.success
              : RealestyListTileTone.neutral,
          showDivider: widget.showDivider && !_confirming,
          onTap: () => context.go(AppRoutes.sellerProperty(property.id)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: RealestySpacing.xs,
            children: [
              if (widget.hasUnread)
                UnreadDot(semanticLabel: l10n.myPropertiesUnread),
              if (isDraft)
                RealestyIconButton(
                  icon: RealestyIcons.trash,
                  semanticLabel: l10n.myPropertiesDelete,
                  onPressed: _deleting
                      ? null
                      : () => setState(() => _confirming = !_confirming),
                )
              else
                RealestyIcon(
                  RealestyIcons.chevronRight,
                  size: 18,
                  color: c.texteDiscret,
                ),
            ],
          ),
        ),
        if (_confirming)
          Padding(
            padding: const EdgeInsets.only(bottom: RealestySpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xs,
              children: [
                InlineBanner(
                  message: l10n.myPropertiesDeleteMessage,
                  icon: RealestyIcons.warning,
                ),
                Row(
                  spacing: RealestySpacing.xs,
                  children: [
                    Expanded(
                      child: RealestyButton(
                        label: l10n.myPropertiesDeleteCancel,
                        variant: RealestyButtonVariant.secondary,
                        height: 44,
                        onPressed: _deleting
                            ? null
                            : () => setState(() => _confirming = false),
                      ),
                    ),
                    Expanded(
                      child: RealestyButton(
                        label: l10n.myPropertiesDeleteConfirm,
                        height: 44,
                        isLoading: _deleting,
                        onPressed: _delete,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
