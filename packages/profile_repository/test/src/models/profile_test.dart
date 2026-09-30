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
  });
}
