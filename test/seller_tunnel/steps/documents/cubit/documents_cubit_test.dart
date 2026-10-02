import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

/// Records the files it cleans; fails with [error] when given.
class _FakeProcessor extends Mock implements PhotoProcessor {
  new([this.error]);

  final Exception? error;
  final List<Uint8List> cleaned = [];

  @override
  Future<Uint8List> stripMetadata(Uint8List bytes) async {
    cleaned.add(bytes);
    if (error case final error?) throw error;
    return Uint8List.fromList([9, ...bytes]);
  }
}

/// A minimal JPEG with an EXIF segment holding "GPS".
final _jpegWithExif = Uint8List.fromList([
  0xFF, 0xD8, //
  0xFF, 0xE1, 0, 10, 0x45, 0x78, 0x69, 0x66, 0, 0, 0x47, 0x50, //
  0xFF, 0xDA, 0, 2, 1, 2, 0xFF, 0xD9,
]);

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

final _scan = PickedDocument(
  fileName: 'Titre de propriété - scan du 2026-10-01 18h42.pdf',
  mimeType: 'application/pdf',
  bytes: _bytes,
);

void main() {
  late MockPropertyRepository repository;
  late _MockDocumentPicker picker;
  late List<Uri> opened;
  late bool openResult;

  setUpAll(() {
    registerFallbackValue(DocumentSource.files);
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

  DocumentsCubit build({
    List<PropertyDocument> documents = const [],
    PhotoProcessor? processor,
  }) => DocumentsCubit(
    propertyRepository: repository,
    documentPicker: picker,
    photoProcessor: processor,
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
        act: (cubit) =>
            cubit.pick(DocumentSource.files, kind: DocumentKind.other),
        expect: () => const [picking, initial],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'ignores a second tap while the picker is open',
        build: build,
        act: (cubit) async {
          final first = cubit.pick(
            DocumentSource.photos,
            kind: DocumentKind.other,
          );
          await cubit.pick(DocumentSource.files, kind: DocumentKind.other);
          await first;
        },
        verify: (_) => verify(() => picker.pick(any())).called(1),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'uploads a valid file as a document of the given kind',
        build: build,
        act: (cubit) => cubit.pick(
          DocumentSource.photos,
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

      group('removes the metadata of an image before the upload', () {
        Uint8List uploaded() =>
            verify(
                  () => repository.uploadDocument(
                    ownerId: any(named: 'ownerId'),
                    propertyId: any(named: 'propertyId'),
                    kind: any(named: 'kind'),
                    fileName: any(named: 'fileName'),
                    bytes: captureAny(named: 'bytes'),
                    mimeType: any(named: 'mimeType'),
                  ),
                ).captured.single
                as Uint8List;

        test('with the photo processor of the app by default', () async {
          when(() => picker.pick(any())).thenAnswer(
            (_) async => XFile.fromData(_jpegWithExif, path: 'id.jpg'),
          );
          final cubit = build();
          await cubit.pick(
            DocumentSource.photos,
            kind: DocumentKind.identityDocument,
          );
          expect(uploaded(), [0xFF, 0xD8, 0xFF, 0xDA, 0, 2, 1, 2, 0xFF, 0xD9]);
        });

        test('never changes a PDF', () async {
          final processor = _FakeProcessor();
          when(
            () => picker.pick(any()),
          ).thenAnswer((_) async => XFile.fromData(_bytes, path: 'titre.pdf'));
          await build(processor: processor)
              .pick(DocumentSource.files, kind: DocumentKind.titleDeed);
          expect(processor.cleaned, isEmpty);
          expect(uploaded(), _bytes);
        });

        test('uploads the cleaned image', () async {
          final processor = _FakeProcessor();
          await build(processor: processor)
              .pick(DocumentSource.photos, kind: DocumentKind.identityDocument);
          expect(processor.cleaned, [_bytes]);
          expect(uploaded(), [9, ..._bytes]);
        });

        blocTest<DocumentsCubit, DocumentsState>(
          'keeps an image that cannot be parsed, and reports it',
          build: () =>
              build(processor: _FakeProcessor(const FormatException())),
          act: (cubit) => cubit.pick(
            DocumentSource.photos,
            kind: DocumentKind.identityDocument,
          ),
          errors: () => [isA<FormatException>()],
          verify: (_) => expect(uploaded(), _bytes),
        );
      });

      blocTest<DocumentsCubit, DocumentsState>(
        'rejects an unsupported type',
        setUp: () => when(
          () => picker.pick(any()),
        ).thenAnswer((_) async => XFile.fromData(_bytes, path: 'notes.docx')),
        build: build,
        act: (cubit) =>
            cubit.pick(DocumentSource.files, kind: DocumentKind.other),
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
        act: (cubit) =>
            cubit.pick(DocumentSource.files, kind: DocumentKind.other),
        skip: 2,
        expect: () => [initial.copyWith(notice: DocumentsNotice.fileTooLarge)],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the access was refused',
        setUp: () => when(() => picker.pick(any()))
            .thenThrow(DocumentAccessDenied(PlatformException(code: 'denied'))),
        build: build,
        act: (cubit) =>
            cubit.pick(DocumentSource.photos, kind: DocumentKind.other),
        skip: 2,
        expect: () => [initial.copyWith(notice: DocumentsNotice.accessDenied)],
        errors: () => [isA<DocumentAccessDenied>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'tells when the file cannot be picked',
        setUp: () =>
            when(() => picker.pick(any())).thenThrow(Exception('oops')),
        build: build,
        act: (cubit) =>
            cubit.pick(DocumentSource.files, kind: DocumentKind.other),
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
        act: (cubit) =>
            cubit.pick(DocumentSource.photos, kind: DocumentKind.other),
        expect: () => const <DocumentsState>[],
        verify: (_) => verifyNever(() => picker.pick(any())),
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing on a locked dossier',
        build: build,
        seed: () => const DocumentsState(property: _locked, documents: []),
        act: (cubit) =>
            cubit.pick(DocumentSource.photos, kind: DocumentKind.other),
        expect: () => const <DocumentsState>[],
        verify: (_) => verifyNever(() => picker.pick(any())),
      );
    });

    group('addScan', () {
      blocTest<DocumentsCubit, DocumentsState>(
        'uploads the PDF of a scan',
        build: () => build(documents: const [_titleDeed]),
        act: (cubit) =>
            cubit.addScan(_scan, kind: DocumentKind.identityDocument),
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [_titleDeed],
            uploading: _scan,
          ),
          const DocumentsState(
            property: testProperty,
            documents: [_titleDeed, _identity],
            notice: DocumentsNotice.uploaded,
            noticeCount: 1,
          ),
        ],
        verify: (_) => verify(
          () => repository.uploadDocument(
            ownerId: 'user-id',
            propertyId: 'property-id',
            kind: DocumentKind.identityDocument,
            fileName: 'Titre de propriété - scan du 2026-10-01 18h42.pdf',
            bytes: _bytes,
            mimeType: 'application/pdf',
          ),
        ).called(1),
      );

      test('waits until the current change is over', () async {
        final cubit = build()
          ..emit(
            const DocumentsState(
              property: testProperty,
              documents: [],
              busyDocumentIds: {'d1'},
            ),
          );
        final adding = cubit.addScan(_scan, kind: DocumentKind.plan);
        await Future<void>.delayed(Duration.zero);
        verifyNever(
          () => repository.uploadDocument(
            ownerId: any(named: 'ownerId'),
            propertyId: any(named: 'propertyId'),
            kind: any(named: 'kind'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            mimeType: any(named: 'mimeType'),
          ),
        );

        cubit.emit(cubit.state.copyWith(busyDocumentIds: const {}));
        await adding;
        expect(cubit.state.documents, [_identity]);
      });

      test('drops nothing when closed while waiting', () async {
        final cubit = build()
          ..emit(
            const DocumentsState(
              property: testProperty,
              documents: [],
              busyDocumentIds: {'d1'},
            ),
          );
        final adding = cubit.addScan(_scan, kind: DocumentKind.plan);
        cubit.emit(cubit.state.copyWith(busyDocumentIds: const {}));
        await cubit.close();
        await adding;
        expect(cubit.state.isUploading, isFalse);
      });

      blocTest<DocumentsCubit, DocumentsState>(
        'does nothing on a locked dossier',
        build: build,
        seed: () => const DocumentsState(property: _locked, documents: []),
        act: (cubit) => cubit.addScan(_scan, kind: DocumentKind.plan),
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
        act: (cubit) => cubit.addScan(_scan, kind: DocumentKind.titleDeed),
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [],
            uploading: _scan,
          ),
          DocumentsState(
            property: testProperty,
            documents: const [_titleDeed],
            failedUploads: [
              FailedUpload(file: _scan, kind: DocumentKind.titleDeed),
            ],
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
        build: () => build(documents: const [_identity]),
        act: (cubit) => cubit.addScan(_scan, kind: DocumentKind.titleDeed),
        skip: 1,
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [_identity],
            failedUploads: [
              FailedUpload(file: _scan, kind: DocumentKind.titleDeed),
            ],
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
          await cubit.pick(DocumentSource.photos, kind: DocumentKind.other);
          // The lost upload went through after all.
          when(() => repository.getDocuments(any()))
              .thenAnswer((_) async => [stored]);
          await cubit.pick(DocumentSource.photos, kind: DocumentKind.other);
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
          await cubit.pick(DocumentSource.photos, kind: DocumentKind.other);
          await cubit.pick(DocumentSource.photos, kind: DocumentKind.other);
        },
        verify: (cubit) {
          expect(uploads, 2);
          expect(cubit.state.documents, [_titleDeed, _identity]);
          expect(cubit.state.failedUploads, isEmpty);
        },
        errors: () => [isA<TimeoutException>()],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'keeps a failed scan to retry it',
        build: build,
        act: (cubit) async {
          await cubit.addScan(_scan, kind: DocumentKind.titleDeed);
          expect(cubit.state.failedUploads, [
            FailedUpload(file: _scan, kind: DocumentKind.titleDeed),
          ]);
          await cubit.retryUpload(cubit.state.failedUploads.single);
        },
        verify: (cubit) {
          expect(uploads, 2);
          verify(
            () => repository.uploadDocument(
              ownerId: 'user-id',
              propertyId: 'property-id',
              kind: DocumentKind.titleDeed,
              fileName: _scan.fileName,
              bytes: _bytes,
              mimeType: 'application/pdf',
            ),
          ).called(2);
          expect(cubit.state.failedUploads, isEmpty);
          expect(cubit.state.notice, DocumentsNotice.uploaded);
        },
        errors: () => [isA<TimeoutException>()],
      );
    });

    group('failed uploads', () {
      final failed = FailedUpload(file: _scan, kind: DocumentKind.titleDeed);
      final other = FailedUpload(file: _photo, kind: DocumentKind.other);

      blocTest<DocumentsCubit, DocumentsState>(
        'discardFailedUpload gives up a file',
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [],
          failedUploads: [failed, other],
        ),
        act: (cubit) => cubit.discardFailedUpload(failed),
        expect: () => [
          DocumentsState(
            property: testProperty,
            documents: const [],
            failedUploads: [other],
          ),
        ],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'cannot change while busy',
        build: build,
        seed: () => DocumentsState(
          property: testProperty,
          documents: const [],
          uploading: _photo,
          failedUploads: [failed],
        ),
        act: (cubit) async {
          cubit.discardFailedUpload(failed);
          await cubit.retryUpload(failed);
        },
        expect: () => const <DocumentsState>[],
      );

      blocTest<DocumentsCubit, DocumentsState>(
        'retryUpload does nothing on a locked dossier',
        build: build,
        seed: () => DocumentsState(
          property: _locked,
          documents: const [],
          failedUploads: [failed],
        ),
        act: (cubit) => cubit.retryUpload(failed),
        expect: () => const <DocumentsState>[],
      );
    });

    blocTest<DocumentsCubit, DocumentsState>(
      'delete does nothing on a locked dossier',
      build: build,
      seed: () =>
          const DocumentsState(property: _locked, documents: [_identity]),
      act: (cubit) => cubit.delete(_identity),
      expect: () => const <DocumentsState>[],
    );

    blocTest<DocumentsCubit, DocumentsState>(
      'submissionBlocked shows the documents needed to send, once',
      build: build,
      act: (cubit) => cubit
        ..submissionBlocked()
        ..submissionBlocked(),
      expect: () => const [
        DocumentsState(
          property: testProperty,
          documents: [],
          showsSubmissionErrors: true,
        ),
      ],
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

  group('reuse', () {
    const other = PropertyDocument(
      id: 'other',
      propertyId: 'garage',
      kind: DocumentKind.titleDeed,
      storagePath: 'user-id/garage/acte.pdf',
    );
    const copy = PropertyDocument(
      id: 'copy',
      propertyId: 'property-id',
      kind: DocumentKind.titleDeed,
      storagePath: 'user-id/property-id/acte.pdf',
    );

    DocumentsCubit build({Property property = testProperty}) => DocumentsCubit(
      propertyRepository: repository,
      documentPicker: picker,
      openUrl: (uri) async => true,
      property: property,
    );

    test('copies the document of another property', () async {
      when(
        () => repository.copyDocument(
          other,
          ownerId: 'user-id',
          toPropertyId: 'property-id',
        ),
      ).thenAnswer((_) async => copy);
      final cubit = build();
      await cubit.reuse(other);
      expect(cubit.state.documents, [copy]);
      expect(cubit.state.notice, DocumentsNotice.uploaded);
      expect(cubit.state.picking, isFalse);
      await cubit.close();
    });

    test('reloads after a failure', () async {
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) async => throw const DocumentUploadFailure());
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => [copy]);
      final cubit = build();
      await cubit.reuse(other);
      expect(cubit.state.documents, [copy]);
      expect(cubit.state.notice, DocumentsNotice.reuseFailed);
      await cubit.close();
    });

    test('does nothing on a locked dossier or once closed', () async {
      final locked = build(property: _locked);
      await locked.reuse(other);
      expect(locked.state.documents, isEmpty);
      await locked.close();

      final closing = Completer<PropertyDocument>();
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) => closing.future);
      final cubit = build();
      final reusing = cubit.reuse(other);
      await cubit.close();
      closing.complete(copy);
      await reusing;

      final failing = Completer<PropertyDocument>();
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) => failing.future);
      final other2 = build();
      final reusing2 = other2.reuse(other);
      await other2.close();
      failing.completeError(const DocumentUploadFailure());
      await reusing2;
    });
  });
}
