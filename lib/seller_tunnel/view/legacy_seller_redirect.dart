import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_shell.dart';

/// A route from before EPIC-13 (one property per seller: `/vendeur/rapport`,
/// `/vendeur/marche`, `/vendeur/audit/<step>`), e.g. in an old notification:
/// opens the same screen of the seller's most recently updated property
/// (their only one, usually), or the seller space when there is none.
class LegacySellerRedirect extends StatefulWidget {
  const new({required this.segments, super.key});

  /// Path segments under the property (`['rapport']`,
  /// `['audit', 'technique']`…).
  final List<String> segments;

  @override
  State<LegacySellerRedirect> createState() => _LegacySellerRedirectState();
}

class _LegacySellerRedirectState extends State<LegacySellerRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(target(context.read<SellerPropertiesCubit>().state));
    });
  }

  /// Where the old route leads with the properties of [state].
  String target(SellerPropertiesState state) {
    final properties = [...state.properties]
      ..sort((a, b) {
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
    final property = properties.firstOrNull;
    if (property == null) return AppRoutes.seller;
    return [
      AppRoutes.sellerProperty(property.id),
      ...widget.segments,
    ].join('/');
  }

  @override
  Widget build(BuildContext context) => const SellerLoading();
}
