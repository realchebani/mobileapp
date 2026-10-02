import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// Column names of the `property_lots` table.
abstract final class PropertyLotColumns {
  static const id = 'id';
  static const ownerId = 'owner_id';
  static const name = 'name';
  static const saleMode = 'sale_mode';
  static const mainPropertyId = 'main_property_id';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// {@template property_lot}
/// A sale lot (row of `property_lots`): properties of one seller sold
/// together. Members point to their lot (`properties.lot_id`).
/// {@endtemplate}
class PropertyLot extends Equatable {
  /// {@macro property_lot}
  const new({
    required this.id,
    required this.ownerId,
    this.name,
    this.saleMode = LotSaleMode.together,
    this.mainPropertyId,
    this.createdAt,
    this.updatedAt,
  });

  /// Builds a lot from a `property_lots` row.
  factory fromJson(Map<String, dynamic> json) => PropertyLot(
    id: json[PropertyLotColumns.id] as String,
    ownerId: json[PropertyLotColumns.ownerId] as String,
    name: json[PropertyLotColumns.name] as String?,
    saleMode:
        parseDbEnum(LotSaleMode.values, json[PropertyLotColumns.saleMode]) ??
        LotSaleMode.together,
    mainPropertyId: json[PropertyLotColumns.mainPropertyId] as String?,
    createdAt: readDateTime(json[PropertyLotColumns.createdAt]),
    updatedAt: readDateTime(json[PropertyLotColumns.updatedAt]),
  );

  final String id;
  final String ownerId;

  /// Name given by the seller (1–80 characters), if any.
  final String? name;
  final LotSaleMode saleMode;

  /// The main property of the lot (a member), if chosen.
  final String? mainPropertyId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The row of this lot.
  Map<String, Object?> toJson() => {
    PropertyLotColumns.id: id,
    PropertyLotColumns.ownerId: ownerId,
    PropertyLotColumns.name: name,
    PropertyLotColumns.saleMode: saleMode.value,
    PropertyLotColumns.mainPropertyId: mainPropertyId,
    PropertyLotColumns.createdAt: encodeDbValue(createdAt),
    PropertyLotColumns.updatedAt: encodeDbValue(updatedAt),
  };

  @override
  List<Object?> get props => [
    id,
    ownerId,
    name,
    saleMode,
    mainPropertyId,
    createdAt,
    updatedAt,
  ];
}
