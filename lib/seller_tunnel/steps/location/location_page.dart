import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/location/cubit/location_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_card.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_map.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/same_address_card.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V2 · Géoloc & cadastre: address of the property (BAN autocomplete or
/// device position), its cadastral parcels on an aerial map and the
/// special situations.
class LocationPage extends StatelessWidget {
  const new({
    this.deviceLocator,
    this.tileBuilder = ParcelMap.ignOrthoTile,
    super.key,
  });

  /// Defaults to the device GPS.
  final DeviceLocator? deviceLocator;

  /// Map tiles (IGN orthophotos by default; tests inject offline tiles).
  final MapTileBuilder tileBuilder;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        return LocationCubit(
          geoRepository: context.read<GeoRepository>(),
          propertyRepository: context.read<PropertyRepository>(),
          deviceLocator: deviceLocator ?? DeviceLocator(),
          property: tunnel.property!,
          parcels: tunnel.parcels,
        );
      },
      child: LocationView(tileBuilder: tileBuilder),
    );
  }
}

class LocationView extends StatefulWidget {
  const new({this.tileBuilder = ParcelMap.ignOrthoTile, super.key});

  final MapTileBuilder tileBuilder;

  @override
  State<LocationView> createState() => _LocationViewState();
}

class _LocationViewState extends State<LocationView> {
  static const SellerTunnelStep _step = SellerTunnelStep.location;
  static const int _maxOtherLength = 300;

  late final LocationState _initial = context.read<LocationCubit>().state;
  late final TextEditingController _address = TextEditingController(
    text: _initial.addressText,
  );
  late final TextEditingController _other = TextEditingController(
    text: _initial.otherSituation,
  );

  final GlobalKey _addressKey = GlobalKey();
  final GlobalKey _mapKey = GlobalKey();
  final GlobalKey _parcelKey = GlobalKey();
  final GlobalKey _situationsKey = GlobalKey();

  @override
  void dispose() {
    _address.dispose();
    _other.dispose();
    super.dispose();
  }

  void _submitted(BuildContext context, LocationState state) {
    switch (state.submitStatus) {
      case LocationSubmitStatus.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(parcels: state.savedParcels);
        unawaited(
          tunnel.saveAndContinue(_step, state.toPatch(tunnel.state.property!)),
        );
      case LocationSubmitStatus.failure:
        showRealestySnackBar(
          context,
          context.l10n.sellerTunnelSaveError,
          isError: true,
        );
      case LocationSubmitStatus.idle:
      case LocationSubmitStatus.inProgress:
        break;
    }
  }

  /// Scrolls to the first unanswered question.
  void _revealFirstError(BuildContext context, LocationState state) {
    final key = state.addressMissing || state.addressNotPicked
        ? _addressKey
        : state.parcelsMissing
        ? _mapKey
        : state.confirmationMissing
        ? _parcelKey
        : _situationsKey;
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

  void _locateFailed(BuildContext context, LocationState state) {
    final l10n = context.l10n;
    showRealestySnackBar(context, switch (state.locateError!) {
      DeviceLocationError.serviceDisabled => l10n.locationLocateServiceDisabled,
      DeviceLocationError.permissionDenied =>
        l10n.locationLocatePermissionDenied,
      DeviceLocationError.unavailable => l10n.locationLocateUnavailable,
    }, isError: true);
  }

  String _intro(AppLocalizations l10n, LocationState state) {
    final parcels = state.parcels;
    final surface = frenchNumber(state.totalAreaM2);
    if (parcels.length == 1) {
      final parcel = parcels.single;
      return l10n.locationIntroParcel(
        parcel.section ?? '',
        parcel.shortNumero ?? '',
        surface,
      );
    }
    if (parcels.isNotEmpty) {
      return l10n.locationIntroParcels(parcels.length, surface);
    }
    return switch (state.parcelStatus) {
      ParcelLookupStatus.notFound ||
      ParcelLookupStatus.failure => l10n.locationIntroNoParcel,
      _ => l10n.locationIntroAsk,
    };
  }

  String? _badge(AppLocalizations l10n, LocationState state) {
    if (state.isLocating || state.parcelStatus == ParcelLookupStatus.loading) {
      return l10n.locationParcelSearching;
    }
    final parcels = state.parcels;
    if (parcels.length == 1) {
      return l10n.locationParcelSelected(
        parcels.single.section ?? '',
        parcels.single.shortNumero ?? '',
      );
    }
    if (parcels.isNotEmpty) return l10n.locationParcelsSelected(parcels.length);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<LocationCubit>();
    final state = context.watch<LocationCubit>().state;
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final isBusy = state.isSubmitting || tunnelSaving;
    final center = state.mapCenter;
    final locate = isBusy || state.isLocating ? null : cubit.locate;

    return MultiBlocListener(
      listeners: [
        BlocListener<LocationCubit, LocationState>(
          listenWhen: (previous, current) =>
              previous.submitStatus != current.submitStatus,
          listener: _submitted,
        ),
        BlocListener<LocationCubit, LocationState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: _revealFirstError,
        ),
        BlocListener<LocationCubit, LocationState>(
          listenWhen: (previous, current) =>
              previous.locateError != current.locateError &&
              current.locateError != null,
          listener: _locateFailed,
        ),
        BlocListener<LocationCubit, LocationState>(
          listenWhen: (previous, current) =>
              previous.addressText != current.addressText &&
              current.addressText != _address.text,
          listener: (context, state) => _address.text = state.addressText,
        ),
      ],
      child: TunnelScaffold(
        header: TunnelHeader(
          step: _step,
          onBack: () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          hint: l10n.tunnelHintVoiceOrScreen,
          label: l10n.tunnelContinue,
          isLoading: isBusy,
          onPressed: cubit.submit,
        ),
        children: [
          AgentIntro(message: _intro(l10n, state)),
          if (state.address == null)
            ?SameAddressCard.of(
              context,
              current: context.read<SellerTunnelCubit>().state.property!,
              onUse: isBusy ? null : cubit.suggestionSelected,
            ),
          RealestyTextField(
            key: _addressKey,
            label: l10n.locationAddressLabel,
            hint: l10n.locationAddressHint,
            leadingIcon: RealestyIcons.pin,
            controller: _address,
            enabled: !isBusy,
            errorText: !state.showErrors
                ? null
                : state.addressMissing
                ? l10n.locationAddressRequired
                : state.addressNotPicked
                ? l10n.locationAddressPick
                : null,
            maxLines: 2,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.search,
            autofillHints: const [AutofillHints.fullStreetAddress],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp('[\n\r]')),
              LengthLimitingTextInputFormatter(GeoRepository.maxQueryLength),
            ],
            onChanged: cubit.addressChanged,
            footer: state.suggestions.isNotEmpty
                ? _Suggestions(
                    suggestions: state.suggestions,
                    onSelected: isBusy
                        ? null
                        : (address) {
                            FocusScope.of(context).unfocus();
                            unawaited(cubit.suggestionSelected(address));
                          },
                  )
                : state.suggestionsUnavailable
                ? Text(
                    l10n.locationSuggestionsUnavailable,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  )
                : null,
          ),
          Column(
            key: _mapKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.md,
            children: [
              if (center == null)
                _MapPlaceholder(isLocating: state.isLocating, onLocate: locate)
              else
                ParcelMap(
                  center: center,
                  // Fit again on a new selection, not on each edit.
                  fitKey: state.isEditingParcels
                      ? null
                      : Object.hashAll([
                          state.point,
                          for (final parcel in state.parcels) parcel.idu,
                        ]),
                  outlines: [
                    for (final parcel in state.parcels) ...parcel.outlines,
                  ],
                  marker: state.point,
                  onTap: isBusy
                      ? null
                      : (point) => unawaited(cubit.mapTapped(point)),
                  semanticTapLabel: state.isEditingParcels
                      ? l10n.locationToggleCenterParcel
                      : l10n.locationSelectCenterParcel,
                  onLocate: locate,
                  badge: _badge(l10n, state),
                  isBusy:
                      state.isLocating ||
                      state.parcelStatus == ParcelLookupStatus.loading,
                  tileBuilder: widget.tileBuilder,
                ),
              if (state.isEditingParcels)
                InlineBanner(
                  message: l10n.locationEditHint,
                  variant: InlineBannerVariant.info,
                ),
              if (state.parcelStatus == ParcelLookupStatus.notFound)
                InlineBanner(message: l10n.locationParcelNotFound)
              else if (state.parcelStatus == ParcelLookupStatus.failure)
                InlineBanner(message: l10n.locationParcelUnavailable),
              if (state.showErrors && state.parcelsMissing)
                LocationErrorText(l10n.locationParcelRequired),
            ],
          ),
          if (state.parcels.isNotEmpty) ...[
            ParcelCard(parcels: state.parcels),
            Column(
              key: _parcelKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RealestySpacing.xs,
              children: [
                MediaQuery(
                  // Spec: these two side-by-side buttons use 15/600 text.
                  data: MediaQuery.of(context).copyWith(
                    textScaler: _CompactTextScaler(
                      MediaQuery.textScalerOf(context),
                    ),
                  ),
                  child: _ParcelActions(
                    confirmed: state.parcelConfirmed,
                    onConfirm: isBusy ? null : cubit.confirmParcels,
                    onEdit: isBusy || state.isEditingParcels
                        ? null
                        : cubit.editParcels,
                  ),
                ),
                if (state.showErrors && state.confirmationMissing)
                  LocationErrorText(l10n.locationConfirmRequired),
              ],
            ),
          ],
          Column(
            key: _situationsKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Text(
                l10n.locationSituationsQuestion,
                style: RealestyTextStyles.label.copyWith(color: c.encre2),
              ),
              Wrap(
                spacing: RealestySpacing.xs,
                runSpacing: RealestySpacing.xs,
                children: [
                  for (final situation in SpecialSituation.values)
                    RealestyChoiceChip(
                      label: _situationLabel(l10n, situation),
                      selected: state.situations.contains(situation),
                      onSelected: isBusy
                          ? null
                          : (selected) => cubit.situationToggled(
                              situation,
                              selected: selected,
                            ),
                    ),
                ],
              ),
              if (state.situations.contains(SpecialSituation.other))
                RealestyTextField(
                  label: l10n.locationSituationOtherLabel,
                  controller: _other,
                  enabled: !isBusy,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maxOtherLength),
                  ],
                  onChanged: cubit.otherSituationChanged,
                ),
              if (state.showErrors && state.situationsMissing)
                LocationErrorText(l10n.locationSituationsRequired),
            ],
          ),
        ],
      ),
    );
  }

  static String _situationLabel(
    AppLocalizations l10n,
    SpecialSituation situation,
  ) => switch (situation) {
    SpecialSituation.rightOfWay => l10n.locationSituationRightOfWay,
    SpecialSituation.networkEasement => l10n.locationSituationNetworks,
    SpecialSituation.other => l10n.locationSituationOther,
    SpecialSituation.none => l10n.locationSituationNone,
  };
}

/// "Oui, c’est correct" / "Modifier / ajouter": side by side when both
/// labels fit with their icons, else stacked.
class _ParcelActions extends StatelessWidget {
  const new({
    required this.confirmed,
    required this.onConfirm,
    required this.onEdit,
  });

  final bool confirmed;
  final VoidCallback? onConfirm;
  final VoidCallback? onEdit;

  static const double _gap = 10;
  static const double _height = 48;

  /// Width of a [RealestyButton] showing [label] after a 20 px icon.
  static double _width(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: RealestyTextStyles.button),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return 2 * (RealestySpacing.md + RealestyBorders.medium) +
        20 +
        RealestySpacing.xs +
        width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final confirm = RealestyButton(
      label: confirmed ? l10n.locationConfirmed : l10n.locationConfirm,
      leadingIcon: RealestyIcons.check,
      variant: confirmed
          ? RealestyButtonVariant.accent
          : RealestyButtonVariant.primary,
      height: _height,
      onPressed: onConfirm,
    );
    final edit = RealestyButton(
      label: l10n.locationEdit,
      leadingIcon: RealestyIcons.plus,
      variant: RealestyButtonVariant.secondary,
      height: _height,
      onPressed: onEdit,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2;
        final fits =
            _width(context, l10n.locationConfirm) <= half &&
            _width(context, l10n.locationConfirmed) <= half &&
            _width(context, l10n.locationEdit) <= half;
        return fits
            ? Row(
                spacing: _gap,
                children: [
                  Expanded(child: confirm),
                  Expanded(child: edit),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: RealestySpacing.xs,
                children: [confirm, edit],
              );
      },
    );
  }
}

/// Scales text by 15/16 on top of [parent] (16 px button text → 15 px).
class _CompactTextScaler extends TextScaler {
  const new(this.parent);

  final TextScaler parent;

  @override
  double scale(double fontSize) => parent.scale(fontSize) * 15 / 16;

  @override
  double get textScaleFactor => parent.scale(16) / 16 * 15 / 16;

  @override
  bool operator ==(Object other) =>
      other is _CompactTextScaler && other.parent == parent;

  @override
  int get hashCode => parent.hashCode;
}

/// BAN suggestions under the address field (not designed: DS list items in
/// a card).
class _Suggestions extends StatelessWidget {
  const new({required this.suggestions, required this.onSelected});

  final List<GeoAddress> suggestions;
  final ValueChanged<GeoAddress>? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.field),
        border: Border.all(color: c.bordureCarte),
        boxShadow: RealestyShadows.level1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, address) in suggestions.indexed)
            RealestyListItem(
              title: address.name ?? address.label,
              subtitle: [address.postcode, address.city].nonNulls.join(' '),
              leadingIcon: RealestyIcons.pin,
              showDivider: index < suggestions.length - 1,
              onTap: onSelected == null ? null : () => onSelected!(address),
            ),
        ],
      ),
    );
  }
}

/// Stands for the map until a position is known.
class _MapPlaceholder extends StatelessWidget {
  const new({required this.isLocating, required this.onLocate});

  final bool isLocating;
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      height: ParcelMap.height,
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: RealestySpacing.sm,
        children: [
          RealestyIcon(RealestyIcons.map, size: 28, color: c.texteDiscret),
          Text(
            l10n.locationMapEmpty,
            textAlign: TextAlign.center,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
          RealestyButton(
            label: l10n.locationLocateMe,
            leadingIcon: RealestyIcons.target,
            variant: RealestyButtonVariant.secondary,
            height: 44,
            expand: false,
            isLoading: isLocating,
            loadingSemanticLabel: l10n.tunnelLoading,
            onPressed: onLocate,
          ),
        ],
      ),
    );
  }
}
