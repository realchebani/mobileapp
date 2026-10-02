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

  /// Its estimate is not computed yet (dossier not sent, or computing).
  waiting,
}

/// Estimate of a sale lot (EPIC-13, owner decision Q4): the sum of the
/// non-certified estimates of its properties, only once every property
/// that can be estimated has one. Computed in the app: no new server
/// computation, no quota used.
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
      } else {
        state = LotMemberEstimate.waiting;
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

  /// Whether the sum can be shown.
  bool get isComplete => median != null;

  @override
  List<Object?> get props => [members, low, median, high];
}
