import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

const _titleDeed = PropertyDocument(
  id: 'd1',
  propertyId: 'property-id',
  kind: DocumentKind.titleDeed,
  storagePath: 'user-id/property-id/1_titre.pdf',
  fileName: 'titre.pdf',
);

const _identity = PropertyDocument(
  id: 'd2',
  propertyId: 'property-id',
  kind: DocumentKind.identityDocument,
  storagePath: 'user-id/property-id/2_photo.jpg',
  fileName: 'photo.jpg',
);

final _bytes = Uint8List.fromList([1, 2, 3]);

const _locked = Property(
  id: 'property-id',
  ownerId: 'user-id',
  status: PropertyStatus.inReview,
);

final _photo = PickedDocument(
  fileName: 'photo.jpg',
  mimeType: 'image/jpeg',
  bytes: _bytes,
);

void main() {
  late MockPropertyRepository repository;
  late _MockDocumentPicker picker;
  late List<Uri> opened;
  late bool openResult;

  setUpAll(() {
    registerFallbackValue(DocumentSource.camera);
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(_titleDeed);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    repository = MockPropertyRepository();
    picker = _MockDocumentPicker();
    opened = [];
    openResult = true;
    when(() => picker.pick(any()))
        .thenAnswer((_) async => XFile.fromData(_bytes, path: 'photo.jpg'));
    when(
      () => repository.uploadDocument(
        ownerId: any(named: 'ownerId'),
        propertyId: any(named: 'propertyId'),
        kind: any(named: 'kind'),
        fileName: any(named: 'fileName'),
        bytes: any(named: 'bytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async => _identity);
    when(() => repository.deleteDocument(any())).thenAnswer((_) async {});
    when(() => repository.getDocuments(any()))
        .thenAnswer((_) async => [_titleDeed]);
    when(
      () =>
          repository.getDocumentUrl(any(), expiresIn: any(named: 'expiresIn')),
    ).thenAnswer((_) async => 'https://storage.example/signed');
  });

  DocumentsCubit build({List<PropertyDocument> documents = const []}) =>
      DocumentsCubit(
        propertyRepository: repository,
        documentPicker: picker,
        openUrl: (uri) async {
          opened.add(uri);
          return openResult;
        },
        property: testProperty,
        documents: documents,
      );

  const initial = DocumentsState(property: testProperty, documents: []);

  group(DocumentsCubit, () {
    test('starts with the documents of the dossier', () {
      expect(
        build(documents: [_titleDeed]).state,
        const DocumentsState(property: testProperty, documents: [_titleDeed]),
      );
    });

    group('mimeTypeOf', () {
      test('reads the extension', () {
        expect(
          DocumentsCubit.mimeTypeOf(XFile.fromData(_bytes, path: 'A.PDF')),
          'application/pdf',
        );
        expect(
          DocumentsCubit.mimeTypeOf(XFile('/tmp/scan.heic')),
          'image/heic',
        );
      });

      test('falls back to the reported type', () {
        expect(
          DocumentsCubit.mimeTypeOf(
            XFile.fromData(_bytes, path: 'scan', mimeType: 'image/PNG'),
          ),
          'image/png',
        );
      });

      test('rejects other types', () {
        expect(
          DocumentsCubit.mimeTypeOf(
            XFile.fromData(_bytes, path: 'notes.docx', mimeType: 'text/plain'),
          ),
          isNull,
        );
        expect(DocumentsCubit.mimeTypeOf(XFile.fromData(_bytes)), isNull);
      });
    });

    group('pick', () {
      const picking = DocumentsState(
        property: testProperty,
        documents: [],
        picking: true,
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing when cancelled',
        setUp: () => when(() => picker.pick(any())).thenAnswer((_) async {
          return null;
        }),
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.files),
        expect: () => const [picking, initial],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'keeps a valid file until its kind is known',
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.camera),
        expect: () => [
          picking,
          initial,
          DocumentsState(
            property: testProperty,
            documents: const [],
            pending: _photo,
          ),
        ],
        verify: (cubit) => expect(cubit.state.isBusy, isTrue),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'ignores a second tap while the picker is open',
        build: build,
        act: (cubit) async {
          final first = cubit.pick(DocumentSource.camera);
          await cubit.pick(DocumentSource.files);
          await first;
        },
        verify: (_) => verify(() => picker.pick(any())).called(1),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'uploads a valid file at once when its kind is given',
        build: build,
        act: (cubit) => cubit.pick(
          DocumentSource.camera,
          kind: DocumentKind.identityDocument,
        ),
        expect: () => [
          picking,
          initial,
          DocumentsState(
            property: testProperty,
            documents: const [],
            uploading: _photo,
          ),
          const DocumentsState(
            property: testProperty,
            documents: [_identity],
            notice: DocumentsNotice.uploaded,
            noticeCount: 1,
          ),
        ],
        verify: (_) => verify(
          () => repository.uploadDocument(
            ownerId: 'user-id',
            propertyId: 'property-id',
            kind: DocumentKind.identityDocument,
            fileName: 'photo.jpg',
            bytes: _bytes,
            mimeType: 'image/jpeg',
          ),
        ).called(1),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'rejects an unsupported type',
        setUp: () => when(
          () => picker.pick(any()),
        ).thenAnswer((_) async => XFile.fromData(_bytes, path: 'notes.docx')),
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.files),
        skip: 2,
        expect: () => [
          initial.copyWith(notice: DocumentsNotice.unsupportedType),
        ],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'rejects a file over 20 MB',
        setUp: () => when(() => picker.pick(any())).thenAnswer(
          (_) async => XFile.fromData(
            _bytes,
            path: 'big.pdf',
            length: DocumentsCubit.maxFileBytes + 1,
          ),
        ),
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.files),
        skip: 2,
        expect: () => [initial.copyWith(notice: DocumentsNotice.fileTooLarge)],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the access was refused',
        setUp: () => when(() => picker.pick(any()))
            .thenThrow(DocumentAccessDenied(PlatformException(code: 'denied'))),
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.camera),
        skip: 2,
        expect: () => [initial.copyWith(notice: DocumentsNotice.accessDenied)],
        errors: () => [isA<DocumentAccessDenied>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the file cannot be picked',
        setUp: () =>
            when(() => picker.pick(any())).thenThrow(Exception('oops')),
        build: build,
        act: (cubit) => cubit.pick(DocumentSource.files),
        skip: 2,
        expect: () => [initial.copyWith(notice: DocumentsNotice.pickFailed)],
        errors: () => [isA<Exception>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing while busy',
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [],
          uploading: _photo,
        ),
        act: (cubit) => cubit.pick(DocumentSource.camera),
        expect: () => const <DocumentsState>[],
        verify: (_) => verifyNever(() => picker.pick(any())),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing on a locked dossier',
        build: build,
        seed: () => const DocumentsState(property: _locked, documents: []),
        act: (cubit) => cubit.pick(DocumentSource.camera),
        expect: () => const <DocumentsState>[],
        verify: (_) => verifyNever(() => picker.pick(any())),
      );
    });

    group('kindChosen', () {
      blocTest<DocumentsCubit, DocumentsState>(
        'uploads the pending file',
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [_titleDeed],
          pending: _photo,
        ),
        act: (cubit) => cubit.kindChosen(DocumentKind.identityDocument),
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [_titleDeed],
            uploading: _photo,
          ),
          const DocumentsState(
            property: testProperty,
            documents: [_titleDeed, _identity],
            notice: DocumentsNotice.uploaded,
            noticeCount: 1,
          ),
        ],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing without a pending file',
        build: build,
        act: (cubit) => cubit.kindChosen(DocumentKind.plan),
        expect: () => const <DocumentsState>[],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'reloads the documents when the upload fails',
        setUp: () => when(
          () => repository.uploadDocument(
            ownerId: any(named: 'ownerId'),
            propertyId: any(named: 'propertyId'),
            kind: any(named: 'kind'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenThrow(const DocumentUploadFailure()),
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [],
          pending: _photo,
        ),
        act: (cubit) => cubit.kindChosen(DocumentKind.titleDeed),
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [],
            uploading: _photo,
          ),
          const DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            notice: DocumentsNotice.uploadFailed,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<DocumentUploadFailure>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'keeps the documents when they cannot be reloaded',
        setUp: () {
          when(
            () => repository.uploadDocument(
              ownerId: any(named: 'ownerId'),
              propertyId: any(named: 'propertyId'),
              kind: any(named: 'kind'),
              fileName: any(named: 'fileName'),
              bytes: any(named: 'bytes'),
              mimeType: any(named: 'mimeType'),
            ),
          ).thenThrow(const PropertySaveFailure());
          when(() => repository.getDocuments(any()))
              .thenThrow(const PropertyLoadFailure());
        },
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [_identity],
          pending: _photo,
        ),
        act: (cubit) => cubit.kindChosen(DocumentKind.titleDeed),
        skip: 1,
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_identity],
            notice: DocumentsNotice.uploadFailed,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<PropertySaveFailure>(), isA<PropertyLoadFailure>()],
      );
    });

    group('retrying a failed upload', () {
      final stored = PropertyDocument(
        id: 'd3',
        propertyId: 'property-id',
        kind: DocumentKind.identityDocument,
        storagePath: 'user-id/property-id/3_photo.jpg',
        fileName: 'photo.jpg',
        sizeBytes: _bytes.length,
      );
      late int uploads;

      setUp(() {
        uploads = 0;
        when(
          () => repository.uploadDocument(
            ownerId: any(named: 'ownerId'),
            propertyId: any(named: 'propertyId'),
            kind: any(named: 'kind'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer((_) async {
          if (uploads++ == 0) throw TimeoutException('lost');
          return _identity;
        });
      });

      blocTest<DocumentsCubit, DocumentsState>(
        'keeps the file stored by the lost upload',
        build: build,
        act: (cubit) async {
          await cubit.pick(DocumentSource.camera, kind: DocumentKind.other);
          // The lost upload went through after all.
          when(() => repository.getDocuments(any()))
              .thenAnswer((_) async => [stored]);
          await cubit.pick(DocumentSource.camera, kind: DocumentKind.other);
        },
        verify: (cubit) {
          expect(uploads, 1);
          expect(cubit.state.documents, [stored]);
          expect(cubit.state.notice, DocumentsNotice.uploaded);
          expect(cubit.state.isUploading, isFalse);
        },
        errors: () => [isA<TimeoutException>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'uploads again when the file was not stored',
        build: build,
        act: (cubit) async {
          await cubit.pick(DocumentSource.camera, kind: DocumentKind.other);
          await cubit.pick(DocumentSource.camera, kind: DocumentKind.other);
        },
        verify: (cubit) {
          expect(uploads, 2);
          expect(cubit.state.documents, [_titleDeed, _identity]);
        },
        errors: () => [isA<TimeoutException>()],
      );
    });

    blocTest<DocumentsCubit, DocumentsState>(
      'kindChosen does nothing on a locked dossier',
      build: build,
      seed: () => DocumentsState(
        property: _locked,
        documents: const [],
        pending: _photo,
      ),
      act: (cubit) => cubit.kindChosen(DocumentKind.plan),
      expect: () => const <DocumentsState>[],
    );

    blocTest<DocumentsCubit, DocumentsState>(
      'delete does nothing on a locked dossier',
      build: build,
      seed: () =>
          const DocumentsState(property: _locked, documents: [_identity]),
      act: (cubit) => cubit.delete(_identity),
      expect: () => const <DocumentsState>[],
    );

    test('a closed cubit ignores late answers', () async {
      final cubit = build();
      await cubit.close();
      cubit.pendingDiscarded();
      expect(cubit.state, initial);
    });

    blocTest<DocumentsCubit, DocumentsState>(
      'pendingDiscarded drops the pending file',
      build: build,
      seed: () => DocumentsState(
        property: testProperty,
        documents: const [],
        pending: _photo,
      ),
      act: (cubit) => cubit.pendingDiscarded(),
      expect: () => const [initial],
    );

    group('delete', () {
      blocTest<DocumentsCubit, DocumentsState>(
        'deletes the document',
        build: () => build(documents: [_titleDeed, _identity]),
        act: (cubit) => cubit.delete(_identity),
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed, _identity],
            busyDocumentIds: {'d2'},
          ),
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            notice: DocumentsNotice.deleted,
            noticeCount: 1,
          ),
        ],
        verify: (_) =>
            verify(() => repository.deleteDocument(_identity)).called(1),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'reloads the documents when it fails',
        setUp: () =>
            when(() => repository.deleteDocument(any()))
                .thenThrow(const PropertyDeleteFailure()),
        build: () => build(documents: [_titleDeed, _identity]),
        act: (cubit) => cubit.delete(_identity),
        skip: 1,
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            notice: DocumentsNotice.deleteFailed,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<PropertyDeleteFailure>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing while busy',
        build: build,
        seed: () => const DocumentsState(
          property: testProperty,
          documents: [_identity],
          busyDocumentIds: {'d2'},
        ),
        act: (cubit) => cubit.delete(_identity),
        expect: () => const <DocumentsState>[],
      );
    });

    group('open', () {
      blocTest<DocumentsCubit, DocumentsState>(
        'opens the signed URL of the document',
        build: () => build(documents: [_titleDeed]),
        act: (cubit) => cubit.open(_titleDeed),
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            busyDocumentIds: {'d1'},
          ),
          DocumentsState(property: testProperty, documents: [_titleDeed]),
        ],
        verify: (_) {
          verify(
            () => repository.getDocumentUrl(
              _titleDeed.storagePath,
              expiresIn: const Duration(seconds: 120),
            ),
          ).called(1);
          expect(opened, [Uri.parse('https://storage.example/signed')]);
        },
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the URL cannot be opened',
        setUp: () => openResult = false,
        build: () => build(documents: [_titleDeed]),
        act: (cubit) => cubit.open(_titleDeed),
        skip: 1,
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            notice: DocumentsNotice.openFailed,
            noticeCount: 1,
          ),
        ],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the URL cannot be created',
        setUp: () => when(
          () => repository.getDocumentUrl(
            any(),
            expiresIn: any(named: 'expiresIn'),
          ),
        ).thenThrow(const PropertyLoadFailure()),
        build: () => build(documents: [_titleDeed]),
        act: (cubit) => cubit.open(_titleDeed),
        skip: 1,
        expect: () => const [
          DocumentsState(
            property: testProperty,
            documents: [_titleDeed],
            notice: DocumentsNotice.openFailed,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<PropertyLoadFailure>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing while the document is being opened',
        build: build,
        seed: () => const DocumentsState(
          property: testProperty,
          documents: [_titleDeed],
          busyDocumentIds: {'d1'},
        ),
        act: (cubit) => cubit.open(_titleDeed),
        expect: () => const <DocumentsState>[],
      );
    });

    test('state exposes the checklist of the dossier', () {
      const state = DocumentsState(
        property: testProperty,
        documents: [_titleDeed],
      );
      expect(state.checklist.rows.first.documents, [_titleDeed]);
      expect(state.isBusy, isFalse);
    });
  });
}
