import 'package:equatable/equatable.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

/// What the vision AI proposes for a room, from the analyses of its photos
/// (the most frequent answer of each field), compared with the answers of
/// the room: only what would change something is proposed. Proposals only:
/// nothing is applied without the seller.
final class RoomPhotoSuggestions extends Equatable {
  const new({
    this.kind,
    this.floorCovering,
    this.glazing,
    this.conditionNotes = const [],
    this.personalItems = const [],
    this.peoplePhotoIds = const [],
    this.analyzedCount = 0,
  });

  /// The suggestions for [room] from the analyses of [photos];
  /// [currentKind] is the kind of room its name shows, if any.
  factory of({
    required RoomInput room,
    required List<RoomPhoto> photos,
    RoomSuggestion? currentKind,
  }) {
    final analyses = [for (final photo in photos) ?photo.analysis];
    final kind = RoomSuggestion.byKind(
      _mostFrequent([for (final a in analyses) a.roomKind]),
    );
    final covering = FloorCovering.parse(
      _mostFrequent([for (final a in analyses) a.floorCovering]),
    );
    final glazing = _mostFrequent([for (final a in analyses) a.glazing]);
    final description = (room.description ?? '').toLowerCase();
    return RoomPhotoSuggestions(
      kind: kind == null || kind == currentKind || kind == RoomSuggestion.other
          ? null
          : kind,
      floorCovering: covering == null || covering.value == room.floorCovering
          ? null
          : covering,
      glazing: glazing == room.glazing ? null : glazing,
      conditionNotes: _distinct([
        for (final a in analyses)
          for (final note in a.conditionNotes)
            if (!description.contains(note.toLowerCase())) note,
      ]),
      personalItems: _distinct([for (final a in analyses) ...a.personalItems]),
      peoplePhotoIds: [
        for (final photo in photos)
          if (photo.analysis?.peopleVisible ?? false) photo.id,
      ],
      analyzedCount: analyses.length,
    );
  }

  /// The kind of room [name] shows ("Chambre 2" → bedroom), if any.
  static RoomSuggestion? kindOfName(String name, AppLocalizations l10n) {
    final lower = name.trim().toLowerCase();
    for (final suggestion in RoomSuggestion.values) {
      if (suggestion == RoomSuggestion.other) continue;
      if (lower.startsWith(suggestion.label(l10n).toLowerCase())) {
        return suggestion;
      }
    }
    return null;
  }

  /// The most frequent non-null value (the first one on a tie).
  static T? _mostFrequent<T>(List<T?> values) {
    final counts = <T, int>{};
    for (final value in values) {
      if (value != null) counts[value] = (counts[value] ?? 0) + 1;
    }
    T? best;
    var bestCount = 0;
    for (final MapEntry(:key, :value) in counts.entries) {
      if (value > bestCount) {
        best = key;
        bestCount = value;
      }
    }
    return best;
  }

  static List<String> _distinct(List<String> texts) {
    final seen = <String>{};
    return [
      for (final text in texts)
        if (seen.add(text.toLowerCase())) text,
    ];
  }

  /// Another kind of room than its name shows.
  final RoomSuggestion? kind;

  /// Another floor covering than the room's.
  final FloorCovering? floorCovering;

  /// Another glazing than the room's.
  final Glazing? glazing;

  /// Notes about the condition not in the description yet.
  final List<String> conditionNotes;

  /// Personal items to put away before the listing photos.
  final List<String> personalItems;

  /// Photos where a person is visible.
  final List<String> peoplePhotoIds;

  /// Photos analysed so far.
  final int analyzedCount;

  /// Whether a value can be applied to the room.
  bool get hasProposals =>
      kind != null ||
      floorCovering != null ||
      glazing != null ||
      conditionNotes.isNotEmpty;

  @override
  List<Object?> get props => [
    kind,
    floorCovering,
    glazing,
    conditionNotes,
    personalItems,
    peoplePhotoIds,
    analyzedCount,
  ];
}

/// The changes of the room accepted from the suggestions.
extension RoomSuggestionChanges on RoomInput {
  /// The room as [kind] (name numbered among [otherNames], main / annex).
  RoomInput withKind(
    RoomSuggestion kind,
    AppLocalizations l10n,
    List<String> otherNames,
  ) {
    final label = kind.label(l10n);
    return _copy(
      name: kind.isNumbered
          ? RoomSuggestion.numbered(label, otherNames)
          : label,
      isMain: kind.isMain,
      isAnnex: kind.isAnnex,
    );
  }

  RoomInput withFloorCovering(FloorCovering covering) =>
      _copy(floorCovering: covering.value);

  RoomInput withGlazing(Glazing glazing) => _copy(glazing: glazing);

  /// The room with [note] added to its description (cut to the maximum
  /// length).
  RoomInput withNote(String note) {
    final current = description?.trim() ?? '';
    final text = current.isEmpty
        ? note
        : '$current${RegExp(r'[.!?]$').hasMatch(current) ? '' : '.'} $note';
    return _copy(
      description: text.length > Room.descriptionMaxLength
          ? text.substring(0, Room.descriptionMaxLength)
          : text,
    );
  }

  RoomInput _copy({
    String? name,
    String? floorCovering,
    Glazing? glazing,
    bool? isMain,
    bool? isAnnex,
    String? description,
  }) => RoomInput(
    name: name ?? this.name,
    level: level,
    areaM2: areaM2,
    floorCovering: floorCovering ?? this.floorCovering,
    glazing: glazing ?? this.glazing,
    isMain: isMain ?? this.isMain,
    isAnnex: isAnnex ?? this.isAnnex,
    description: description ?? this.description,
  );
}
