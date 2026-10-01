import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/cubit/notification_preference_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/data/notification_preference_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockStore extends Mock implements NotificationPreferenceStore;

void main() {
  late _MockStore store;

  setUp(() {
    store = _MockStore();
    when(() => store.write(any(), enabled: any(named: 'enabled')))
        .thenAnswer((_) async {});
  });

  NotificationPreferenceCubit build({
    bool initialValue = true,
    RemoteNotificationSave? saveRemote,
  }) => NotificationPreferenceCubit(
    store: store,
    propertyId: 'p1',
    initialValue: initialValue,
    saveRemote: saveRemote,
  );

  test('starts from the dossier value', () {
    expect(build(initialValue: false).state, isFalse);
  });

  group('load', () {
    blocTest<NotificationPreferenceCubit, bool>(
      'emits the saved choice',
      setUp: () => when(() => store.read('p1')).thenAnswer((_) async => false),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [false],
    );

    blocTest<NotificationPreferenceCubit, bool>(
      'keeps the dossier value when nothing is saved',
      setUp: () => when(() => store.read('p1')).thenAnswer((_) async => null),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => <bool>[],
    );

    blocTest<NotificationPreferenceCubit, bool>(
      'keeps the dossier value when reading fails',
      setUp: () => when(() => store.read('p1')).thenThrow(Exception('io')),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => <bool>[],
      errors: () => [isA<Exception>()],
    );

    test('keeps a choice made while loading', () async {
      when(() => store.read('p1')).thenAnswer((_) async => true);
      final cubit = build(initialValue: false);
      final load = cubit.load();
      await cubit.toggled(enabled: false);
      await load;
      expect(cubit.state, isFalse);
    });

    test('does not emit once closed', () async {
      when(() => store.read('p1')).thenAnswer((_) async => false);
      final cubit = build();
      final load = cubit.load();
      await cubit.close();
      await load;
      expect(cubit.state, isTrue);
    });
  });

  group('toggled', () {
    blocTest<NotificationPreferenceCubit, bool>(
      'emits and saves the choice',
      build: build,
      act: (cubit) => cubit.toggled(enabled: false),
      expect: () => [false],
      verify: (_) => verify(() => store.write('p1', enabled: false)).called(1),
    );

    blocTest<NotificationPreferenceCubit, bool>(
      'keeps the choice when saving fails',
      setUp: () =>
          when(() => store.write(any(), enabled: any(named: 'enabled')))
              .thenThrow(Exception('io')),
      build: build,
      act: (cubit) => cubit.toggled(enabled: false),
      expect: () => [false],
      errors: () => [isA<Exception>()],
    );
    blocTest<NotificationPreferenceCubit, bool>(
      'saves in the dossier, then on the device',
      build: () => build(saveRemote: ({required enabled}) async => true),
      act: (cubit) => cubit.toggled(enabled: false),
      expect: () => [false],
      verify: (_) => verify(() => store.write('p1', enabled: false)).called(1),
    );

    blocTest<NotificationPreferenceCubit, bool>(
      'reverts when the dossier cannot be saved',
      build: () => build(saveRemote: ({required enabled}) async => false),
      act: (cubit) => cubit.toggled(enabled: false),
      expect: () => [false, true],
      verify: (_) =>
          verifyNever(() => store.write(any(), enabled: any(named: 'enabled'))),
    );

    test('does not revert once closed', () async {
      final cubit = build(saveRemote: ({required enabled}) async => false);
      final toggle = cubit.toggled(enabled: false);
      await cubit.close();
      await toggle;
      expect(cubit.state, isFalse);
    });
  });
}
