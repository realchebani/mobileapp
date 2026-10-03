import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// What can be put on sale (EPIC-08, owner decisions of 2026-10-03): a
/// certified property on its own, or a sale lot (as soon as its main
/// property is certified).
final class SaleTarget extends Equatable {
  const new _({required this.members, this.property, this.lotId});

  /// The property [property] on its own.
  factory forProperty(Property property) =>
      SaleTarget._(property: property, members: [property]);

  /// The lot [lot] of [members] (its main property first).
  factory forLot(PropertyLot lot, List<Property> members) =>
      SaleTarget._(lotId: lot.id, members: members);

  /// The target of the existing [sale] of [members].
  factory forSale(Sale sale, List<Property> members) => sale.isLot
      ? SaleTarget._(lotId: sale.lotId, members: members)
      : SaleTarget._(property: members.first, members: members);

  /// The property sold on its own, if any.
  final Property? property;

  /// The lot sold, if any.
  final String? lotId;

  /// The properties sold (one, or the lot's members).
  final List<Property> members;

  bool get isLot => lotId != null;

  String? get propertyId => property?.id;

  /// The certified members (whose certified values make the lot's value).
  List<Property> get certifiedMembers => [
    for (final member in members)
      if (member.status == PropertyStatus.certified) member,
  ];

  @override
  List<Object?> get props => [property, lotId, members];
}

/// Where a property stands regarding its sale: its active sale (on its own
/// or through its lot), and the new sales it could start.
final class SaleEntry extends Equatable {
  const new({this.activeSale, this.targets = const [], this.lot});

  /// The entry of [property], given the seller's [properties], [lots] and
  /// active [sales].
  factory of({
    required Property property,
    required List<Property> properties,
    required List<PropertyLot> lots,
    required List<Sale> sales,
  }) {
    final lot = lots.where((l) => l.id == property.lotId).firstOrNull;
    final active =
        sales.where((s) => s.propertyId == property.id).firstOrNull ??
        (lot == null
            ? null
            : sales.where((s) => s.lotId == lot.id).firstOrNull);
    if (active != null) return SaleEntry(activeSale: active, lot: lot);
    final targets = <SaleTarget>[
      if (property.status == PropertyStatus.certified &&
          (lot == null || lot.saleMode == LotSaleMode.togetherOrSeparately))
        SaleTarget.forProperty(property),
      if (lot != null) ?lotTarget(lot, properties: properties, sales: sales),
    ];
    return SaleEntry(targets: targets, lot: lot);
  }

  /// The lot [lot] as a sale target, or null while its main property is
  /// not certified or one of its members is on sale on its own.
  static SaleTarget? lotTarget(
    PropertyLot lot, {
    required List<Property> properties,
    required List<Sale> sales,
  }) {
    final members = lotMembers(lot, properties);
    if (members.isEmpty || members.first.status != PropertyStatus.certified) {
      return null;
    }
    final ids = {for (final member in members) member.id};
    if (sales.any((s) => ids.contains(s.propertyId) || s.lotId == lot.id)) {
      return null;
    }
    return SaleTarget.forLot(lot, members);
  }

  /// The members of [lot], its main property first (its main_property_id,
  /// else the oldest member — same rule as the database).
  static List<Property> lotMembers(PropertyLot lot, List<Property> properties) {
    final members =
        [
          for (final property in properties)
            if (property.lotId == lot.id) property,
        ]..sort((a, b) {
          // Same order as the database: oldest first, then by id.
          final byDate = _created(a).compareTo(_created(b));
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
    final main =
        members.where((p) => p.id == lot.mainPropertyId).firstOrNull ??
        members.firstOrNull;
    return [
      ?main,
      for (final member in members)
        if (member != main) member,
    ];
  }

  static DateTime _created(Property property) =>
      property.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// The sale the property is part of, if any.
  final Sale? activeSale;

  /// The sales that can be started (empty while nothing can be sold).
  final List<SaleTarget> targets;

  /// The lot of the property, if any.
  final PropertyLot? lot;

  @override
  List<Object?> get props => [activeSale, targets, lot];
}
