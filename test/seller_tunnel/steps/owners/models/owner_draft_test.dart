import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  group('validateOwnerName', () {
    test('requires a non-blank name', () {
      expect(validateOwnerName('  '), OwnerFieldError.required);
      expect(validateOwnerName('Sophie'), isNull);
    });
  });

  group('validateOwnerPhone', () {
    test('requires a French number', () {
      expect(validateOwnerPhone(''), OwnerFieldError.required);
      expect(validateOwnerPhone('06 12'), OwnerFieldError.invalidPhone);
      expect(
        validateOwnerPhone('00 12 34 56 78'),
        OwnerFieldError.invalidPhone,
      );
      expect(validateOwnerPhone('06.12.34.56.78'), isNull);
    });
  });

  group('validateOwnerEmail', () {
    test('checks the format and, when required, the presence', () {
      expect(validateOwnerEmail('', required: true), OwnerFieldError.required);
      expect(validateOwnerEmail(' ', required: false), isNull);
      expect(
        validateOwnerEmail('sophie@', required: false),
        OwnerFieldError.invalidEmail,
      );
      expect(validateOwnerEmail(' sophie@email.fr ', required: true), isNull);
    });
  });

  group('phoneToE164', () {
    test('converts French numbers', () {
      expect(phoneToE164('06 12 34 56 78'), '+33612345678');
      expect(phoneToE164('+33 6 12 34 56 78'), '+33612345678');
      expect(phoneToE164('0033-1-23-45-67-89'), '+33123456789');
      expect(phoneToE164('12345'), isNull);
    });
  });

  group('displayPhone', () {
    test('formats French E.164 numbers', () {
      expect(displayPhone(null), '');
      expect(displayPhone('+33698765432'), '06 98 76 54 32');
      expect(displayPhone('+4930123456'), '+4930123456');
    });
  });

  group(OwnerDraft, () {
    const owner = PropertyOwner(
      id: 'o2',
      propertyId: 'p',
      position: 2,
      firstName: 'Marc',
      lastName: 'Durand',
      phone: '+33698765432',
    );

    test('fromOwner', () {
      expect(
        OwnerDraft.fromOwner(owner),
        const OwnerDraft(
          id: 'o2',
          firstName: 'Marc',
          lastName: 'Durand',
          phone: '06 98 76 54 32',
        ),
      );
    });

    test('fullName and initials', () {
      const draft = OwnerDraft(firstName: ' élise ', lastName: 'Durand');
      expect(draft.fullName, 'élise Durand');
      expect(draft.initials, 'ÉD');
      expect(const OwnerDraft(lastName: 'Durand').initials, 'D');
    });

    test('isValid', () {
      const draft = OwnerDraft(
        firstName: 'Marc',
        lastName: 'Durand',
        phone: '06 98 76 54 32',
      );
      expect(draft.isValid(emailRequired: false), isTrue);
      expect(draft.isValid(emailRequired: true), isFalse);
      expect(
        draft.copyWith(firstName: '').isValid(emailRequired: false),
        isFalse,
      );
      expect(
        draft.copyWith(lastName: '').isValid(emailRequired: false),
        isFalse,
      );
      expect(draft.copyWith(phone: '1').isValid(emailRequired: false), isFalse);
    });

    test('toOwner trims and converts', () {
      const draft = OwnerDraft(
        id: 'o1',
        firstName: ' Sophie ',
        lastName: 'Durand ',
        phone: '06 12 34 56 78',
        email: ' sophie@email.fr ',
      );
      expect(
        draft.toOwner(propertyId: 'p', position: 1, profileId: 'u'),
        const PropertyOwner(
          id: 'o1',
          propertyId: 'p',
          position: 1,
          profileId: 'u',
          firstName: 'Sophie',
          lastName: 'Durand',
          phone: '+33612345678',
          email: 'sophie@email.fr',
        ),
      );
      expect(
        const OwnerDraft().toOwner(propertyId: 'p', position: 2).email,
        isNull,
      );
    });

    test('copyWith', () {
      const draft = OwnerDraft(id: 'a');
      expect(
        draft.copyWith(
          id: 'b',
          firstName: 'f',
          lastName: 'l',
          phone: 'p',
          email: 'e',
        ),
        const OwnerDraft(
          id: 'b',
          firstName: 'f',
          lastName: 'l',
          phone: 'p',
          email: 'e',
        ),
      );
      expect(draft.copyWith(), draft);
    });
  });
}
