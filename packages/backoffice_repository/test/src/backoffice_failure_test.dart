import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  group(BackOfficeFailure, () {
    test('maps the SQL codes exactly', () {
      final failure = BackOfficeFailure.from(
        const PostgrestException(message: 'mfa_required', code: '42501'),
      );
      expect(failure.reason, BackOfficeFailureReason.mfaRequired);
      expect(failure.details, isNull);
      expect(
        BackOfficeFailureReason.parse('identity_document_forbidden'),
        BackOfficeFailureReason.identityDocumentForbidden,
      );
      expect(
        BackOfficeFailureReason.parse('something else'),
        BackOfficeFailureReason.unknown,
      );
      expect('$failure', contains('mfaRequired'));
    });

    test('keeps the details and the validation errors', () {
      final conflict = BackOfficeFailure.from(
        const PostgrestException(
          message: 'draft_conflict',
          details: 'Julien M.',
        ),
      );
      expect(conflict.details, 'Julien M.');
      final invalid = BackOfficeFailure.from(
        const PostgrestException(
          message: 'draft_invalid',
          details: '[{"path": "value_eur", "code": "required"}]',
        ),
      );
      expect(invalid.errors, [const ValidationError('value_eur', 'required')]);
      final broken = BackOfficeFailure.from(
        const PostgrestException(message: 'draft_invalid', details: '{'),
      );
      expect(broken.errors, isEmpty);
      final empty = BackOfficeFailure.from(
        const PostgrestException(message: 'draft_invalid', details: ''),
      );
      expect(empty.details, isNull);
    });

    test('reads the bo-files answer', () {
      final failure = BackOfficeFailure.from(
        const FunctionException(
          status: 403,
          details: {'error': 'identity_document_forbidden'},
        ),
      );
      expect(failure.reason, BackOfficeFailureReason.identityDocumentForbidden);
      expect(
        BackOfficeFailure.from(const FunctionException(status: 500)).reason,
        BackOfficeFailureReason.unknown,
      );
    });

    test('other errors are unknown; failures pass through', () {
      const original = BackOfficeFailure(BackOfficeFailureReason.forbidden);
      expect(BackOfficeFailure.from(original), same(original));
      expect(
        BackOfficeFailure.from(Exception('x')).reason,
        BackOfficeFailureReason.unknown,
      );
    });
  });
}
