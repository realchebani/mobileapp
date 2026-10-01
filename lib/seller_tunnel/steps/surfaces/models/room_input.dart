import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

/// What the room form edits: the answers of one row of the V5c table.
final class RoomInput extends Equatable {
  const new({
    required this.name,
    required this.level,
    required this.areaM2,
    this.floorCovering,
    this.glazing,
    this.isMain = false,
  });

  /// The answers of [room].
  factory fromRoom(Room room) => RoomInput(
    name: room.name,
    level: room.level,
    areaM2: room.areaM2,
    floorCovering: room.floorCovering,
    glazing: room.glazing,
    isMain: room.isMain,
  );

  final String name;
  final RoomLevel? level;
  final double areaM2;

  /// Stored value of a `FloorCovering` (or any text of a scanned room).
  final String? floorCovering;
  final Glazing? glazing;
  final bool isMain;

  @override
  List<Object?> get props => [
    name,
    level,
    areaM2,
    floorCovering,
    glazing,
    isMain,
  ];
}
