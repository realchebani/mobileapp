import 'package:equatable/equatable.dart';
import 'package:property_repository/src/models/enums.dart';
import 'package:property_repository/src/models/json.dart';

/// EPIC-15 · how a room photo was taken (`room_photos.source`).
enum PhotoSource implements DbEnum {
  camera('camera'),
  library('library');

  new(this.value);

  @override
  final String value;
}

/// EPIC-15 · a defect of a photo, found on the device or by the vision AI.
enum PhotoQualityIssue implements DbEnum {
  dark('dark'),
  overexposed('overexposed'),
  blurry('blurry'),
  tilted('tilted'),
  cluttered('cluttered');

  new(this.value);

  @override
  final String value;
}

List<PhotoQualityIssue> _issues(Object? value) => [
  if (value is List)
    for (final item in value) ?parseDbEnum(PhotoQualityIssue.values, item),
];

List<String> _texts(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is String) item,
];

/// {@template photo_quality}
/// The checks made on the device before a photo is sent
/// (`room_photos.quality`).
/// {@endtemplate}
class PhotoQuality extends Equatable {
  /// {@macro photo_quality}
  const new({
    this.brightness,
    this.sharpness,
    this.tiltDegrees,
    this.issues = const [],
  });

  /// Builds the checks from their JSON.
  factory fromJson(Map<String, dynamic> json) => PhotoQuality(
    brightness: readDouble(json['brightness']),
    sharpness: readDouble(json['sharpness']),
    tiltDegrees: readDouble(json['tilt_deg']),
    issues: _issues(json['issues']),
  );

  /// Mean luminance, 0–255.
  final double? brightness;

  /// Variance of the Laplacian of the reduced grey image.
  final double? sharpness;

  /// Tilt of the phone when the photo was taken (camera only), degrees.
  final double? tiltDegrees;

  /// The defects found.
  final List<PhotoQualityIssue> issues;

  Map<String, Object?> toJson() => {
    'brightness': brightness,
    'sharpness': sharpness,
    'tilt_deg': tiltDegrees,
    'issues': [for (final issue in issues) issue.value],
  };

  @override
  List<Object?> get props => [brightness, sharpness, tiltDegrees, issues];
}

/// {@template room_photo_analysis}
/// What the vision AI proposes for a room photo (`room_photos.analysis`,
/// written by the Edge Function `vision-room`). Suggestions only: the
/// seller accepts them or not; never a surface or a measurement.
/// {@endtemplate}
class RoomPhotoAnalysis extends Equatable {
  /// {@macro room_photo_analysis}
  const new({
    this.roomKind,
    this.floorCovering,
    this.glazing,
    this.conditionNotes = const [],
    this.personalItems = const [],
    this.peopleVisible = false,
    this.qualityIssues = const [],
    this.model,
  });

  /// Builds the analysis from its JSON.
  factory fromJson(Map<String, dynamic> json) => RoomPhotoAnalysis(
    roomKind: json['room_kind'] as String?,
    floorCovering: json['floor_covering'] as String?,
    glazing: parseDbEnum(Glazing.values, json['glazing']),
    conditionNotes: _texts(json['condition_notes']),
    personalItems: _texts(json['personal_items']),
    peopleVisible: json['people_visible'] as bool? ?? false,
    qualityIssues: _issues(json['quality_issues']),
    model: json['model'] as String?,
  );

  /// The V5c room suggestion (its name, e.g. `kitchen`).
  final String? roomKind;

  /// A stored floor covering (e.g. `carrelage`).
  final String? floorCovering;
  final Glazing? glazing;

  /// Visible condition, without figures (e.g. "Fissure au plafond").
  final List<String> conditionNotes;

  /// Personal items to put away before the listing photos.
  final List<String> personalItems;

  /// A person is visible: the photo should be taken again or deleted.
  final bool peopleVisible;
  final List<PhotoQualityIssue> qualityIssues;
  final String? model;

  @override
  List<Object?> get props => [
    roomKind,
    floorCovering,
    glazing,
    conditionNotes,
    personalItems,
    peopleVisible,
    qualityIssues,
    model,
  ];
}

/// {@template room_photo}
/// EPIC-15 · a photo of a room (`room_photos`), stored in the
/// `property-documents` bucket under
/// `<owner id>/<property id>/photos/<room id>/<photo id>.jpg`.
/// {@endtemplate}
class RoomPhoto extends Equatable {
  /// {@macro room_photo}
  const new({
    required this.id,
    required this.propertyId,
    required this.roomId,
    required this.storagePath,
    this.width,
    this.height,
    this.sizeBytes,
    this.sortOrder = 0,
    this.source = PhotoSource.camera,
    this.quality,
    this.analysis,
    this.takenAt,
  });

  /// Builds a photo from a `room_photos` row.
  factory fromJson(Map<String, dynamic> json) {
    final quality = json['quality'];
    final analysis = json['analysis'];
    return RoomPhoto(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      roomId: json['room_id'] as String,
      storagePath: json['storage_path'] as String,
      width: readInt(json['width']),
      height: readInt(json['height']),
      sizeBytes: readInt(json['size_bytes']),
      sortOrder: readInt(json['sort_order']) ?? 0,
      source:
          parseDbEnum(PhotoSource.values, json['source']) ?? PhotoSource.camera,
      quality: quality is Map<String, dynamic>
          ? PhotoQuality.fromJson(quality)
          : null,
      analysis: analysis is Map<String, dynamic>
          ? RoomPhotoAnalysis.fromJson(analysis)
          : null,
      takenAt: readDateTime(json['taken_at']),
    );
  }

  final String id;
  final String propertyId;
  final String roomId;
  final String storagePath;
  final int? width;
  final int? height;
  final int? sizeBytes;

  /// Order in the room (the first photo is the main one).
  final int sortOrder;
  final PhotoSource source;
  final PhotoQuality? quality;

  /// The vision AI suggestions, once analysed.
  final RoomPhotoAnalysis? analysis;
  final DateTime? takenAt;

  /// The photo with [analysis].
  RoomPhoto withAnalysis(RoomPhotoAnalysis analysis) =>
      _copy(analysis: analysis);

  /// The photo at [sortOrder].
  RoomPhoto withSortOrder(int sortOrder) => _copy(sortOrder: sortOrder);

  RoomPhoto _copy({RoomPhotoAnalysis? analysis, int? sortOrder}) => RoomPhoto(
    id: id,
    propertyId: propertyId,
    roomId: roomId,
    storagePath: storagePath,
    width: width,
    height: height,
    sizeBytes: sizeBytes,
    sortOrder: sortOrder ?? this.sortOrder,
    source: source,
    quality: quality,
    analysis: analysis ?? this.analysis,
    takenAt: takenAt,
  );

  /// The columns the app may insert (not the analysis).
  Map<String, Object?> toInsertJson() => {
    'id': id,
    'property_id': propertyId,
    'room_id': roomId,
    'storage_path': storagePath,
    'width': width,
    'height': height,
    'size_bytes': sizeBytes,
    'sort_order': sortOrder,
    'source': source.value,
    'quality': quality?.toJson(),
    'taken_at': encodeDbValue(takenAt),
  };

  @override
  List<Object?> get props => [
    id,
    propertyId,
    roomId,
    storagePath,
    width,
    height,
    sizeBytes,
    sortOrder,
    source,
    quality,
    analysis,
    takenAt,
  ];
}

/// {@template plan_room}
/// A room read on a floor plan by the Edge Function `plan-reader`: only
/// what is printed (an area missing from the plan is null).
/// {@endtemplate}
class PlanRoom extends Equatable {
  /// {@macro plan_room}
  const new({required this.name, this.areaM2, this.level, this.kind});

  /// Builds a room from its JSON.
  factory fromJson(Map<String, dynamic> json) => PlanRoom(
    name: json['name'] as String,
    areaM2: readDouble(json['area_m2']),
    level: parseDbEnum(RoomLevel.values, json['level']),
    kind: json['kind'] as String?,
  );

  final String name;
  final double? areaM2;
  final RoomLevel? level;

  /// The V5c room suggestion (its name, e.g. `bedroom`).
  final String? kind;

  @override
  List<Object?> get props => [name, areaM2, level, kind];
}

/// {@template plan_reading}
/// The reading of a photographed floor plan (`plan-reader`).
/// {@endtemplate}
class PlanReading extends Equatable {
  /// {@macro plan_reading}
  const new({
    required this.isFloorPlan,
    this.rooms = const [],
    this.printedTotalM2,
    this.roomsTotalM2 = 0,
    this.totalMatches,
  });

  /// Builds the reading from its JSON.
  factory fromJson(Map<String, dynamic> json) => PlanReading(
    isFloorPlan: json['is_floor_plan'] as bool? ?? false,
    rooms: [
      if (json['rooms'] case final List<dynamic> rooms)
        for (final room in rooms)
          if (room is Map<String, dynamic>) PlanRoom.fromJson(room),
    ],
    printedTotalM2: readDouble(json['printed_total_m2']),
    roomsTotalM2: readDouble(json['rooms_total_m2']) ?? 0,
    totalMatches: json['total_matches'] as bool?,
  );

  /// False when the image is not a floor plan.
  final bool isFloorPlan;
  final List<PlanRoom> rooms;

  /// The total printed on the plan, if any.
  final double? printedTotalM2;

  /// The sum of the areas read.
  final double roomsTotalM2;

  /// Whether the sum matches the printed total (±5 %); null without total.
  final bool? totalMatches;

  @override
  List<Object?> get props => [
    isFloorPlan,
    rooms,
    printedTotalM2,
    roomsTotalM2,
    totalMatches,
  ];
}
