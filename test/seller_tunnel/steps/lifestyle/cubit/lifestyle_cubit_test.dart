import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _property = Property(id: 'p', ownerId: 'u');
const _asset = LifestyleItem(
  id: 'a1',
  propertyId: 'p',
  kind: LifestyleItemKind.asset,
  label: 'École à 4 min',
);
const _asset2 = LifestyleItem(
  id: 'a2',
  propertyId: 'p',
  kind: LifestyleItemKind.asset,
  label: 'Bus ligne 17',
  sortOrder: 1,
);
const _watch = LifestyleItem(
  id: 'w1',
  propertyId: 'p',
  kind: LifestyleItemKind.watchPoint,
  label: 'Rue chargée',
);

void main() {
  late MockPropertyRepository repository;
  late List<String> calls;

  setUpAll(() => registerFallbackValue(_asset));

  setUp(() {
    repository = MockPropertyRepository();
    calls = [];
    when(() => repository.deleteLifestyleItem(any())).thenAnswer((i) async {
      calls.add('delete ${i.positionalArguments.single}');
    });
    when(() => repository.saveLifestyleItem(any())).thenAnswer((i) async {
      final item = i.positionalArguments.single as LifestyleItem;
      calls.add('save ${item.id} ${item.sortOrder}');
      return item;
    });
  });

  LifestyleCubit build({
    Property property = _property,
    List<LifestyleItem> items = const [],
    Duration timeout = const Duration(seconds: 15),
  }) {
    var next = 0;
    return LifestyleCubit(
      propertyRepository: repository,
      property: property,
      items: items,
      newId: () => 'n${next++}',
      timeout: timeout,
    );
  }

  group('initial state', () {
    test('is empty for a new dossier', () {
      final cubit = LifestyleCubit(
        propertyRepository: repository,
        property: _property,
      );
      expect(cubit.state, const LifestyleState());
      cubit.itemAdded(LifestyleItemKind.asset, 'Calme');
      expect(cubit.state.assets.single.id, hasLength(36));
    });

    test('is built from the saved answers and items', () {
      final cubit = build(
        property: const Property(
          id: 'p',
          ownerId: 'u',
          noiseLevel: 3,
          overlooking: Overlooking.slight,
          secretNote: 'Boulangerie',
        ),
        items: [_asset, _watch, _asset2],
      );
      expect(
        cubit.state,
        const LifestyleState(
          assets: [
            LifestyleItemDraft(
              id: 'a1',
              kind: LifestyleItemKind.asset,
              label: 'École à 4 min',
            ),
            LifestyleItemDraft(
              id: 'a2',
              kind: LifestyleItemKind.asset,
              label: 'Bus ligne 17',
            ),
          ],
          watchPoints: [
            LifestyleItemDraft(
              id: 'w1',
              kind: LifestyleItemKind.watchPoint,
              label: 'Rue chargée',
            ),
          ],
          noiseLevel: 3,
          overlooking: Overlooking.slight,
          secretNote: 'Boulangerie',
        ),
      );
    });
  });

  group('editing', () {
    test('adds, edits and removes items', () {
      final cubit = build()
        ..itemAdded(LifestyleItemKind.asset, '  Calme  ')
        ..itemAdded(LifestyleItemKind.watchPoint, 'Bruit');
      expect(cubit.state.assets, const [
        LifestyleItemDraft(
          id: 'n0',
          kind: LifestyleItemKind.asset,
          label: 'Calme',
        ),
      ]);
      final watch = cubit.state.watchPoints.single;
      expect(watch.id, 'n1');
      cubit
        ..itemAdded(LifestyleItemKind.watchPoint, 'Voisins')
        ..itemEdited(watch, ' Bruit le soir ');
      expect(cubit.state.watchPoints.map((d) => d.label), [
        'Bruit le soir',
        'Voisins',
      ]);
      cubit.itemRemoved(watch);
      expect(cubit.state.watchPoints.map((d) => d.label), ['Voisins']);
      expect(cubit.state.assets, hasLength(1));
    });

    test('ignores additions beyond the maximum', () {
      final cubit = build();
      for (var i = 0; i < lifestyleItemsMax + 2; i++) {
        cubit.itemAdded(LifestyleItemKind.asset, 'Atout $i');
      }
      expect(cubit.state.assets, hasLength(lifestyleItemsMax));
      expect(cubit.state.canAdd(LifestyleItemKind.asset), isFalse);
      expect(cubit.state.canAdd(LifestyleItemKind.watchPoint), isTrue);
    });

    test('sets the noise (clamped), overlooking and note', () {
      final cubit = build()
        ..noiseLevelChanged(12)
        ..overlookingChanged(Overlooking.significant)
        ..secretNoteChanged('Marché');
      expect(cubit.state.noiseLevel, 10);
      cubit.noiseLevelChanged(0);
      expect(cubit.state.noiseLevel, 1);
      expect(cubit.state.overlooking, Overlooking.significant);
      expect(cubit.state.secretNote, 'Marché');
    });

    test('is ignored while submitting', () async {
      final completer = Completer<LifestyleItem>();
      when(() => repository.saveLifestyleItem(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..itemAdded(LifestyleItemKind.asset, 'Calme');
      final submitting = cubit.submit();
      expect(cubit.state.isSubmitting, isTrue);
      cubit
        ..noiseLevelChanged(4)
        ..secretNoteChanged('x');
      unawaited(cubit.submit());
      expect(cubit.state.noiseLevel, isNull);
      expect(cubit.state.secretNote, '');
      completer.complete(_asset);
      await submitting;
      verify(() => repository.saveLifestyleItem(any())).called(1);
    });
  });

  group('patchFor', () {
    test('holds the answers and their provenance', () {
      const property = Property(
        id: 'p',
        ownerId: 'u',
        provenance: {'construction_year': 'document'},
      );
      const state = LifestyleState(
        noiseLevel: 3,
        overlooking: Overlooking.none,
        secretNote: '  Boulangerie  ',
      );
      expect(state.patchFor(property), {
        PropertyColumns.noiseLevel: 3,
        PropertyColumns.overlooking: Overlooking.none,
        PropertyColumns.secretNote: 'Boulangerie',
        PropertyColumns.provenance: {
          'construction_year': 'document',
          'noise_level': 'declared',
          'overlooking': 'declared',
          'secret_note': 'declared',
        },
      });
    });

    test('drops the provenance of cleared answers', () {
      const property = Property(
        id: 'p',
        ownerId: 'u',
        provenance: {
          'noise_level': 'declared',
          'secret_note': 'declared',
          'construction_year': 'document',
        },
      );
      expect(
        const LifestyleState(noiseLevel: 2)
            .patchFor(property)[PropertyColumns.provenance],
        {'noise_level': 'declared', 'construction_year': 'document'},
      );
    });

    test('clears the unanswered columns', () {
      expect(const LifestyleState(secretNote: '  ').patchFor(_property), {
        PropertyColumns.noiseLevel: null,
        PropertyColumns.overlooking: null,
        PropertyColumns.secretNote: null,
        PropertyColumns.provenance: const <String, Object?>{},
      });
    });
  });

  group('submit', () {
    blocTest<LifestyleCubit, LifestyleState>(
      'writes nothing when the items are unchanged',
      build: () => build(items: [_asset, _asset2, _watch]),
      act: (cubit) => cubit.submit(),
      expect: () => [
        isA<LifestyleState>().having(
          (s) => s.submission,
          'submission',
          LifestyleSubmission.inProgress,
        ),
        isA<LifestyleState>()
            .having(
              (s) => s.submission,
              'submission',
              LifestyleSubmission.success,
            )
            .having((s) => s.savedItems, 'savedItems', [
              _asset,
              _asset2,
              _watch,
            ]),
      ],
      verify: (_) => expect(calls, isEmpty),
    );

    test('deletes removed rows, then writes new and changed ones', () async {
      final cubit = build(items: [_asset, _asset2, _watch]);
      cubit
        ..itemRemoved(cubit.state.assets.first)
        ..itemEdited(cubit.state.watchPoints.single, 'Rue chargée le matin')
        ..itemAdded(LifestyleItemKind.watchPoint, 'Voisins');
      await cubit.submit();
      expect(calls, ['delete a1', 'save a2 0', 'save w1 0', 'save n0 1']);
      expect(cubit.state.submission, LifestyleSubmission.success);
      expect(cubit.state.savedItems.map((i) => i.label), [
        'Bus ligne 17',
        'Rue chargée le matin',
        'Voisins',
      ]);
      calls.clear();
      await cubit.submit();
      expect(calls, isEmpty);
    });

    test('after a failure, retries only what is left and deletes rows '
        'whose write may have happened', () async {
      final cubit = build()
        ..itemAdded(LifestyleItemKind.asset, 'Calme')
        ..itemAdded(LifestyleItemKind.asset, 'École');
      var fail = true;
      when(() => repository.saveLifestyleItem(any())).thenAnswer((i) async {
        final item = i.positionalArguments.single as LifestyleItem;
        calls.add('save ${item.id} ${item.sortOrder}');
        if (item.id == 'n1' && fail) throw Exception('lost');
        return item;
      });
      await cubit.submit();
      expect(cubit.state.submission, LifestyleSubmission.failure);
      expect(calls, ['save n0 0', 'save n1 1']);

      // The second item is removed: its write may have reached the
      // database, so it is deleted.
      calls.clear();
      fail = false;
      cubit.itemRemoved(cubit.state.assets.last);
      await cubit.submit();
      expect(calls, ['delete n1']);
      expect(cubit.state.submission, LifestyleSubmission.success);
    });

    test('times out', () {
      fakeAsync((async) {
        when(() => repository.saveLifestyleItem(any()))
            .thenAnswer((_) => Completer<LifestyleItem>().future);
        final cubit = build(timeout: const Duration(seconds: 1))
          ..itemAdded(LifestyleItemKind.asset, 'Calme');
        unawaited(cubit.submit());
        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.submission, LifestyleSubmission.failure);
      });
    });

    test('stops writing once closed', () async {
      final completer = Completer<LifestyleItem>();
      when(() => repository.saveLifestyleItem(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()
        ..itemAdded(LifestyleItemKind.asset, 'Calme')
        ..itemAdded(LifestyleItemKind.asset, 'École');
      final submitting = cubit.submit();
      await cubit.close();
      completer.complete(_asset);
      await submitting;
      verify(() => repository.saveLifestyleItem(any())).called(1);
    });

    test('stops deleting once closed', () async {
      final completer = Completer<void>();
      when(() => repository.deleteLifestyleItem(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build(items: [_asset, _asset2]);
      cubit
        ..itemRemoved(cubit.state.assets.first)
        ..itemRemoved(cubit.state.assets.last);
      final submitting = cubit.submit();
      await cubit.close();
      completer.complete();
      await submitting;
      verify(() => repository.deleteLifestyleItem(any())).called(1);
      verifyNever(() => repository.saveLifestyleItem(any()));
    });

    test('does not emit once closed', () async {
      final completer = Completer<LifestyleItem>();
      when(() => repository.saveLifestyleItem(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..itemAdded(LifestyleItemKind.asset, 'Calme');
      final submitting = cubit.submit();
      await cubit.close();
      completer.complete(_asset);
      await submitting;

      final failing = Completer<LifestyleItem>();
      when(() => repository.saveLifestyleItem(any()))
          .thenAnswer((_) => failing.future);
      final other = build()..itemAdded(LifestyleItemKind.asset, 'Calme');
      final otherSubmitting = other.submit();
      await other.close();
      failing.completeError(Exception());
      await otherSubmitting;
    });
  });
}
