import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/my_properties/my_properties_page.dart';
import 'package:mobileapp/seller_space/my_property/property_home_page.dart';
import 'package:mobileapp/seller_space/shell/property_valuation_scope.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/view/property_route_scope.dart';

/// Root of the "Mon bien" tab: with one property, its home, as before
/// EPIC-13 ([PropertyHomePage]: start / resume the audit while it is a
/// draft, V9 once it is sent); with several, "Mes biens"
/// ([MyPropertiesPage]).
class MyPropertyPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final onlyId = context.select<SellerPropertiesCubit, String?>((cubit) {
      final properties = cubit.state.properties;
      return properties.length == 1 ? properties.single.id : null;
    });
    if (onlyId == null) return const MyPropertiesPage();
    return PropertyRouteScope(
      key: ValueKey(onlyId),
      propertyId: onlyId,
      child: const PropertyValuationScope(child: PropertyHomePage()),
    );
  }
}
