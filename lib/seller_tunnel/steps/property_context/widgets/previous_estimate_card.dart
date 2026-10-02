import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/context_input_formatters.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';

/// Card of a previous agency estimate (V3 "Estimation précédente"): price,
/// month and agency, and a remove button when [onRemove] is set.
///
/// The fields start from [draft]; edits are reported through the
/// callbacks.
class PreviousEstimateCard extends StatefulWidget {
  const new({
    required this.draft,
    required this.title,
    required this.onPriceChanged,
    required this.onMonthChanged,
    required this.onAgencyChanged,
    this.priceError,
    this.monthError,
    this.onRemove,
    this.footer,
    super.key,
  });

  final EstimateDraft draft;
  final String title;
  final String? priceError;
  final String? monthError;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<String> onAgencyChanged;
  final VoidCallback? onRemove;

  /// Shown at the bottom of the card ("Ajouter une autre agence").
  final Widget? footer;

  @override
  State<PreviousEstimateCard> createState() => _PreviousEstimateCardState();
}

class _PreviousEstimateCardState extends State<PreviousEstimateCard> {
  late final _price = TextEditingController(text: widget.draft.price);
  late final _month = TextEditingController(text: widget.draft.month);
  late final _agency = TextEditingController(text: widget.draft.agency);

  /// A voice turn (or its undo) changed the card: the fields follow
  /// (typing keeps them equal, so nothing happens then).
  @override
  void didUpdateWidget(PreviousEstimateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    void sync(TextEditingController controller, String text) {
      if (controller.text != text) controller.text = text;
    }

    sync(_price, widget.draft.price);
    sync(_month, widget.draft.month);
    sync(_agency, widget.draft.agency);
  }

  @override
  void dispose() {
    _price.dispose();
    _month.dispose();
    _agency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    // With large text, "mm/aaaa" no longer fits half a card: one field per
    // line.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    final price = RealestyTextField(
      label: l10n.contextEstimatePrice,
      controller: _price,
      suffixText: '€',
      errorText: widget.priceError,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: const [AmountInputFormatter()],
      onChanged: widget.onPriceChanged,
    );
    final date = RealestyTextField(
      label: l10n.contextEstimateDate,
      hint: l10n.contextEstimateDateHint,
      leadingIcon: RealestyIcons.calendar,
      controller: _month,
      errorText: widget.monthError,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      inputFormatters: const [MonthInputFormatter()],
      onChanged: widget.onMonthChanged,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Row(
            children: [
              Expanded(child: SectionLabel(widget.title)),
              if (widget.onRemove != null)
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.contextEstimateRemove(widget.title),
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          if (stacked) ...[
            price,
            date,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Expanded(child: price),
                Expanded(child: date),
              ],
            ),
          RealestyTextField(
            label: l10n.contextEstimateAgency,
            hint: l10n.contextEstimateAgencyHint,
            leadingIcon: RealestyIcons.building,
            controller: _agency,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                PropertyContextState.maxAgencyLength,
              ),
            ],
            onChanged: widget.onAgencyChanged,
          ),
          ?widget.footer,
        ],
      ),
    );
  }
}
