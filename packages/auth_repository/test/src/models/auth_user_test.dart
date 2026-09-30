import 'package:auth_repository/auth_repository.dart';
import 'package:test/test.dart';

void main() {
  group('AuthUser', () {
    test('supports value equality', () {
      expect(
        const AuthUser(id: 'a', email: 'a@b.c'),
        const AuthUser(id: 'a', email: 'a@b.c'),
      );
      expect(const AuthUser(id: 'a'), isNot(const AuthUser(id: 'b')));
    });
  });
}
