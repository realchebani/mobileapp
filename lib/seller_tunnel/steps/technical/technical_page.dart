import 'dart:async';
import 'dart:math';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/cubit/technical_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/heating_system_label.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/technical_options.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/widgets/technical_input_formatters.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/widgets/technical_question.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V4b · Audit technique (mode écran): technical identity card of the
/// building (construction, structure, heating, outdoor equipment), adapted
/// to the type of property.
class TechnicalPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TechnicalCubit(
        property: context.read<SellerTunnelCubit>().state.property!,
      ),
      child: const TechnicalView(),
    );
  }
}

class TechnicalView extends StatefulWidget {
  const new({this.voiceSheet = VoiceDefaults.technicalSheet, super.key});

  /// The microphone opens the step sheet (owner decision Q4), otherwise
  /// the V4 audit.
  final bool voiceSheet;

  @override
  State<TechnicalView> createState() => _TechnicalViewState();
}

class _TechnicalViewState extends State<TechnicalView> {
  static const SellerTunnelStep _step = SellerTunnelStep.technical;

  /// The microphone (EPIC-14, owner decision Q4): the V4b voice sheet,
  /// whose answers fill this form (nothing saved before "Continuer").
  Future<void> _openVoiceSheet() async {
    final l10n = context.l10n;
    await showStepVoiceSheet(
      context,
      propertyId: context.read<SellerTunnelCubit>().state.property!.id,
      step: AgentStep.technical,
      form: context.read<TechnicalCubit>(),
      title: l10n.technicalVoiceTitle,
      intro: l10n.technicalVoiceIntro,
    );
  }

  /// "Conversation guidée" (or the microphone without the sheet): saves
  /// what was typed (without moving on), then opens V4, which reads the
  /// dossier. Invalid answers are shown instead.
  Future<void> _openVoiceAudit() async {
    final technical = context.read<TechnicalCubit>();
    final tunnel = context.read<SellerTunnelCubit>();
    final state = technical.state;
    if (!state.isValid) {
      technical.submit();
      return;
    }
    if (state.values.keys.any(state.isChanged)) {
      await tunnel.save(state.patch);
      if (tunnel.state.saveStatus == SellerTunnelSaveStatus.failure) return;
    }
    if (mounted) {
      context.go(
        AppRoutes.sellerPropertyAudit(
          tunnel.state.property!.id,
          SellerTunnelStep.voiceAuditSegment,
        ),
      );
    }
  }

  late final TextEditingController _constructionYear;
  late final TextEditingController _livingArea;
  late final TextEditingController _livingRoomArea;
  late final TextEditingController _roofYear;
  late final TextEditingController _heatPumpYear;
  late final TextEditingController _poolDimensions;
  late final TextEditingController _usableArea;

  final GlobalKey _yearRowKey = GlobalKey();
  final GlobalKey _areaRowKey = GlobalKey();
  final GlobalKey _usableAreaKey = GlobalKey();
  final GlobalKey _levelsKey = GlobalKey();
  final GlobalKey _roofRowKey = GlobalKey();
  final GlobalKey _heatingKey = GlobalKey();
  final GlobalKey _heatPumpRowKey = GlobalKey();
  final GlobalKey _poolRowKey = GlobalKey();

  static final List<TextInputFormatter> _yearFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(4),
  ];

  @override
  void initState() {
    super.initState();
    final initial = context.read<TechnicalCubit>().state;
    _constructionYear = TextEditingController(text: initial.constructionYear);
    _livingArea = TextEditingController(text: initial.livingArea);
    _livingRoomArea = TextEditingController(text: initial.livingRoomArea);
    _roofYear = TextEditingController(text: initial.roofYear);
    _heatPumpYear = TextEditingController(text: initial.heatPumpYear);
    _poolDimensions = TextEditingController(text: initial.poolDimensions);
    _usableArea = TextEditingController(text: initial.usableArea);
  }

  /// The text fields after a voice turn (typing keeps them equal).
  void _syncControllers(TechnicalState state) {
    void sync(TextEditingController controller, String text) {
      if (controller.text != text) controller.text = text;
    }

    sync(_constructionYear, state.constructionYear);
    sync(_livingArea, state.livingArea);
    sync(_livingRoomArea, state.livingRoomArea);
    sync(_roofYear, state.roofYear);
    sync(_heatPumpYear, state.heatPumpYear);
    sync(_poolDimensions, state.poolDimensions);
    sync(_usableArea, state.usableArea);
  }

  @override
  void dispose() {
    _constructionYear.dispose();
    _livingArea.dispose();
    _livingRoomArea.dispose();
    _roofYear.dispose();
    _heatPumpYear.dispose();
    _poolDimensions.dispose();
    _usableArea.dispose();
    super.dispose();
  }

  /// Scrolls to the first missing or invalid answer.
  void _revealFirstError(TechnicalState state) {
    final key = state.constructionYearError != null
        ? _yearRowKey
        : state.livingAreaError != null || state.livingRoomAreaError != null
        ? _areaRowKey
        : state.usableAreaError != null
        ? _usableAreaKey
        : state.levelsError != null
        ? _levelsKey
        : state.roofYearError != null
        ? _roofRowKey
        : state.heatingSystemsError != null
        ? _heatingKey
        : state.heatPumpYearError != null
        ? _heatPumpRowKey
        : _poolRowKey;
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
    final cubit = context.read<TechnicalCubit>();
    final state = context.watch<TechnicalCubit>().state;
    final saving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final enabled = !saving;

    final services = VoiceServices.of(context);
    final sheet =
        widget.voiceSheet &&
        services.isAvailable &&
        state.profile.hasVoice(_step);
    final guided = services.isAvailable && state.profile.voiceAudit;
    return MultiBlocListener(
      listeners: [
        BlocListener<TechnicalCubit, TechnicalState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: (context, state) => _revealFirstError(state),
        ),
        BlocListener<TechnicalCubit, TechnicalState>(
          // A voice turn (or its undo) changed answers: the text fields
          // follow (typing keeps them equal, so nothing happens then).
          listener: (context, state) => _syncControllers(state),
        ),
        BlocListener<TechnicalCubit, TechnicalState>(
          listenWhen: (previous, current) =>
              previous.saveRequests != current.saveRequests,
          listener: (context, state) => unawaited(
            context.read<SellerTunnelCubit>().saveAndContinue(
              _step,
              state.patch,
            ),
          ),
        ),
      ],
      child: TunnelScaffold(
        spacing: RealestySpacing.xl,
        header: TunnelHeader(
          step: _step,
          onBack: saving ? null : () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          // Hidden while the microphone is (voice disabled for the
          // flavor or not consented).
          hint: l10n.tunnelHintVoiceOrScreen,
          label: l10n.technicalSaveAndContinue,
          isLoading: saving,
          onPressed: cubit.submit,
          // The V4b voice sheet (EPIC-14); without it, V4 · audit vocal
          // (only for the dwellings).
          onMicPressed: saving
              ? null
              : sheet
              ? () => unawaited(_openVoiceSheet())
              : guided
              ? _openVoiceAudit
              : null,
        ),
        children: [
          if (sheet && guided)
            Align(
              alignment: Alignment.centerLeft,
              child: RealestyButton(
                label: l10n.technicalVoiceGuided,
                variant: RealestyButtonVariant.text,
                leadingIcon: RealestyIcons.mic,
                height: RealestySpacing.minTouchTarget,
                onPressed: saving ? null : () => unawaited(_openVoiceAudit()),
              ),
            ),
          if (state.asks(TechnicalField.livingArea)) ...[
            _identity(context, state, enabled: enabled),
            _structure(context, state, enabled: enabled),
            _heating(context, state, enabled: enabled),
          ] else ...[
            if (state.asks(TechnicalField.usableArea) ||
                state.asks(TechnicalField.constructionYear))
              _premises(context, state, enabled: enabled),
            if (state.asks(TechnicalField.wallMaterial))
              _structure(context, state, enabled: enabled),
            if (state.asks(TechnicalField.heating))
              _heating(context, state, enabled: enabled)
            else if (state.asks(TechnicalField.sanitation))
              _section(l10n.technicalSanitation, [
                _sanitationChips(context, state, enabled: enabled),
              ]),
            if (state.asks(TechnicalField.parkingFeatures))
              _features(context, state, enabled: enabled),
          ],
          if (state.asks(TechnicalField.outdoorEquipment))
            _outdoor(context, state, enabled: enabled),
          InlineBanner(
            message: l10n.technicalProvenanceNote,
            variant: InlineBannerVariant.info,
          ),
        ],
      ),
    );
  }

  /// The message of [error] once errors are shown.
  String? _error(
    BuildContext context,
    TechnicalState state,
    TechnicalError? error, {
    String Function()? required,
    int? min,
  }) {
    if (!state.showErrors || error == null) return null;
    final l10n = context.l10n;
    return switch (error) {
      TechnicalError.required => required!(),
      TechnicalError.yearRange => l10n.technicalErrorYearRange(
        '$min',
        '${state.today.year}',
      ),
      TechnicalError.areaRange => l10n.technicalErrorAreaRange(
        '$min',
        frenchNumber(TechnicalState.maxArea),
      ),
      TechnicalError.livingRoomTooLarge =>
        l10n.technicalErrorLivingRoomTooLarge,
      TechnicalError.dimensions => l10n.technicalErrorDimensions,
    };
  }

  /// The provenance tag of [column] when it has a value: always for the
  /// fields of the design ([always]), otherwise only when the answer does
  /// not come from the seller.
  Widget? _provenance(
    TechnicalState state,
    String column, {
    required bool hasValue,
    bool always = false,
  }) {
    if (!hasValue) return null;
    final provenance = state.provenanceOf(column);
    final tag = !always && provenance == Provenance.declared
        ? null
        : TechnicalProvenanceTag(provenance);
    if (!state.dictated.contains(column)) return tag;
    // Answered by voice on this visit.
    return Wrap(
      spacing: RealestySpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [?tag, const DictatedTag()],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.sm,
      children: [SectionTitle(title), ...children],
    );
  }

  Widget _pair(
    Widget first,
    Widget second, {
    required (String, String) labels,
    Key? key,
  }) => _PairRow(key: key, labels: labels, first: first, second: second);

  /// An optional select; once answered, "Non précisé" clears it.
  Widget _select<T extends Object>({
    required TechnicalState state,
    required String label,
    required String column,
    required T? value,
    required Map<T, String> options,
    required ValueChanged<T?>? onChanged,
  }) {
    final tag = _provenance(state, column, hasValue: value != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        RealestySelect<T?>(
          label: label,
          hint: context.l10n.technicalSelectHint,
          value: value,
          options: [
            for (final MapEntry(:key, :value) in options.entries)
              RealestySelectOption(value: key, label: value),
            if (value != null)
              RealestySelectOption(
                value: null,
                label: context.l10n.technicalNotSpecified,
              ),
          ],
          onChanged: onChanged,
        ),
        ?tag,
      ],
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required String Function(T) label,
    required bool Function(T) selected,
    required ValueChanged<T>? onTap,
  }) {
    return Wrap(
      spacing: RealestySpacing.xs,
      runSpacing: RealestySpacing.xs,
      children: [
        for (final value in values)
          RealestyChoiceChip(
            label: label(value),
            selected: selected(value),
            onSelected: onTap == null ? null : (_) => onTap(value),
          ),
      ],
    );
  }

  Widget _identity(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    final c = context.realestyColors;
    return _section(l10n.technicalSectionIdentity, [
      _pair(
        key: _yearRowKey,
        labels: (l10n.technicalConstructionYear, l10n.technicalExposure),
        RealestyTextField(
          label: l10n.technicalConstructionYear,
          controller: _constructionYear,
          enabled: enabled,
          errorText: _error(
            context,
            state,
            state.constructionYearError,
            required: () => l10n.technicalErrorConstructionYear,
            min: TechnicalState.minConstructionYear,
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: _yearFormatters,
          onChanged: cubit.constructionYearChanged,
          footer: _provenance(
            state,
            PropertyColumns.constructionYear,
            hasValue: state.constructionYear.isNotEmpty,
          ),
        ),
        _select(
          state: state,
          label: l10n.technicalExposure,
          column: PropertyColumns.orientation,
          value: state.exposure,
          options: {
            for (final value in Exposure.values)
              value: _exposureLabel(l10n, value),
          },
          onChanged: enabled ? cubit.exposureChanged : null,
        ),
      ),
      _pair(
        key: _areaRowKey,
        labels: (l10n.technicalLivingArea, l10n.technicalLivingRoomArea),
        RealestyTextField(
          label: l10n.technicalLivingArea,
          controller: _livingArea,
          suffixText: 'm²',
          enabled: enabled,
          errorText: _error(
            context,
            state,
            state.livingAreaError,
            required: () => l10n.technicalErrorLivingArea,
            min: TechnicalState.minLivingArea,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: const [DecimalInputFormatter()],
          onChanged: cubit.livingAreaChanged,
          footer: _provenance(
            state,
            PropertyColumns.livingAreaM2,
            hasValue: state.livingArea.isNotEmpty,
          ),
        ),
        RealestyTextField(
          label: l10n.technicalLivingRoomArea,
          controller: _livingRoomArea,
          suffixText: 'm²',
          enabled: enabled,
          errorText: _error(
            context,
            state,
            state.livingRoomAreaError,
            min: TechnicalState.minLivingRoomArea,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: const [DecimalInputFormatter()],
          onChanged: cubit.livingRoomAreaChanged,
          footer: _provenance(
            state,
            PropertyColumns.livingRoomAreaM2,
            hasValue: state.livingRoomArea.isNotEmpty,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.all(RealestySpacing.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.card),
          border: Border.all(color: c.bordureCarte),
        ),
        child: Column(
          spacing: 10,
          children: [
            RealestyStepper(
              title: l10n.technicalRooms,
              value: state.rooms,
              min: TechnicalState.minRooms,
              max: TechnicalState.maxRooms,
              decrementLabel: l10n.technicalStepperDecrement,
              incrementLabel: l10n.technicalStepperIncrement,
              onChanged: enabled ? cubit.roomsChanged : null,
            ),
            Divider(height: 1, thickness: 1, color: c.bordureCarte),
            RealestyStepper(
              title: l10n.technicalBedrooms,
              value: state.bedrooms,
              max: state.rooms,
              decrementLabel: l10n.technicalStepperDecrement,
              incrementLabel: l10n.technicalStepperIncrement,
              onChanged: enabled ? cubit.bedroomsChanged : null,
            ),
          ],
        ),
      ),
      if (state.asks(TechnicalField.levels))
        TechnicalQuestion(
          key: _levelsKey,
          label: l10n.technicalLevels,
          errorText: _error(
            context,
            state,
            state.levelsError,
            required: () => l10n.technicalErrorLevels,
          ),
          child: RealestySegmentedControl<PropertyLevels?>(
            segments: [
              for (final levels in PropertyLevels.values)
                RealestySegment(
                  value: levels,
                  label: _levelsLabel(l10n, levels),
                ),
            ],
            selected: state.levels,
            onChanged: enabled ? (value) => cubit.levelsChanged(value!) : null,
          ),
        ),
    ]);
  }

  Widget _structure(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    return _section(l10n.technicalSectionStructure, [
      TechnicalQuestion(
        label: l10n.technicalWallMaterial,
        footer: _provenance(
          state,
          PropertyColumns.wallMaterial,
          hasValue: state.wallMaterial != null,
        ),
        child: _chips(
          values: WallMaterial.values,
          label: (value) => _wallLabel(l10n, value),
          selected: (value) => state.wallMaterial == value,
          onTap: enabled ? cubit.wallMaterialToggled : null,
        ),
      ),
      if (state.asks(TechnicalField.adjacency))
        TechnicalQuestion(
          label: l10n.technicalAdjacency,
          footer: _provenance(
            state,
            PropertyColumns.adjacency,
            hasValue: state.adjacency != null,
          ),
          child: _chips(
            values: Adjacency.values,
            label: (value) => _adjacencyLabel(l10n, value),
            selected: (value) => state.adjacency == value,
            onTap: enabled ? cubit.adjacencyToggled : null,
          ),
        ),
      if (state.asks(TechnicalField.roof))
        _pair(
          key: _roofRowKey,
          labels: (l10n.technicalRoof, l10n.technicalRoofYear),
          _select(
            state: state,
            label: l10n.technicalRoof,
            column: PropertyColumns.roofType,
            value: state.roofType,
            options: {
              for (final value in RoofType.values)
                value: _roofLabel(l10n, value),
            },
            onChanged: enabled ? cubit.roofTypeChanged : null,
          ),
          RealestyTextField(
            label: l10n.technicalRoofYear,
            controller: _roofYear,
            enabled: enabled,
            errorText: _error(
              context,
              state,
              state.roofYearError,
              min: state.roofMinYear,
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: _yearFormatters,
            onChanged: cubit.roofYearChanged,
            footer: _provenance(
              state,
              PropertyColumns.roofYear,
              hasValue: state.roofYear.isNotEmpty,
              always: true,
            ),
          ),
        ),
    ]);
  }

  Widget _heating(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    final sanitation = state.asks(TechnicalField.sanitation);
    return _section(
      sanitation ? l10n.technicalSectionHeating : l10n.technicalHeating,
      [
        TechnicalQuestion(
          key: _heatingKey,
          label: l10n.technicalHeatingSystems,
          errorText: _error(
            context,
            state,
            state.heatingSystemsError,
            required: () => l10n.technicalErrorHeatingSystems,
          ),
          footer: _provenance(
            state,
            PropertyColumns.heatingSystems,
            hasValue: state.heatingSystems.isNotEmpty,
          ),
          child: _chips(
            values: HeatingSystem.values,
            label: (value) => heatingSystemLabel(l10n, value),
            selected: state.heatingSystems.contains,
            onTap: enabled ? cubit.heatingSystemToggled : null,
          ),
        ),
        if (state.asksHeatPump)
          _pair(
            key: _heatPumpRowKey,
            labels: (l10n.technicalHeatPumpType, l10n.technicalHeatPumpYear),
            _select(
              state: state,
              label: l10n.technicalHeatPumpType,
              column: PropertyColumns.heatPumpType,
              value: state.heatPumpType,
              options: {
                for (final value in HeatPumpType.values)
                  value: _heatPumpLabel(l10n, value),
              },
              onChanged: enabled ? cubit.heatPumpTypeChanged : null,
            ),
            RealestyTextField(
              label: l10n.technicalHeatPumpYear,
              controller: _heatPumpYear,
              enabled: enabled,
              errorText: _error(
                context,
                state,
                state.heatPumpYearError,
                min: TechnicalState.minHeatPumpYear,
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: _yearFormatters,
              onChanged: cubit.heatPumpYearChanged,
              footer: _provenance(
                state,
                PropertyColumns.heatPumpYear,
                hasValue: state.heatPumpYear.isNotEmpty,
                always: true,
              ),
            ),
          ),
        if (sanitation)
          TechnicalQuestion(
            label: l10n.technicalSanitation,
            footer: _provenance(
              state,
              PropertyColumns.sanitation,
              hasValue: state.sanitation != null,
            ),
            child: _sanitationChips(context, state, enabled: enabled),
          ),
      ],
    );
  }

  /// Surface utile, construction year and level of a parking space, an
  /// outbuilding, a commercial premises or a whole building.
  Widget _premises(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    final title = switch (state.propertyType) {
      PropertyType.parking => l10n.technicalSectionPlace,
      PropertyType.building => l10n.technicalSectionBuilding,
      _ => l10n.technicalSectionPremises,
    };
    return _section(title, [
      if (state.asks(TechnicalField.usableArea))
        RealestyTextField(
          key: _usableAreaKey,
          label: l10n.technicalUsableArea,
          controller: _usableArea,
          suffixText: 'm²',
          enabled: enabled,
          errorText: _error(
            context,
            state,
            state.usableAreaError,
            required: () => l10n.technicalErrorUsableArea,
            min: TechnicalState.minUsableArea,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: const [DecimalInputFormatter()],
          onChanged: cubit.usableAreaChanged,
          footer: _provenance(
            state,
            PropertyColumns.usableAreaM2,
            hasValue: state.usableArea.isNotEmpty,
          ),
        ),
      if (state.asks(TechnicalField.constructionYear))
        RealestyTextField(
          key: _yearRowKey,
          label: l10n.technicalConstructionYear,
          controller: _constructionYear,
          enabled: enabled,
          errorText: _error(
            context,
            state,
            state.constructionYearError,
            required: () => l10n.technicalErrorConstructionYear,
            min: TechnicalState.minConstructionYear,
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: _yearFormatters,
          onChanged: cubit.constructionYearChanged,
          footer: _provenance(
            state,
            PropertyColumns.constructionYear,
            hasValue: state.constructionYear.isNotEmpty,
          ),
        ),
      if (state.asks(TechnicalField.parkingLevel))
        TechnicalQuestion(
          label: l10n.technicalParkingLevel,
          child: _chips(
            values: ParkingLevel.values,
            label: (value) => switch (value) {
              ParkingLevel.basement => l10n.technicalParkingLevelBasement,
              ParkingLevel.groundFloor => l10n.technicalParkingLevelGround,
              ParkingLevel.upperFloor => l10n.technicalParkingLevelUpper,
              ParkingLevel.outdoor => l10n.technicalParkingLevelOutdoor,
            },
            selected: (value) => state.parkingLevel == value,
            onTap: enabled ? cubit.parkingLevelToggled : null,
          ),
        ),
    ]);
  }

  /// Equipment of a parking space or an outbuilding.
  Widget _features(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    return _section(l10n.technicalSectionEquipment, [
      TechnicalQuestion(
        label: l10n.technicalParkingFeatures,
        child: _chips(
          values: state.profile.parkingFeatureChoices,
          label: (value) => switch (value) {
            ParkingFeature.motorizedDoor => l10n.technicalFeatureMotorizedDoor,
            ParkingFeature.electricity => l10n.technicalFeatureElectricity,
            ParkingFeature.chargingPoint => l10n.technicalFeatureChargingPoint,
            ParkingFeature.water => l10n.technicalFeatureWater,
            ParkingFeature.securedAccess => l10n.technicalFeatureSecuredAccess,
          },
          selected: state.parkingFeatures.contains,
          onTap: enabled ? cubit.parkingFeatureToggled : null,
        ),
      ),
    ]);
  }

  Widget _sanitationChips(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    return _chips(
      values: Sanitation.values,
      label: (value) => _sanitationLabel(l10n, value),
      selected: (value) => state.sanitation == value,
      onTap: enabled ? cubit.sanitationToggled : null,
    );
  }

  Widget _outdoor(
    BuildContext context,
    TechnicalState state, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<TechnicalCubit>();
    return _section(l10n.technicalSectionOutdoor, [
      TechnicalQuestion(
        label: l10n.technicalOutdoorEquipment,
        footer: _provenance(
          state,
          PropertyColumns.outdoorEquipment,
          hasValue: state.outdoorEquipment.isNotEmpty,
        ),
        child: _chips(
          values: OutdoorEquipment.values,
          label: (value) => _outdoorLabel(l10n, value),
          selected: state.outdoorEquipment.contains,
          onTap: enabled ? cubit.outdoorEquipmentToggled : null,
        ),
      ),
      if (state.asksPool)
        _pair(
          key: _poolRowKey,
          labels: (l10n.technicalPoolType, l10n.technicalPoolDimensions),
          _select(
            state: state,
            label: l10n.technicalPoolType,
            column: PropertyColumns.poolType,
            value: state.poolType,
            options: {
              for (final value in PoolType.values)
                value: _poolLabel(l10n, value),
            },
            onChanged: enabled ? cubit.poolTypeChanged : null,
          ),
          RealestyTextField(
            label: l10n.technicalPoolDimensions,
            hint: l10n.technicalPoolDimensionsHint,
            controller: _poolDimensions,
            suffixText: 'm',
            enabled: enabled,
            errorText: _error(context, state, state.poolDimensionsError),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            inputFormatters: const [DimensionsInputFormatter()],
            onChanged: cubit.poolDimensionsChanged,
            footer: _provenance(
              state,
              PropertyColumns.poolLengthM,
              hasValue: state.poolDimensions.trim().isNotEmpty,
              always: true,
            ),
          ),
        ),
    ]);
  }

  static String _exposureLabel(AppLocalizations l10n, Exposure value) =>
      switch (value) {
        Exposure.north => l10n.technicalExposureNorth,
        Exposure.northEast => l10n.technicalExposureNorthEast,
        Exposure.east => l10n.technicalExposureEast,
        Exposure.southEast => l10n.technicalExposureSouthEast,
        Exposure.south => l10n.technicalExposureSouth,
        Exposure.southWest => l10n.technicalExposureSouthWest,
        Exposure.west => l10n.technicalExposureWest,
        Exposure.northWest => l10n.technicalExposureNorthWest,
        Exposure.dualAspect => l10n.technicalExposureDualAspect,
      };

  static String _levelsLabel(AppLocalizations l10n, PropertyLevels value) =>
      switch (value) {
        PropertyLevels.singleStorey => l10n.technicalLevelsSingleStorey,
        PropertyLevels.oneUpperFloor => l10n.technicalLevelsOneUpperFloor,
        PropertyLevels.twoOrMoreUpperFloors => l10n.technicalLevelsTwoOrMore,
      };

  static String _wallLabel(AppLocalizations l10n, WallMaterial value) =>
      switch (value) {
        WallMaterial.concreteBlock => l10n.technicalWallConcreteBlock,
        WallMaterial.brick => l10n.technicalWallBrick,
        WallMaterial.stone => l10n.technicalWallStone,
        WallMaterial.concrete => l10n.technicalWallConcrete,
        WallMaterial.rubble => l10n.technicalWallRubble,
        WallMaterial.wood => l10n.technicalWallWood,
        WallMaterial.rammedEarth => l10n.technicalWallRammedEarth,
      };

  static String _adjacencyLabel(AppLocalizations l10n, Adjacency value) =>
      switch (value) {
        Adjacency.detached => l10n.technicalAdjacencyDetached,
        Adjacency.oneSide => l10n.technicalAdjacencyOneSide,
        Adjacency.twoSides => l10n.technicalAdjacencyTwoSides,
        Adjacency.threeSides => l10n.technicalAdjacencyThreeSides,
      };

  static String _roofLabel(AppLocalizations l10n, RoofType value) =>
      switch (value) {
        RoofType.tiles => l10n.technicalRoofTiles,
        RoofType.slate => l10n.technicalRoofSlate,
        RoofType.flatRoof => l10n.technicalRoofFlat,
        RoofType.steelSheet => l10n.technicalRoofSteelSheet,
        RoofType.zinc => l10n.technicalRoofZinc,
        RoofType.other => l10n.technicalRoofOther,
      };

  static String _heatPumpLabel(AppLocalizations l10n, HeatPumpType value) =>
      switch (value) {
        HeatPumpType.airToWater => l10n.technicalHeatPumpAirToWater,
        HeatPumpType.airToAir => l10n.technicalHeatPumpAirToAir,
        HeatPumpType.geothermal => l10n.technicalHeatPumpGeothermal,
      };

  static String _sanitationLabel(AppLocalizations l10n, Sanitation value) =>
      switch (value) {
        Sanitation.mainsSewer => l10n.technicalSanitationMainsSewer,
        Sanitation.septicTank => l10n.technicalSanitationSepticTank,
        Sanitation.soakaway => l10n.technicalSanitationSoakaway,
      };

  static String _outdoorLabel(AppLocalizations l10n, OutdoorEquipment value) =>
      switch (value) {
        OutdoorEquipment.pool => l10n.technicalOutdoorPool,
        OutdoorEquipment.garage => l10n.technicalOutdoorGarage,
        OutdoorEquipment.terrace => l10n.technicalOutdoorTerrace,
        OutdoorEquipment.gardenShed => l10n.technicalOutdoorGardenShed,
        OutdoorEquipment.motorizedGate => l10n.technicalOutdoorMotorizedGate,
      };

  static String _poolLabel(AppLocalizations l10n, PoolType value) =>
      switch (value) {
        PoolType.inGroundLiner => l10n.technicalPoolInGroundLiner,
        PoolType.inGroundShell => l10n.technicalPoolInGroundShell,
        PoolType.inGroundConcrete => l10n.technicalPoolInGroundConcrete,
        PoolType.semiInGround => l10n.technicalPoolSemiInGround,
        PoolType.aboveGround => l10n.technicalPoolAboveGround,
      };
}

/// Two answers side by side. The shorter label is padded so that both
/// fields line up even when a label wraps (large text sizes).
class _PairRow extends StatelessWidget {
  const new({
    required this.labels,
    required this.first,
    required this.second,
    super.key,
  });

  /// Labels of [first] and [second], as they render them.
  final (String, String) labels;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style
        .merge(RealestyTextStyles.label);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - RealestySpacing.sm) / 2;
        double height(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: width);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final difference = height(labels.$1) - height(labels.$2);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RealestySpacing.sm,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: max(0, -difference)),
                child: first,
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: max(0, difference)),
                child: second,
              ),
            ),
          ],
        );
      },
    );
  }
}
