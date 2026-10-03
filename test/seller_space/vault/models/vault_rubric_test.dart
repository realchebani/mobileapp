import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  group(VaultRubric, () {
    test('files every kind in one rubric', () {
      for (final kind in DocumentKind.values) {
        expect(VaultRubric.of(kind).kinds, contains(kind));
      }
      expect(VaultRubric.of(DocumentKind.dpe), VaultRubric.energy);
      expect(VaultRubric.of(DocumentKind.coOwnership), VaultRubric.property);
      expect(VaultRubric.of(DocumentKind.insurance), VaultRubric.works);
    });

    test('parses its code', () {
      expect(VaultRubric.fromCode('energie'), VaultRubric.energy);
      expect(VaultRubric.fromCode('nope'), isNull);
      expect(VaultRubric.fromCode(null), isNull);
    });

    test('accepts documents except the Realesty ones', () {
      expect(VaultRubric.mandates.acceptsDocuments, isFalse);
      expect(VaultRubric.identity.acceptsDocuments, isTrue);
    });
  });
}
