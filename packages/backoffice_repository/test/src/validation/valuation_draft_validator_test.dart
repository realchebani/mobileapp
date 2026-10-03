import 'dart:convert';
import 'dart:io';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:test/test.dart';

void main() {
  group(ValuationDraftValidator, () {
    final fixture = jsonDecode(
      File('../../supabase/functions/tests/fixtures/valuation_drafts.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

    for (final raw in fixture['cases'] as List<dynamic>) {
      final testCase = raw as Map<String, dynamic>;
      test('parity with SQL: ${testCase['name']}', () {
        expect(
          ValuationDraftValidator.validate(testCase['payload']),
          ValidationError.listFrom(testCase['errors']),
        );
      });
    }

    test('null is an empty draft', () {
      expect(ValuationDraftValidator.validate(null), hasLength(3));
    });
  });

  group(ValidationError, () {
    test('reads the SQL list and writes JSON', () {
      final errors = ValidationError.listFrom([
        {'path': 'value_eur', 'code': 'required'},
        'ignored',
      ]);
      expect(errors, [const ValidationError('value_eur', 'required')]);
      expect(errors.single.toJson(), {'path': 'value_eur', 'code': 'required'});
      expect('${errors.single}', 'value_eur: required');
      expect(ValidationError.listFrom(null), isEmpty);
      expect(ValidationError.listFrom([<String, dynamic>{}]), [
        const ValidationError('', ''),
      ]);
    });
  });
}
