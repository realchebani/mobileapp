import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';

/// "Repris de Maison · 12 rue des Lilas" (V1): the owners were copied from
/// another property when this one was added (EPIC-13); nothing otherwise.
class OwnersCopiedNote extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sourceId = context.select<SellerTunnelCubit, String?>(
      (cubit) => cubit.state.property?.ownersCopiedFrom,
    );
    final source = context.select<SellerPropertiesCubit?, String?>((cubit) {
      final property = sourceId == null
          ? null
          : cubit?.state.propertyById(sourceId);
      return property == null ? null : propertyShortLabel(l10n, property);
    });
    if (source == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ProvenanceTag(
        ProvenanceKind.declared,
        label: l10n.ownersCopiedFrom(source),
      ),
    );
  }
}
