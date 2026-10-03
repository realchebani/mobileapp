import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeRepository repository;
  final dossier = dossierFixture();

  setUp(() {
    repository = MockBackOfficeRepository();
    when(() => repository.getDossier('p1')).thenAnswer((_) async => dossier);
    when(() => repository.startReview(any())).thenAnswer((_) async {});
    when(() => repository.verifyDocument(any())).thenAnswer((_) async {});
    when(() => repository.rejectDocument(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.verifyIdentity(any())).thenAnswer((_) async {});
    when(() => repository.signFiles(any(), any())).thenAnswer(
      (invocation) async => [
        for (final file
            in invocation.positionalArguments[1] as List<FileRequest>)
          SignedFile(kind: file.kind, id: file.id, url: 'https://s/${file.id}'),
      ],
    );
    when(
      () => repository.audit(propertyId: any(named: 'propertyId')),
    ).thenAnswer(
      (_) async => [
        AuditEntry(id: 1, at: DateTime(2026), actorRole: 'admin', action: 'x'),
      ],
    );
  });

  DossierCubit build() =>
      DossierCubit(repository: repository, propertyId: 'p1');

  blocTest<DossierCubit, DossierState>(
    'loads the dossier',
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [DossierState(load: DossierLoad.ready, dossier: dossier)],
  );

  blocTest<DossierCubit, DossierState>(
    'a failed load',
    setUp: () =>
        when(() => repository.getDossier('p1')).thenThrow(Exception('x')),
    build: build,
    act: (cubit) => cubit.load(),
    errors: () => [isA<Exception>()],
    expect: () => [const DossierState(load: DossierLoad.failure)],
  );

  blocTest<DossierCubit, DossierState>(
    'actions reload the dossier and clear busy, even on failure',
    build: build,
    act: (cubit) async {
      await cubit.startReview();
      await cubit.verifyDocument('d2');
      await cubit.rejectDocument('d2', 'Illisible');
      await cubit.verifyIdentity('o1');
      when(() => repository.verifyIdentity(any())).thenThrow(Exception('x'));
      await expectLater(cubit.verifyIdentity('o1'), throwsException);
    },
    verify: (cubit) {
      expect(cubit.state.busy, isFalse);
      verify(() => repository.getDossier('p1')).called(4);
      verify(() => repository.rejectDocument('d2', 'Illisible')).called(1);
    },
  );

  blocTest<DossierCubit, DossierState>(
    'signs files and photos in batches of 60',
    build: build,
    seed: () => DossierState(
      load: DossierLoad.ready,
      dossier: Dossier(
        id: 'p1',
        role: StaffRole.admin,
        status: DossierStatus.submitted,
        property: const {'id': 'p1'},
        photos: [
          for (var i = 0; i < 61; i++)
            DossierPhoto(id: 'ph$i', roomId: 'r1', sortOrder: i),
        ],
      ),
    ),
    act: (cubit) async {
      expect(
        await cubit.signFile(const FileRequest(FileKind.document, 'd2')),
        'https://s/d2',
      );
      await cubit.loadPhotos();
      await cubit.loadPhotos();
      expect(cubit.state.photoUrls, hasLength(61));
      cubit.clearPhotoUrls();
    },
    verify: (cubit) {
      expect(cubit.state.photoUrls, isEmpty);
      verify(() => repository.signFiles('p1', any())).called(3);
    },
  );

  blocTest<DossierCubit, DossierState>(
    'nothing to sign before the load; the journal',
    build: build,
    act: (cubit) async {
      await cubit.loadPhotos();
      await cubit.loadAudit();
    },
    verify: (cubit) {
      expect(cubit.state.audit, hasLength(1));
      verifyNever(() => repository.signFiles(any(), any()));
    },
  );
}
