import 'package:profile_repository/profile_repository.dart';
import 'package:test/test.dart';

void main() {
  group('UserRole.tryParse', () {
    test('parses known roles', () {
      expect(UserRole.tryParse('seller'), UserRole.seller);
      expect(UserRole.tryParse('buyer'), UserRole.buyer);
    });

    test('returns null for unknown values', () {
      expect(UserRole.tryParse(null), isNull);
      expect(UserRole.tryParse('agent'), isNull);
    });
  });

  group('Profile', () {
    test('fromJson reads a profiles row', () {
      expect(
        Profile.fromJson(const {'id': 'a', 'first_name': null, 'role': null}),
        const Profile(id: 'a'),
      );
      expect(
        Profile.fromJson(const {
          'id': 'a',
          'first_name': 'Jo',
          'role': 'buyer',
        }),
        const Profile(id: 'a', firstName: 'Jo', role: UserRole.buyer),
      );
    });

    test('fromJson reads the details and the deactivation', () {
      final profile = Profile.fromJson(const {
        'id': 'a',
        'first_name': 'Jo',
        'last_name': 'Doe',
        'phone': '0612345678',
        'postal_address': '1 rue',
        'locale': 'en',
        'deactivated_at': '2026-10-03T08:00:00Z',
        'deletion_due_at': '2026-11-02T08:00:00Z',
      });
      expect(profile.lastName, 'Doe');
      expect(profile.phone, '0612345678');
      expect(profile.postalAddress, '1 rue');
      expect(profile.locale, 'en');
      expect(profile.isDeactivated, isTrue);
      expect(profile.deletionDueAt, DateTime.utc(2026, 11, 2, 8));
      expect(profile.fullName, 'Jo Doe');
    });

    test('fullName is null without a name', () {
      expect(const Profile(id: 'a', firstName: ' ').fullName, isNull);
      expect(const Profile(id: 'a', lastName: 'Doe').fullName, 'Doe');
    });

    test('copies', () {
      final deactivated = Profile(
        id: 'a',
        firstName: 'Jo',
        locale: 'fr',
        deactivatedAt: DateTime(2026),
        deletionDueAt: DateTime(2026, 2),
      );
      expect(deactivated.withRole(UserRole.seller).role, UserRole.seller);
      expect(deactivated.withRole(UserRole.seller).locale, 'fr');
      expect(deactivated.withLocale(null).locale, isNull);
      expect(deactivated.withLocale('es').isDeactivated, isTrue);
      final active = deactivated.reactivated();
      expect(active.isDeactivated, isFalse);
      expect(active.deletionDueAt, isNull);
      expect(active.firstName, 'Jo');
    });
  });

  group('ProfileDetails', () {
    test('toJson trims and stores empty values as null', () {
      expect(
        const ProfileDetails(
          firstName: ' Jo ',
          lastName: '',
          phone: '06',
        ).toJson(),
        {
          'first_name': 'Jo',
          'last_name': null,
          'phone': '06',
          'postal_address': null,
        },
      );
      expect(const ProfileDetails(firstName: 'a').props, [
        'a',
        null,
        null,
        null,
      ]);
    });
  });
}
