import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/role/role.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(() async {
    registerFallbackValue(UserRole.seller);
    await loadRealestyFonts();
  });

  late ProfileCubit profileCubit;

  ProfileState loaded({
    String? firstName,
    RoleUpdateStatus roleUpdateStatus = RoleUpdateStatus.idle,
  }) => ProfileState(
    status: ProfileStatus.success,
    profile: Profile(id: 'id', firstName: firstName),
    roleUpdateStatus: roleUpdateStatus,
  );

  setUp(() {
    usePhoneSurface();
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(loaded());
    when(() => profileCubit.selectRole(any())).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) =>
      tester.pumpApp(const RolePage(), profileCubit: profileCubit);

  group(RolePage, () {
    testWidgets('greets without a first name', (tester) async {
      await pump(tester);

      expect(find.textContaining('Bonjour !'), findsOneWidget);
      expect(find.text('Agent Realesty'), findsOneWidget);
      expect(find.text('Je souhaite vendre'), findsOneWidget);
      expect(find.text('Je souhaite acheter'), findsOneWidget);
      expect(
        find.text(
          'Vous pourrez basculer entre vos espaces vendeur et acheteur à tout '
          'moment.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('greets with the first name', (tester) async {
      when(() => profileCubit.state).thenReturn(loaded(firstName: 'Sophie'));
      await pump(tester);

      expect(find.textContaining('Bonjour Sophie !'), findsOneWidget);
    });

    testWidgets('selects the seller or buyer role', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Je souhaite vendre'));
      verify(() => profileCubit.selectRole(UserRole.seller)).called(1);

      await tester.tap(find.text('Je souhaite acheter'));
      verify(() => profileCubit.selectRole(UserRole.buyer)).called(1);
    });

    testWidgets('ignores taps while saving', (tester) async {
      when(() => profileCubit.state)
          .thenReturn(loaded(roleUpdateStatus: RoleUpdateStatus.inProgress));
      await pump(tester);

      await tester.tap(find.text('Je souhaite vendre'));
      verifyNever(() => profileCubit.selectRole(any()));
    });

    testWidgets('shows a save failure', (tester) async {
      whenListen(
        profileCubit,
        Stream.fromIterable([
          loaded(roleUpdateStatus: RoleUpdateStatus.inProgress),
          loaded(roleUpdateStatus: RoleUpdateStatus.failure),
        ]),
        initialState: loaded(),
      );
      await pump(tester);
      await tester.pump();

      expect(
        find.text('Impossible d’enregistrer votre choix. Réessayez.'),
        findsOneWidget,
      );
    });
  });
}
