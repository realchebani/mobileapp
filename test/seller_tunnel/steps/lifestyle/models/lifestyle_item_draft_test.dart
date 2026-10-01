import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  group('isValidLifestyleLabel', () {
    test('accepts 3 to 140 trimmed characters', () {
      expect(isValidLifestyleLabel('  ab  '), isFalse);
      expect(isValidLifestyleLabel('abc'), isTrue);
      expect(isValidLifestyleLabel('a' * 140), isTrue);
      expect(isValidLifestyleLabel('a' * 141), isFalse);
    });

    test('counts code points, as Postgres does', () {
      expect(isValidLifestyleLabel('🌳🌳'), isFalse);
      expect(isValidLifestyleLabel('🌳🌳🌳'), isTrue);
      expect(isValidLifestyleLabel('🌳' * 140), isTrue);
      expect(isValidLifestyleLabel('🌳' * 141), isFalse);
      expect(charLength('é🌳'), 2);
    });
  });

  group('CharLengthFormatter', () {
    const formatter = CharLengthFormatter(3);

    test('keeps a text within the limit', () {
      const value = TextEditingValue(text: '🌳🌳🌳');
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });

    test('cuts the code points beyond the limit', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '🌳🌳🌳🌳a'),
      );
      expect(result.text, '🌳🌳🌳');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
    });
  });

  group('generateUuidV4', () {
    test('builds a version 4 UUID', () {
      final pattern = RegExp(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(generateUuidV4(), matches(pattern));
      expect(generateUuidV4(Random(1)), matches(pattern));
      expect(generateUuidV4(Random(1)), generateUuidV4(Random(1)));
      expect(generateUuidV4(), isNot(generateUuidV4()));
    });
  });

  group('LifestyleItemDraft', () {
    const item = LifestyleItem(
      id: 'a1',
      propertyId: 'p',
      kind: LifestyleItemKind.watchPoint,
      label: 'Rue chargée',
      sortOrder: 4,
    );

    test('is built from a row, keeping its id', () {
      expect(
        LifestyleItemDraft.fromItem(item),
        const LifestyleItemDraft(
          id: 'a1',
          kind: LifestyleItemKind.watchPoint,
          label: 'Rue chargée',
        ),
      );
    });

    test('gets a new id for a row without one', () {
      const row = LifestyleItem(
        propertyId: 'p',
        kind: LifestyleItemKind.asset,
        label: 'Calme',
      );
      expect(LifestyleItemDraft.fromItem(row, newId: () => 'x').id, 'x');
      expect(LifestyleItemDraft.fromItem(row).id, hasLength(36));
    });

    test('copyWith and toItem', () {
      final draft = LifestyleItemDraft.fromItem(item).copyWith(label: 'Bus');
      expect(draft.label, 'Bus');
      expect(draft.copyWith(), draft);
      expect(
        draft.toItem(propertyId: 'p', sortOrder: 2),
        const LifestyleItem(
          id: 'a1',
          propertyId: 'p',
          kind: LifestyleItemKind.watchPoint,
          label: 'Bus',
          sortOrder: 2,
        ),
      );
    });
  });
}
