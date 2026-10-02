import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/dashboard/widgets/lot_card.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Regrouper des biens en lot" ("Mes biens"): choose at least two
/// properties in no lot and the sale mode; the new lot then opens.
Future<void> showCreateLotSheet(BuildContext context) async {
  final cubit = context.read<SellerPropertiesCubit>();
  final router = GoRouter.of(context);
  final lotId = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: CreateLotSheet(newLotId: generateUuidV4()),
    ),
  );
  if (lotId != null) router.go(AppRoutes.sellerLot(lotId));
}

/// The form of [showCreateLotSheet]; pops with the id of the created lot.
class CreateLotSheet extends StatefulWidget {
  const new({required this.newLotId, super.key});

  /// Id of the lot to create (kept across retries).
  final String newLotId;

  @override
  State<CreateLotSheet> createState() => _CreateLotSheetState();
}

class _CreateLotSheetState extends State<CreateLotSheet> {
  final _selected = <String>{};
  LotSaleMode _saleMode = LotSaleMode.together;
  bool _saving = false;
  bool _showError = false;

  Future<void> _create(List<Property> candidates) async {
    final l10n = context.l10n;
    if (_selected.length < 2) {
      setState(() => _showError = true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<SellerPropertiesCubit>().createLot(
        lotId: widget.newLotId,
        members: [
          for (final property in candidates)
            if (_selected.contains(property.id)) property,
        ],
        saleMode: _saleMode,
      );
      if (mounted) Navigator.of(context).pop(widget.newLotId);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showRealestySnackBar(context, l10n.lotSaveError, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final candidates = context
        .watch<SellerPropertiesCubit>()
        .state
        .lotCandidates;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.lg,
          RealestySpacing.gutter,
          RealestySpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Text(
              l10n.lotCreateTitle,
              style: RealestyTextStyles.title2.copyWith(color: c.encre),
            ),
            Text(
              l10n.lotCreateMessage,
              style: RealestyTextStyles.body.copyWith(
                color: _showError && _selected.length < 2
                    ? c.erreur
                    : c.texteDiscret,
              ),
            ),
            for (final property in candidates)
              RealestyCheckbox(
                value: _selected.contains(property.id),
                label: propertyShortLabel(l10n, property),
                onChanged: _saving
                    ? null
                    : (checked) => setState(() {
                        if (checked) {
                          _selected.add(property.id);
                        } else {
                          _selected.remove(property.id);
                        }
                      }),
              ),
            Wrap(
              spacing: RealestySpacing.xs,
              runSpacing: RealestySpacing.xs,
              children: [
                for (final mode in LotSaleMode.values)
                  RealestyChoiceChip(
                    label: lotSaleModeLabel(l10n, mode),
                    selected: _saleMode == mode,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _saleMode = mode),
                  ),
              ],
            ),
            const SizedBox(height: RealestySpacing.xs),
            RealestyButton(
              label: l10n.lotCreateConfirm,
              isLoading: _saving,
              onPressed: () => _create(candidates),
            ),
          ],
        ),
      ),
    );
  }
}
