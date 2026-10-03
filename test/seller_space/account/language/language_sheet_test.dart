import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/account/language/language_sheet.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late LocaleCubit localeCubit;
  late MockProfileCubit profileCubit;
  late MockProfileRepository repository;

  setUp(() {
    localeCubit = LocaleCubit();
    profileCubit = MockProfileCubit();
    repository = MockProfileRepository();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(
        status: ProfileStatus.success,
        profile: Profile(id: 'user-id'),
      ),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpApp(
      BlocProvider.value(
        value: localeCubit,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLanguageSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
      profileCubit: profileCubit,
      profileRepository: repository,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('LanguageSheet', () {
    testWidgets('applies a language and saves it in the profile', (
      tester,
    ) async {
      when(() => repository.updateLocale(any(), any()))
          .thenAnswer((_) async => const Profile(id: 'user-id', locale: 'es'));
      await pump(tester);
      expect(find.text('Langue de l’appareil'), findsOneWidget);
      expect(find.textContaining('Actuellement'), findsOneWidget);
      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle();
      expect(localeCubit.state, 'es');
      verify(() => repository.updateLocale('user-id', 'es')).called(1);
      verify(
        () => profileCubit.profileUpdated(
          const Profile(id: 'user-id', locale: 'es'),
        ),
      ).called(1);
    });

    testWidgets('keeps the language on the device when the profile fails', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = const Locale('de');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      when(() => repository.updateLocale(any(), any()))
          .thenThrow(const UpdateProfileFailure());
      await pump(tester);
      expect(find.text('Actuellement : Français'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(localeCubit.state, 'en');
    });

    testWidgets('the same language as the profile is not saved again', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Langue de l’appareil'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.updateLocale(any(), any()));
      when(() => profileCubit.state).thenReturn(const ProfileState());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.updateLocale(any(), any()));
    });

    test('names the languages', () {
      expect(languageName(AppLocalizationsFr(), 'fr'), 'Français');
      expect(languageName(AppLocalizationsFr(), null), 'Langue de l’appareil');
    });
  });
}
