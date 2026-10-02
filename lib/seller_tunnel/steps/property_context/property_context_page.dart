import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/context_input_formatters.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/context_question.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/previous_estimate_card.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V3 · Contexte & type de bien: property type, purchase history, reason
/// for the sale and previous agency estimates.
class PropertyContextPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        return PropertyContextCubit(
          propertyRepository: context.read<PropertyRepository>(),
          property: tunnel.property!,
          estimates: tunnel.previousEstimates,
        );
      },
      child: const PropertyContextView(),
    );
  }
}

class PropertyContextView extends StatefulWidget {
  const new({super.key});

  @override
  State<PropertyContextView> createState() => _PropertyContextViewState();
}

class _PropertyContextViewState extends State<PropertyContextView> {
  static const SellerTunnelStep _step = SellerTunnelStep.context;

  late final PropertyContextState _initial = context
      .read<PropertyContextCubit>()
      .state;
  late final TextEditingController _typeOther = TextEditingController(
    text: _initial.propertyTypeOther,
  );
  late final TextEditingController _commercialUse = TextEditingController(
    text: _initial.commercialUse,
  );
  late final TextEditingController _units = TextEditingController(
    text: _initial.unitsCount,
  );
  late final TextEditingController _year = TextEditingController(
    text: _initial.purchaseYear,
  );
  late final TextEditingController _price = TextEditingController(
    text: _initial.purchasePrice,
  );

  final GlobalKey _typeKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _selfBuiltKey = GlobalKey();
  final GlobalKey _estimatesKey = GlobalKey();

  @override
  void dispose() {
    _typeOther.dispose();
    _commercialUse.dispose();
    _units.dispose();
    _year.dispose();
    _price.dispose();
    super.dispose();
  }

  void _onSubmission(BuildContext context, PropertyContextState state) {
    switch (state.submission) {
      case PropertyContextSubmission.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(previousEstimates: state.savedEstimates);
        unawaited(tunnel.saveAndContinue(_step, state.patch));
      case PropertyContextSubmission.failure:
        showRealestySnackBar(
          context,
          context.l10n.sellerTunnelSaveError,
          isError: true,
        );
      case PropertyContextSubmission.idle:
      case PropertyContextSubmission.inProgress:
        break;
    }
  }

  /// Scrolls to the first unanswered or invalid question.
  void _revealFirstError(PropertyContextState state) {
    final key = state.propertyTypeError != null || state.unitsCountError != null
        ? _typeKey
        : state.purchaseYearError != null || state.purchasePriceError != null
        ? _historyKey
        : state.selfBuiltError != null
        ? _selfBuiltKey
        : _estimatesKey;
    // After the frame, so that a question shown by the last answer exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: RealestyMotion.page,
          alignment: 0.1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<PropertyContextCubit>();
    final state = context.watch<PropertyContextCubit>().state;
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    String? error(PropertyContextError? error, String Function() required) {
      if (!state.showErrors || error == null) return null;
      return switch (error) {
        PropertyContextError.required => required(),
        PropertyContextError.yearRange => l10n.contextErrorYearRange(
          PropertyContextState.minYear.toString(),
          state.today.year.toString(),
        ),
        PropertyContextError.amountRange => l10n.contextErrorAmountRange(
          frenchNumber(PropertyContextState.minAmount),
          frenchNumber(PropertyContextState.maxAmount),
        ),
        PropertyContextError.monthFormat => l10n.contextErrorMonthFormat,
        PropertyContextError.monthTooEarly => l10n.contextErrorMonthTooEarly(
          PropertyContextState.minYear.toString(),
        ),
        PropertyContextError.monthFuture => l10n.contextErrorMonthFuture,
        PropertyContextError.unitsRange => l10n.contextErrorUnitsCount(
          PropertyContextState.minUnits,
          PropertyContextState.maxUnits,
        ),
      };
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<PropertyContextCubit, PropertyContextState>(
          listenWhen: (previous, current) =>
              previous.submission != current.submission,
          listener: _onSubmission,
        ),
        BlocListener<PropertyContextCubit, PropertyContextState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: (context, state) => _revealFirstError(state),
        ),
      ],
      child: TunnelScaffold(
        spacing: 18,
        header: TunnelHeader(
          step: _step,
          onBack: () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          hint: l10n.contextHint,
          label: l10n.tunnelContinue,
          isLoading:
              tunnelSaving ||
              state.submission == PropertyContextSubmission.inProgress,
          onPressed: cubit.submit,
        ),
        children: [
          AgentIntro(message: l10n.contextAgentMessage),
          Column(
            key: _typeKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              SectionLabel(l10n.contextPropertyTypeLabel),
              SelectableCardGrid(
                spacing: 10,
                children: [
                  for (final type in PropertyType.values)
                    SelectableCard(
                      icon: propertyTypeIcon(type),
                      title: propertyTypeName(l10n, type),
                      subtitle: propertyTypeSubtitle(l10n, type),
                      selected: state.propertyType == type,
                      onTap: () => cubit.propertyTypeSelected(type),
                    ),
                ],
              ),
              if (error(
                    state.propertyTypeError,
                    () => l10n.contextErrorPropertyType,
                  )
                  case final message?)
                ContextErrorText(message),
              ..._detail(context, state, error),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              SectionLabel(l10n.contextHistoryLabel),
              Row(
                key: _historyKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: RealestySpacing.sm,
                children: [
                  Expanded(
                    child: RealestyTextField(
                      label: l10n.contextPurchaseYear,
                      controller: _year,
                      errorText: error(
                        state.purchaseYearError,
                        () => l10n.contextErrorPurchaseYear,
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      onChanged: cubit.purchaseYearChanged,
                    ),
                  ),
                  Expanded(
                    child: RealestyTextField(
                      label: l10n.contextPurchasePrice,
                      controller: _price,
                      suffixText: '€',
                      errorText: error(state.purchasePriceError, () => ''),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [AmountInputFormatter()],
                      onChanged: cubit.purchasePriceChanged,
                      footer: Text(
                        l10n.contextOptional,
                        style: RealestyTextStyles.badge.copyWith(
                          fontWeight: FontWeight.w400,
                          color: context.realestyColors.texteDiscret,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (state.asksSelfBuilt)
                ContextQuestion(
                  key: _selfBuiltKey,
                  label: l10n.contextSelfBuiltLabel,
                  errorText: error(
                    state.selfBuiltError,
                    () => l10n.contextErrorSelfBuilt,
                  ),
                  child: _YesNo(
                    value: state.selfBuilt,
                    onChanged: (value) =>
                        cubit.selfBuiltChanged(selfBuilt: value),
                  ),
                ),
              ContextQuestion(
                label: l10n.contextSaleReasonLabel,
                spacing: RealestySpacing.xs,
                child: Wrap(
                  spacing: RealestySpacing.xs,
                  runSpacing: RealestySpacing.xs,
                  children: [
                    for (final reason in SaleReason.values)
                      RealestyChoiceChip(
                        label: _reasonLabel(l10n, reason),
                        selected: state.saleReason == reason,
                        onSelected: (_) => cubit.saleReasonToggled(reason),
                      ),
                  ],
                ),
              ),
              ContextQuestion(
                label: l10n.contextPreviouslyEstimatedLabel,
                child: _YesNo(
                  value: state.previouslyEstimated,
                  onChanged: (value) => cubit.previouslyEstimatedChanged(
                    previouslyEstimated: value,
                  ),
                ),
              ),
              if (state.hasEstimates)
                Column(
                  key: _estimatesKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: RealestySpacing.sm,
                  children: [
                    for (final (index, draft) in state.estimates.indexed)
                      _estimateCard(
                        context,
                        state: state,
                        draft: draft,
                        index: index,
                        error: error,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estimateCard(
    BuildContext context, {
    required PropertyContextState state,
    required EstimateDraft draft,
    required int index,
    required String? Function(PropertyContextError?, String Function()) error,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<PropertyContextCubit>();
    final count = state.estimates.length;
    final isLast = index == count - 1;
    return PreviousEstimateCard(
      key: ValueKey(draft.key),
      draft: draft,
      title: count == 1
          ? l10n.contextEstimateTitle
          : l10n.contextEstimateTitleNumbered(index + 1),
      priceError: error(
        state.estimatePriceError(draft),
        () => l10n.contextErrorEstimatePrice,
      ),
      monthError: error(state.estimateMonthError(draft), () => ''),
      onPriceChanged: (value) => cubit.estimateChanged(draft.key, price: value),
      onMonthChanged: (value) => cubit.estimateChanged(draft.key, month: value),
      onAgencyChanged: (value) =>
          cubit.estimateChanged(draft.key, agency: value),
      onRemove: count > 1 ? () => cubit.estimateRemoved(draft.key) : null,
      footer: isLast
          ? RealestyButton(
              label: l10n.contextEstimateAdd,
              variant: RealestyButtonVariant.text,
              leadingIcon: RealestyIcons.plus,
              height: 40,
              onPressed: cubit.estimateAdded,
            )
          : null,
    );
  }

  /// The precision asked with the selected type (plan §2).
  List<Widget> _detail(
    BuildContext context,
    PropertyContextState state,
    String? Function(PropertyContextError?, String Function()) error,
  ) {
    final l10n = context.l10n;
    final cubit = context.read<PropertyContextCubit>();
    return switch (state.detail) {
      PropertyTypeDetail.none => const [],
      PropertyTypeDetail.otherText => [
        RealestyTextField(
          label: state.propertyType == PropertyType.outbuilding
              ? l10n.contextOutbuildingOtherLabel
              : l10n.contextTypeOtherLabel,
          hint: state.propertyType == PropertyType.outbuilding
              ? l10n.contextOutbuildingOtherHint
              : l10n.contextTypeOtherHint,
          controller: _typeOther,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(
              PropertyContextState.maxOtherTypeLength,
            ),
          ],
          onChanged: cubit.propertyTypeOtherChanged,
        ),
      ],
      PropertyTypeDetail.landKind => [
        ContextQuestion(
          label: l10n.contextLandKindLabel,
          spacing: RealestySpacing.xs,
          child: Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xs,
            children: [
              for (final kind in LandKind.values)
                RealestyChoiceChip(
                  label: switch (kind) {
                    LandKind.buildable => l10n.contextLandKindBuildable,
                    LandKind.notBuildable => l10n.contextLandKindNotBuildable,
                    LandKind.unknown => l10n.contextLandKindUnknown,
                  },
                  selected: state.landKind == kind,
                  onSelected: (_) => cubit.landKindToggled(kind),
                ),
            ],
          ),
        ),
      ],
      PropertyTypeDetail.parkingKind => [
        ContextQuestion(
          label: l10n.contextParkingKindLabel,
          spacing: RealestySpacing.xs,
          child: Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xs,
            children: [
              for (final kind in ParkingKind.values)
                RealestyChoiceChip(
                  label: switch (kind) {
                    ParkingKind.box => l10n.contextParkingKindBox,
                    ParkingKind.garage => l10n.contextParkingKindGarage,
                    ParkingKind.coveredSpace => l10n.contextParkingKindCovered,
                    ParkingKind.outdoorSpace => l10n.contextParkingKindOutdoor,
                  },
                  selected: state.parkingKind == kind,
                  onSelected: (_) => cubit.parkingKindToggled(kind),
                ),
            ],
          ),
        ),
      ],
      PropertyTypeDetail.commercialUse => [
        RealestyTextField(
          label: l10n.contextCommercialUseLabel,
          hint: l10n.contextCommercialUseHint,
          controller: _commercialUse,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(
              PropertyContextState.maxCommercialUseLength,
            ),
          ],
          onChanged: cubit.commercialUseChanged,
        ),
      ],
      PropertyTypeDetail.unitsCount => [
        RealestyTextField(
          label: l10n.contextUnitsCountLabel,
          controller: _units,
          errorText: error(state.unitsCountError, () => ''),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: cubit.unitsCountChanged,
        ),
      ],
    };
  }

  static String _reasonLabel(AppLocalizations l10n, SaleReason reason) =>
      switch (reason) {
        SaleReason.relocation => l10n.contextReasonRelocation,
        SaleReason.moreSpace => l10n.contextReasonMoreSpace,
        SaleReason.separation => l10n.contextReasonSeparation,
        SaleReason.investment => l10n.contextReasonInvestment,
        SaleReason.other => l10n.contextReasonOther,
      };
}

/// "Oui" / "Non" segmented control, with no answer selected by default.
class _YesNo extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RealestySegmentedControl<bool?>(
      segments: [
        RealestySegment(value: true, label: l10n.contextYes),
        RealestySegment(value: false, label: l10n.contextNo),
      ],
      selected: value,
      onChanged: (value) => onChanged(value!),
    );
  }
}
