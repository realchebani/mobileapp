import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/essentiel/essentiel_view.dart';
import 'package:mobileapp/seller_space/sale/expert/expert_view.dart';
import 'package:mobileapp/seller_space/sale/mandate/mandate_signature.dart';
import 'package:mobileapp/seller_space/sale/premium/premium_view.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// `/vendeur/ventes/<id>`: the activation screen of the sale's formula —
/// V11 L’Essentiel, V11b Le Premium or V11c L’Expert (under a
/// `SaleRouteScope`).
class SaleActivationPage extends StatelessWidget {
  const new({this.openUrl = launchUrl, super.key});

  /// Opens the mandate PDF.
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    final formula = context.select<SaleCubit, SaleFormula>(
      (cubit) => cubit.state.sale!.formula,
    );
    return switch (formula) {
      SaleFormula.essentiel => EssentielView(openUrl: openUrl),
      SaleFormula.premium => PremiumView(openUrl: openUrl),
      SaleFormula.expert => ExpertView(openUrl: openUrl),
    };
  }
}
