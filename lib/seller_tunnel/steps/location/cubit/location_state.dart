part of 'location_cubit.dart';

/// Progress of a cadastre lookup.
enum ParcelLookupStatus {
  idle,
  loading,
  success,

  /// No parcel at the point (e.g. a road).
  notFound,

  /// The cadastre API could not be reached.
  failure,
}

/// Progress of saving the parcels on "Continuer".
enum LocationSubmitStatus { idle, inProgress, success, failure }

/// V2 answers being edited: address, located point, selected parcels and
/// special situations.
final class LocationState extends Equatable {
  const new({
    this.addressText = '',
    this.address,
    this.point,
    this.suggestions = const [],
    this.suggestionsUnavailable = false,
    this.parcelStatus = ParcelLookupStatus.idle,
    this.parcels = const [],
    this.parcelConfirmed = false,
    this.isEditingParcels = false,
    this.isLocating = false,
    this.locateError,
    this.situations = const [],
    this.otherSituation = '',
    this.showErrors = false,
    this.submitAttempts = 0,
    this.submitStatus = LocationSubmitStatus.idle,
    this.savedParcels = const [],
  });

  /// The answers already saved in the dossier.
  factory fromDossier(Property property, List<PropertyParcel> parcels) {
    final lat = property.lat;
    final lng = property.lng;
    final point = lat == null || lng == null ? null : GeoPoint(lat, lng);
    final banId = property.addressBanId;
    final label = property.addressLabel ?? '';
    return LocationState(
      addressText: label,
      address: banId == null || point == null
          ? null
          : GeoAddress(
              id: banId,
              label: label,
              point: point,
              housenumber: property.addressHousenumber,
              street: property.addressStreet,
              postcode: property.addressPostcode,
              city: property.addressCity,
              citycode: property.addressCitycode,
            ),
      point: point,
      parcelStatus: parcels.isEmpty
          ? ParcelLookupStatus.idle
          : ParcelLookupStatus.success,
      parcels: [
        for (final parcel in parcels)
          CadastreParcel(
            idu: parcel.idu,
            section: parcel.section,
            numero: parcel.numero,
            codeInsee: parcel.codeInsee,
            areaM2: parcel.areaM2,
            geometry: parcel.geometry,
          ),
      ],
      parcelConfirmed: property.parcelConfirmed && parcels.isNotEmpty,
      situations: property.specialSituations,
      otherSituation: property.specialSituationOther ?? '',
      savedParcels: parcels,
    );
  }

  /// Text of the address field.
  final String addressText;

  /// The BAN address picked (null when typed by hand).
  final GeoAddress? address;

  /// Located point (address, device position or saved position).
  final GeoPoint? point;

  /// Address suggestions under the field.
  final List<GeoAddress> suggestions;

  /// Whether the last address search failed (e.g. offline).
  final bool suggestionsUnavailable;

  final ParcelLookupStatus parcelStatus;

  /// Selected cadastral parcels.
  final List<CadastreParcel> parcels;

  /// "Oui, c’est correct".
  final bool parcelConfirmed;

  /// "Modifier / ajouter": taps on the map add or remove parcels.
  final bool isEditingParcels;

  /// "Me géolocaliser" in progress.
  final bool isLocating;

  /// Why the last "Me géolocaliser" failed (reset on the next attempt).
  final DeviceLocationError? locateError;

  final List<SpecialSituation> situations;

  /// Free text when [SpecialSituation.other] is selected.
  final String otherSituation;

  /// Whether to show the validation errors (after "Continuer").
  final bool showErrors;

  /// Incremented by each "Continuer" refused by validation (the view then
  /// scrolls to the first error).
  final int submitAttempts;

  final LocationSubmitStatus submitStatus;

  /// Parcel rows of the dossier (up to date after a successful submit).
  final List<PropertyParcel> savedParcels;

  /// Center of the map: the located point, or the first parcel.
  GeoPoint? get mapCenter {
    if (point != null) return point;
    for (final parcel in parcels) {
      final ring = parcel.outlines.firstOrNull;
      if (ring != null && ring.isNotEmpty) {
        final lat = ring.fold<double>(0, (sum, p) => sum + p.lat);
        final lng = ring.fold<double>(0, (sum, p) => sum + p.lng);
        return GeoPoint(lat / ring.length, lng / ring.length);
      }
    }
    return null;
  }

  /// Total registered area of the selected parcels (m²).
  int get totalAreaM2 =>
      parcels.fold(0, (total, parcel) => total + (parcel.areaM2 ?? 0));

  bool get addressMissing => addressText.trim().isEmpty;

  /// Whether the address services cannot be reached (then a typed
  /// address and no parcel are accepted).
  bool get servicesUnavailable =>
      suggestionsUnavailable || parcelStatus == ParcelLookupStatus.failure;

  /// A typed address that was neither picked among the suggestions nor
  /// located, while the services are reachable.
  bool get addressNotPicked =>
      !addressMissing &&
      address == null &&
      point == null &&
      !servicesUnavailable;

  /// Every parcel was removed while the cadastre answers.
  bool get parcelsMissing =>
      parcels.isEmpty && parcelStatus == ParcelLookupStatus.success;

  bool get confirmationMissing => parcels.isNotEmpty && !parcelConfirmed;

  bool get situationsMissing => situations.isEmpty;

  bool get isSubmitting => submitStatus == LocationSubmitStatus.inProgress;

  bool get isValid =>
      !addressMissing &&
      !addressNotPicked &&
      !parcelsMissing &&
      !confirmationMissing &&
      !situationsMissing;

  /// The `properties` columns of the step, [property] being the dossier
  /// (for its provenance map).
  ///
  /// A BAN address and its position are `external` data, a typed address
  /// is `declared`.
  Map<String, Object?> toPatch(Property property) {
    final other = otherSituation.trim();
    final source = address == null ? Provenance.declared : Provenance.external;
    return {
      PropertyColumns.addressLabel: addressText.trim(),
      PropertyColumns.addressHousenumber: address?.housenumber,
      PropertyColumns.addressStreet: address?.street,
      PropertyColumns.addressPostcode: address?.postcode,
      PropertyColumns.addressCity: address?.city,
      PropertyColumns.addressCitycode: address?.citycode,
      PropertyColumns.addressBanId: address?.id,
      PropertyColumns.lat: point?.lat,
      PropertyColumns.lng: point?.lng,
      PropertyColumns.parcelConfirmed: parcels.isNotEmpty && parcelConfirmed,
      PropertyColumns.specialSituations: situations,
      PropertyColumns.specialSituationOther:
          situations.contains(SpecialSituation.other) && other.isNotEmpty
          ? other
          : null,
      PropertyColumns.provenance: property.mergeProvenance({
        for (final column in _addressColumns) column: source,
      }),
    };
  }

  static const List<String> _addressColumns = [
    PropertyColumns.addressLabel,
    PropertyColumns.addressHousenumber,
    PropertyColumns.addressStreet,
    PropertyColumns.addressPostcode,
    PropertyColumns.addressCity,
    PropertyColumns.addressCitycode,
    PropertyColumns.addressBanId,
    PropertyColumns.lat,
    PropertyColumns.lng,
  ];

  LocationState copyWith({
    String? addressText,
    GeoAddress? Function()? address,
    GeoPoint? Function()? point,
    List<GeoAddress>? suggestions,
    bool? suggestionsUnavailable,
    ParcelLookupStatus? parcelStatus,
    List<CadastreParcel>? parcels,
    bool? parcelConfirmed,
    bool? isEditingParcels,
    bool? isLocating,
    DeviceLocationError? Function()? locateError,
    List<SpecialSituation>? situations,
    String? otherSituation,
    bool? showErrors,
    int? submitAttempts,
    LocationSubmitStatus? submitStatus,
    List<PropertyParcel>? savedParcels,
  }) {
    return LocationState(
      addressText: addressText ?? this.addressText,
      address: address != null ? address() : this.address,
      point: point != null ? point() : this.point,
      suggestions: suggestions ?? this.suggestions,
      suggestionsUnavailable:
          suggestionsUnavailable ?? this.suggestionsUnavailable,
      parcelStatus: parcelStatus ?? this.parcelStatus,
      parcels: parcels ?? this.parcels,
      parcelConfirmed: parcelConfirmed ?? this.parcelConfirmed,
      isEditingParcels: isEditingParcels ?? this.isEditingParcels,
      isLocating: isLocating ?? this.isLocating,
      locateError: locateError != null ? locateError() : this.locateError,
      situations: situations ?? this.situations,
      otherSituation: otherSituation ?? this.otherSituation,
      showErrors: showErrors ?? this.showErrors,
      submitAttempts: submitAttempts ?? this.submitAttempts,
      submitStatus: submitStatus ?? this.submitStatus,
      savedParcels: savedParcels ?? this.savedParcels,
    );
  }

  @override
  List<Object?> get props => [
    addressText,
    address,
    point,
    suggestions,
    suggestionsUnavailable,
    parcelStatus,
    parcels,
    parcelConfirmed,
    isEditingParcels,
    isLocating,
    locateError,
    situations,
    otherSituation,
    showErrors,
    submitAttempts,
    submitStatus,
    savedParcels,
  ];
}
