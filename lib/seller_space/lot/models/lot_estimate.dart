import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:property_repository/property_repository.dart';

/// How a property counts in the estimate of its lot.
enum LotMemberEstimate {
  /// Its non-certified estimate is added.
  included,

  /// Its type has no automatic estimate: the expert values it.
  byExpert,

  /// A garage or an outbuilding on a parcel of the main dwelling: the
  /// estimate of the dwelling already includes it (DVF sales of houses
  /// include their outbuildings), so it is not added twice.
  includedInMain,

  /// A sent dossier without automatic estimate (too few comparable sales,
  /// or still computing): the expert values it.
  notEstimated,

  /// Its dossier is not sent yet: no estimate before it is.
  waiting,
}

/// Estimate of a sale lot (EPIC-13, owner decision Q4): the sum of the
/// non-certified estimates of its properties, once every property is sent.
/// A sum that leaves out properties valued by the expert is only ever shown
/// as a partial sum ([isPartial], plan §12). Computed in the app: no new
/// server computation, no quota used.
final class LotEstimate extends Equatable {
  const new _({required this.members, this.low, this.median, this.high});

  /// The estimate of the lot of [members], whose main property is
  /// [mainPropertyId] (by default its first dwelling), given the cadastre
  /// identifiers of the parcels of each property ([parcels]).
  factory of({
    required List<Property> members,
    required Map<String, Set<String>> parcels,
    String? mainPropertyId,
  }) {
    final main =
        members.where((p) => p.id == mainPropertyId).firstOrNull ??
        members.where((p) => _dwellings.contains(p.propertyType)).firstOrNull;
    final states = <String, LotMemberEstimate>{};
    var low = 0;
    var median = 0;
    var high = 0;
    for (final member in members) {
      final LotMemberEstimate state;
      if (!PropertyTypeProfile.of(member.propertyType).estimate) {
        state = LotMemberEstimate.byExpert;
      } else if (_onMainParcel(member, main, parcels)) {
        state = LotMemberEstimate.includedInMain;
      } else if (member.aiEstimateLowEur != null &&
          member.aiEstimateMedianEur != null &&
          member.aiEstimateHighEur != null) {
        state = LotMemberEstimate.included;
        low += member.aiEstimateLowEur!;
        median += member.aiEstimateMedianEur!;
        high += member.aiEstimateHighEur!;
      } else if (member.status == PropertyStatus.draft) {
        state = LotMemberEstimate.waiting;
      } else {
        state = LotMemberEstimate.notEstimated;
      }
      states[member.id] = state;
    }
    final complete =
        states.values.contains(LotMemberEstimate.included) &&
        !states.values.contains(LotMemberEstimate.waiting);
    return LotEstimate._(
      members: states,
      low: complete ? low : null,
      median: complete ? median : null,
      high: complete ? high : null,
    );
  }

  static const Set<PropertyType> _dwellings = {
    PropertyType.house,
    PropertyType.apartment,
  };

  static bool _onMainParcel(
    Property member,
    Property? main,
    Map<String, Set<String>> parcels,
  ) {
    if (main == null || member.id == main.id) return false;
    if (!_dwellings.contains(main.propertyType)) return false;
    if (member.propertyType != PropertyType.parking &&
        member.propertyType != PropertyType.outbuilding) {
      return false;
    }
    final own = parcels[member.id] ?? const {};
    return own.intersection(parcels[main.id] ?? const {}).isNotEmpty;
  }

  /// How each property (by id) counts.
  final Map<String, LotMemberEstimate> members;

  /// Sum of the ranges, when every estimable property has its estimate.
  final int? low;
  final int? median;
  final int? high;

  /// Whether a sum can be shown (complete or partial).
  bool get isComplete => median != null;

  /// Whether the sum leaves out properties valued by the expert: it must
  /// then be shown as a partial sum, never as the value of the lot.
  bool get isPartial =>
      isComplete &&
      members.values.any(
        (state) =>
            state == LotMemberEstimate.byExpert ||
            state == LotMemberEstimate.notEstimated,
      );

  /// The properties (ids) left out of the sum and valued by the expert.
  List<String> get leftOut => [
    for (final MapEntry(:key, :value) in members.entries)
      if (value == LotMemberEstimate.byExpert ||
          value == LotMemberEstimate.notEstimated)
        key,
  ];

  @override
  List<Object?> get props => [members, low, median, high];
}
