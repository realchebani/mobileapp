import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/valuation_form/valuation_form.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeRepository repository;

  setUp(() {
    repository = MockBackOfficeRepository();
    when(
      () => repository.saveDraft(
        any(),
        any(),
        expectedVersion: any(named: 'expectedVersion'),
      ),
    ).thenAnswer(
      (invocation) async =>
          (invocation.namedArguments[#expectedVersion] as int) + 1,
    );
    when(() => repository.certify(any(), version: any(named: 'version')))
        .thenAnswer((_) async => 'v1');
    when(
      () => repository.submitForApproval(any(), version: any(named: 'version')),
    ).thenAnswer((_) async {});
    when(() => repository.returnDraft(any(), any())).thenAnswer((_) async {});
    when(
      () => repository.uploadReport(any(), any(), pages: any(named: 'pages')),
    ).thenAnswer((_) async {});
  });

  ValuationFormCubit build({ValuationDraft? draft}) => ValuationFormCubit(
    repository: repository,
    propertyId: 'p1',
    draft: draft,
    autosaveDelay: const Duration(milliseconds: 10),
  );

  group('pre-fills', () {
    final dossier = dossierFixture();

    test('technical sheet from the fill sheet', () {
      expect(technicalSheetFrom(dossier), [
        {
          'label': 'Année de construction',
          'value': '1998',
          'provenance': 'declared',
        },
        {'label': 'Toiture', 'value': 'Tuiles', 'provenance': 'document'},
        {
          'label': 'Assainissement',
          'value': 'Tout-à-l’égout',
          'provenance': 'external',
        },
      ]);
    });

    test('comparables from the DVF snapshot, clipped', () {
      expect(comparablesFrom(dossier), [
        {
          'street': 'rue Lucien Cozon',
          'area_m2': 107,
          'land_m2': 576,
          'price_eur': 457000,
          'excluded': false,
        },
      ]);
      final long = Dossier.fromJson({
        ...dossierJson(),
        'market': {
          'comparables': [
            {'street': 'r' * 130, 'price_eur': 1000},
          ],
        },
      });
      expect(comparablesFrom(long).single['street'], hasLength(120));
    });

    test('adjustments totals', () {
      expect(adjustmentsMismatch([]), isNull);
      expect(
        adjustmentsMismatch([
          {'amount_eur': 100, 'kind': 'base'},
          {'amount_eur': 20},
          {'amount_eur': 'x'},
          {'amount_eur': 5, 'kind': 'control'},
          {'amount_eur': 120, 'kind': 'total'},
        ]),
        isNull,
      );
      expect(
        adjustmentsMismatch([
          {'amount_eur': 100, 'kind': 'base'},
          {'amount_eur': 130, 'kind': 'total'},
          {'amount_eur': 1, 'kind': 'total'},
        ]),
        (100, 130),
      );
    });
  });

  blocTest<ValuationFormCubit, ValuationFormState>(
    'edits are saved automatically',
    build: build,
    act: (cubit) async {
      cubit
        ..setField('value_eur', 525000)
        ..setField('value_eur', null)
        ..setField('low_eur', 1000);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
    verify: (cubit) {
      expect(cubit.state.payload, {'low_eur': 1000});
      expect(cubit.state.version, 1);
      expect(cubit.state.saveStatus, SaveStatus.saved);
      expect(cubit.state.errors, isNotEmpty);
      verify(
        () => repository.saveDraft('p1', {'low_eur': 1000}, expectedVersion: 0),
      ).called(1);
    },
  );

  blocTest<ValuationFormCubit, ValuationFormState>(
    'a save waits for the one in progress; nothing to save',
    build: () => build(
      draft: const ValuationDraft(payload: {'value_eur': 1}, version: 3),
    ),
    act: (cubit) async {
      await cubit.save();
      cubit.setField('value_eur', 2);
      final first = cubit.save();
      cubit.setField('value_eur', 3);
      await Future.wait([first, cubit.save()]);
    },
    verify: (cubit) {
      expect(cubit.state.version, 5);
      expect(cubit.state.saveStatus, SaveStatus.saved);
    },
  );

  blocTest<ValuationFormCubit, ValuationFormState>(
    'conflict and failure, then reset',
    setUp: () {
      var calls = 0;
      when(
        () => repository.saveDraft(
          any(),
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => throw BackOfficeFailure(
          calls++ == 0
              ? BackOfficeFailureReason.draftConflict
              : BackOfficeFailureReason.unknown,
          details: 'Paul P.',
        ),
      );
    },
    build: build,
    act: (cubit) async {
      cubit.setField('value_eur', 1);
      await expectLater(cubit.save(), throwsA(isA<BackOfficeFailure>()));
      expect(cubit.state.saveStatus, SaveStatus.conflict);
      expect(cubit.state.conflictBy, 'Paul P.');
      cubit.setField('value_eur', 2);
      await expectLater(cubit.save(), throwsA(isA<BackOfficeFailure>()));
      expect(cubit.state.saveStatus, SaveStatus.failure);
      cubit.reset(
        ValuationDraft(
          payload: const {'value_eur': 9},
          version: 7,
          status: ValuationDraftStatus.submittedForApproval,
          updatedAt: DateTime(2026),
          approvalNote: 'x',
          submittedByName: 'Paul P.',
        ),
      );
      expect(cubit.state.version, 7);
      expect(cubit.state.isSubmitted, isTrue);
      cubit.reset(null);
    },
    verify: (cubit) => expect(cubit.state.version, 0),
  );

  blocTest<ValuationFormCubit, ValuationFormState>(
    'certify, submit, return, upload',
    build: () =>
        build(draft: const ValuationDraft(payload: validPayload, version: 2)),
    act: (cubit) async {
      expect(await cubit.certify(), 'v1');
      await cubit.submitForApproval();
      expect(cubit.state.isSubmitted, isTrue);
      await cubit.returnDraft('Revoir');
      expect(cubit.state.approvalNote, 'Revoir');
      await cubit.uploadReport(pdfBytes(), 11);
    },
    verify: (cubit) {
      expect(cubit.state.action, FormAction.none);
      verify(() => repository.certify('p1', version: 2)).called(1);
      verify(() => repository.submitForApproval('p1', version: 2)).called(1);
      verify(() => repository.uploadReport('p1', any(), pages: 11)).called(1);
    },
  );
}
