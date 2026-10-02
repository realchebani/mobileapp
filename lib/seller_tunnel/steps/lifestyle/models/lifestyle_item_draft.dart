import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:property_repository/property_repository.dart';

/// Shortest asset or watch point label (spec V6: 3..140 characters).
const lifestyleItemMinLength = 3;

/// Longest asset or watch point label (`lifestyle_items.label` check).
const lifestyleItemMaxLength = 140;

/// Most assets, and most watch points, of a dossier.
const lifestyleItemsMax = 10;

/// Longest secret note (`properties.secret_note` check).
const secretNoteMaxLength = 500;

/// Length of [text] as counted by Postgres `char_length` (code points).
int charLength(String text) => text.runes.length;

/// Whether [label] (trimmed) is a valid asset or watch point.
bool isValidLifestyleLabel(String label) {
  final length = charLength(label.trim());
  return length >= lifestyleItemMinLength && length <= lifestyleItemMaxLength;
}

/// Limits the text to [maxLength] code points (as Postgres `char_length`
/// counts them), cutting what is typed or pasted beyond.
class CharLengthFormatter extends TextInputFormatter {
  const new(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final runes = newValue.text.runes;
    if (runes.length <= maxLength) return newValue;
    final text = String.fromCharCodes(runes.take(maxLength));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// An asset or watch point being edited on V6.
///
/// Its [id] is chosen by the app when the item is added (a random UUID), so
/// that saving it again after a lost answer updates the same
/// `lifestyle_items` row instead of inserting a duplicate.
final class LifestyleItemDraft extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.label,
    this.source = LifestyleItemSource.declared,
  });

  /// The draft of a saved row.
  new fromItem(LifestyleItem item, {String Function()? newId})
    : this(
        id: item.id ?? (newId ?? generateUuidV4)(),
        kind: item.kind,
        label: item.label,
        source: item.source,
      );

  final String id;
  final LifestyleItemKind kind;
  final String label;

  /// [LifestyleItemSource.voice] when the agent proposed it (V6 "Parlez
  /// librement"), kept when the seller edits it.
  final LifestyleItemSource source;

  bool get fromVoice => source == LifestyleItemSource.voice;

  LifestyleItemDraft copyWith({String? label}) => LifestyleItemDraft(
    id: id,
    kind: kind,
    label: label ?? this.label,
    source: source,
  );

  /// The `lifestyle_items` row of this draft, at [sortOrder] in its list.
  LifestyleItem toItem({required String propertyId, required int sortOrder}) =>
      LifestyleItem(
        id: id,
        propertyId: propertyId,
        kind: kind,
        label: label,
        sortOrder: sortOrder,
        source: source,
      );

  @override
  List<Object?> get props => [id, kind, label, source];
}
