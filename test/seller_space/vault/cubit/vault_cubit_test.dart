import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import '../../fixtures.dart';
import '../vault_fixtures.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _Processor implements PhotoProcessor {
  bool fail = false;

  @override
  Future<ProcessedPhoto> process(Uint8List bytes, {double? tiltDegrees}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> stripMetadata(Uint8List bytes) async {
    if (fail) throw const FormatException('bad');
    return Uint8List.fromList([...bytes, 0]);
  }
}

void main() {
  late MockPropertyRepository repository;
  late MockValuationRepository valuations;
  late _MockDocumentPicker picker;
  late _Processor processor;
  late List<Uri> opened;
  late List<String> shared;
  late bool openResult;
  late Map<String, List<PropertyDocument>> changed;

  final file = PickedDocument(
    fileName: 'dpe.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  const target = VaultAddTarget(
    propertyId: 'property-id',
    kind: DocumentKind.dpe,
  );

  setUpAll(() {
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(document('fallback'));
    registerFallbackValue(DocumentSource.files);
    registerFallbackValue(<DocumentVisibility>{});
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    repository = MockPropertyRepository();
    valuations = MockValuationRepository();
    picker = _MockDocumentPicker();
    processor = _Processor();
    opened = [];
    shared = [];
    openResult = true;
    changed = {};
    when(() => repository.getDocumentsOf(any())).thenAnswer((_) async => []);
    when(() => repository.getOwners(any())).thenAnswer((_) async => [sophie]);
    when(() => valuations.getLatestValuation(any()))
        .thenAnswer((_) async => testValuation);
  });

  VaultCubit build() => VaultCubit(
    propertyRepository: repository,
    valuationRepository: valuations,
    documentPicker: picker,
    openUrl: (uri) async {
      opened.add(uri);
      return openResult;
    },
    share: (bytes, name, mime) async =>
        shared.add('$name $mime ${bytes.length}'),
    photoProcessor: processor,
    onDocumentsChanged: (id, documents) => changed[id] = documents,
    timeout: const Duration(milliseconds: 50),
  );

  /// A cubit showing [sentProperty] with [documents].
  Future<VaultCubit> shown([
    List<PropertyDocument> documents = const [],
  ]) async {
    when(() => repository.getDocumentsOf(any()))
        .thenAnswer((_) async => documents);
    final cubit = build();
    await cubit.show(const VaultTarget.property('property-id'), const [
      sentProperty,
    ]);
    return cubit;
  }

  group('show', () {
    blocTest<VaultCubit, VaultState>(
      'loads the documents, owners and valuation',
      build: build,
      act: (cubit) => cubit.show(
        const VaultTarget.property('property-id'),
        const [sentProperty, draftProperty],
      ),
      expect: () => [
        isA<VaultState>().having(
          (s) => s.status,
          'status',
          VaultStatus.loading,
        ),
        isA<VaultState>()
            .having((s) => s.status, 'status', VaultStatus.success)
            .having((s) => s.owners.keys, 'owners', ['property-id', 'draft-id'])
            .having((s) => s.valuations.keys, 'valuations', ['property-id']),
      ],
    );

    blocTest<VaultCubit, VaultState>(
      'without a valuation yet',
      setUp: () =>
          when(() => valuations.getLatestValuation(any()))
              .thenAnswer((_) async => null),
      build: build,
      act: (cubit) => cubit.show(
        const VaultTarget.property('property-id'),
        const [sentProperty],
      ),
      verify: (cubit) => expect(cubit.state.valuations, isEmpty),
    );

    blocTest<VaultCubit, VaultState>(
      'fails',
      setUp: () =>
          when(() => repository.getDocumentsOf(any()))
              .thenThrow(const PropertyLoadFailure()),
      build: build,
      act: (cubit) => cubit.show(const VaultTarget.lot('lot'), const []),
      errors: () => [isA<PropertyLoadFailure>()],
      verify: (cubit) => expect(cubit.state.status, VaultStatus.failure),
    );

    test('an answer for another target is dropped', () async {
      final gate = Completer<List<PropertyDocument>>();
      when(() => repository.getDocumentsOf(any()))
          .thenAnswer((_) => gate.future);
      final cubit = build();
      final first = cubit.show(
        const VaultTarget.property('property-id'),
        const [sentProperty],
      );
      when(() => repository.getDocumentsOf(any())).thenAnswer((_) async => []);
      await cubit.show(const VaultTarget.property('draft-id'), const [
        draftProperty,
      ]);
      gate.complete([document('a')]);
      await first;
      expect(cubit.state.target, const VaultTarget.property('draft-id'));
      expect(cubit.state.documents, isEmpty);
      // Also for a failure.
      final failing = Completer<List<PropertyDocument>>();
      when(() => repository.getDocumentsOf(any()))
          .thenAnswer((_) => failing.future);
      final second = cubit.refresh();
      when(() => repository.getDocumentsOf(any())).thenAnswer((_) async => []);
      await cubit.show(const VaultTarget.lot('lot'), const []);
      failing.completeError(const PropertyLoadFailure());
      await second;
      expect(cubit.state.status, isNot(VaultStatus.failure));
      await cubit.close();
    });

    test('refresh keeps the list shown and takes the new properties', () async {
      final cubit = await shown([document('a')]);
      final states = <VaultStatus>[];
      final subscription = cubit.stream.listen((s) => states.add(s.status));
      await cubit.refresh(properties: const [sentProperty]);
      expect(states, everyElement(VaultStatus.success));
      await subscription.cancel();
      await cubit.close();
      // Nothing to refresh before a target.
      final empty = build();
      await empty.refresh();
      expect(empty.state.status, VaultStatus.initial);
      await empty.close();
    });
  });

  group('pickAndAdd', () {
    XFile pdf([String name = 'a.pdf']) =>
        XFile.fromData(Uint8List.fromList([1]), name: name, path: name);

    /// The files uploaded.
    List<(String, List<int>)> uploading() {
      final sent = <(String, List<int>)>[];
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: any(named: 'title'),
          ownerRef: any(named: 'ownerRef'),
        ),
      ).thenAnswer((invocation) async {
        sent.add((
          invocation.namedArguments[#fileName] as String,
          invocation.namedArguments[#bytes] as Uint8List,
        ));
        return document('new${sent.length}');
      });
      return sent;
    }

    test('sends a PDF as it is', () async {
      final sent = uploading();
      when(() => picker.pick(any())).thenAnswer((_) async => pdf('dir/a.pdf'));
      final cubit = await shown();
      await cubit.pickAndAdd(target, DocumentSource.files);
      expect(sent.single.$1, 'a.pdf');
      expect(sent.single.$2, [1]);
      expect(cubit.state.busy, isFalse);
    });

    test('removes the metadata of an image', () async {
      final sent = uploading();
      when(() => picker.pick(any())).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          name: 'a.jpg',
          path: 'a.jpg',
        ),
      );
      final cubit = await shown();
      await cubit.pickAndAdd(target, DocumentSource.photos);
      expect(sent.single.$2, [1, 0]);
      processor.fail = true;
      await cubit.pickAndAdd(target, DocumentSource.photos);
      expect(sent, hasLength(1));
      expect(cubit.state.notice, VaultNotice.metadataUnremovable);
    });

    test('refuses a file of another type, or too large', () async {
      final sent = uploading();
      final cubit = await shown();
      when(() => picker.pick(any())).thenAnswer((_) async => pdf('a.txt'));
      await cubit.pickAndAdd(target, DocumentSource.files);
      expect(cubit.state.notice, VaultNotice.unsupportedType);
      when(() => picker.pick(any())).thenAnswer(
        (_) async => XFile.fromData(
          Uint8List(DocumentsCubit.maxFileBytes + 1),
          name: 'big.pdf',
          path: 'big.pdf',
        ),
      );
      await cubit.pickAndAdd(target, DocumentSource.files);
      expect(cubit.state.notice, VaultNotice.fileTooLarge);
      expect(sent, isEmpty);
    });

    test('reports a refused access, a failure, a cancellation', () async {
      final sent = uploading();
      final cubit = await shown();
      when(() => picker.pick(any()))
          .thenThrow(const DocumentAccessDenied('no'));
      await cubit.pickAndAdd(target, DocumentSource.photos);
      expect(cubit.state.notice, VaultNotice.accessDenied);
      when(() => picker.pick(any())).thenThrow(Exception('x'));
      await cubit.pickAndAdd(target, DocumentSource.photos);
      expect(cubit.state.notice, VaultNotice.pickFailed);
      cubit.noticeShown();
      when(() => picker.pick(any())).thenAnswer((_) async => null);
      await cubit.pickAndAdd(target, DocumentSource.photos);
      expect(cubit.state.notice, isNull);
      expect(sent, isEmpty);
    });

    test('one pick at a time; nothing once closed', () async {
      final sent = uploading();
      final gate = Completer<XFile?>();
      when(() => picker.pick(any())).thenAnswer((_) => gate.future);
      final cubit = await shown();
      final first = cubit.pickAndAdd(target, DocumentSource.files);
      await cubit.pickAndAdd(target, DocumentSource.files);
      verify(() => picker.pick(any())).called(1);
      await cubit.close();
      gate.complete(pdf());
      await first;
      expect(sent, isEmpty);
    });
  });

  group('add', () {
    void uploads(PropertyDocument document) => when(
      () => repository.uploadDocument(
        ownerId: any(named: 'ownerId'),
        propertyId: any(named: 'propertyId'),
        kind: any(named: 'kind'),
        fileName: any(named: 'fileName'),
        bytes: any(named: 'bytes'),
        mimeType: any(named: 'mimeType'),
        title: any(named: 'title'),
        ownerRef: any(named: 'ownerRef'),
      ),
    ).thenAnswer((_) async => document);

    test('uploads the file and records it', () async {
      final added = document('new', kind: DocumentKind.dpe, added: true);
      uploads(added);
      final cubit = await shown();
      await cubit.add(target, file);
      expect(cubit.state.documents, [added]);
      expect(cubit.state.notice, VaultNotice.uploaded);
      expect(changed['property-id'], [added]);
      verify(
        () => repository.uploadDocument(
          ownerId: 'user-id',
          propertyId: 'property-id',
          kind: DocumentKind.dpe,
          fileName: 'dpe.pdf',
          bytes: file.bytes,
          mimeType: 'application/pdf',
        ),
      ).called(1);
    });

    test('ignores an unknown property', () async {
      final cubit = await shown();
      await cubit.add(
        const VaultAddTarget(propertyId: 'nope', kind: DocumentKind.dpe),
        file,
      );
      expect(cubit.state.busy, isFalse);
    });

    test('keeps a failed upload to retry, then discards it', () async {
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: any(named: 'title'),
          ownerRef: any(named: 'ownerRef'),
        ),
      ).thenThrow(const DocumentUploadFailure());
      when(() => repository.getDocuments(any()))
          .thenThrow(const PropertyLoadFailure());
      final cubit = await shown();
      await cubit.add(target, file);
      expect(cubit.state.failedUpload!.file, file);
      expect(cubit.state.notice, VaultNotice.uploadFailed);
      cubit.discardFailedUpload();
      expect(cubit.state.failedUpload, isNull);
      await cubit.retryUpload();
    });

    test('finds an upload whose answer was lost, on retry', () async {
      var calls = 0;
      final stored = document('new', kind: DocumentKind.dpe).toJson()
        ..['file_name'] = 'dpe.pdf'
        ..['size_bytes'] = 3;
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: any(named: 'title'),
          ownerRef: any(named: 'ownerRef'),
        ),
      ).thenAnswer((_) async {
        calls++;
        throw TimeoutException('lost');
      });
      when(() => repository.getDocuments(any())).thenAnswer(
        (_) async => calls == 1 ? [] : [PropertyDocument.fromJson(stored)],
      );
      final cubit = await shown();
      await cubit.add(target, file);
      expect(cubit.state.failedUpload, isNotNull);
      await cubit.retryUpload();
      expect(cubit.state.failedUpload, isNull);
      expect(cubit.state.documents.single.id, 'new');
      expect(cubit.state.notice, VaultNotice.uploaded);
    });

    test('waits for the current change', () async {
      final gate = Completer<XFile?>();
      when(() => picker.pick(any())).thenAnswer((_) => gate.future);
      uploads(document('new'));
      final cubit = await shown();
      final picking = cubit.pickAndAdd(target, DocumentSource.files);
      final adding = cubit.add(target, file);
      gate.complete(null);
      await picking;
      await adding;
      expect(cubit.state.documents.single.id, 'new');
    });

    test('a replacement of a rejected document keeps the old one', () async {
      final old = document(
        'old',
        kind: DocumentKind.propertyTax,
        status: DocumentStatus.rejected,
        title: 'Taxe 2025',
      );
      uploads(document('new', kind: DocumentKind.propertyTax));
      when(
        () => repository.replaceDocument(
          oldId: any(named: 'oldId'),
          newId: any(named: 'newId'),
        ),
      ).thenAnswer((_) async {});
      final cubit = await shown([old]);
      await cubit.add(target, file, replacing: old);
      expect(cubit.state.documentById('old')!.replacedBy, 'new');
      expect(cubit.state.notice, VaultNotice.replaced);
      verify(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
          title: 'Taxe 2025',
          ownerRef: any(named: 'ownerRef'),
        ),
      ).called(1);
    });

    test('a replacement of an unverified addition deletes it', () async {
      final old = document('old', added: true);
      uploads(document('new'));
      when(
        () => repository.replaceDocument(
          oldId: any(named: 'oldId'),
          newId: any(named: 'newId'),
        ),
      ).thenAnswer((_) async {});
      when(() => repository.deleteDocument(any())).thenAnswer((_) async {});
      final cubit = await shown([old]);
      await cubit.add(target, file, replacing: old);
      expect(cubit.state.documentById('old'), isNull);
    });

    test('a replacement in a draft deletes the old document', () async {
      final old = document('old', propertyId: 'draft-id');
      uploads(document('new', propertyId: 'draft-id'));
      when(() => repository.deleteDocument(any())).thenAnswer((_) async {});
      final cubit = build();
      when(() => repository.getDocumentsOf(any()))
          .thenAnswer((_) async => [old]);
      await cubit.show(const VaultTarget.property('draft-id'), const [
        draftProperty,
      ]);
      await cubit.add(
        const VaultAddTarget(propertyId: 'draft-id', kind: DocumentKind.other),
        file,
        replacing: old,
      );
      expect(cubit.state.documentById('old'), isNull);
      verifyNever(
        () => repository.replaceDocument(
          oldId: any(named: 'oldId'),
          newId: any(named: 'newId'),
        ),
      );
    });

    test('a failed replacement keeps both documents', () async {
      final old = document('old', status: DocumentStatus.rejected);
      uploads(document('new'));
      when(
        () => repository.replaceDocument(
          oldId: any(named: 'oldId'),
          newId: any(named: 'newId'),
        ),
      ).thenThrow(const PropertySaveFailure());
      final cubit = await shown([old]);
      await cubit.add(target, file, replacing: old);
      expect(cubit.state.documents, hasLength(2));
      expect(cubit.state.documentById('old')!.replacedBy, isNull);
    });
  });

  group('reuse', () {
    test('copies a document of another property', () async {
      final copy = document('copy');
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) async => copy);
      final cubit = await shown();
      await cubit.reuse(target, document('source', propertyId: 'draft-id'));
      expect(cubit.state.documents, [copy]);
      expect(cubit.state.notice, VaultNotice.uploaded);
      // Unknown property: nothing.
      await cubit.reuse(
        const VaultAddTarget(propertyId: 'nope', kind: DocumentKind.dpe),
        copy,
      );
    });

    test('reloads after a failure', () async {
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenThrow(const DocumentUploadFailure());
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => [document('copy')]);
      final cubit = await shown();
      await cubit.reuse(target, document('source'));
      expect(cubit.state.documents.single.id, 'copy');
      expect(cubit.state.notice, VaultNotice.reuseFailed);
      when(() => repository.getDocuments(any()))
          .thenThrow(const PropertyLoadFailure());
      await cubit.reuse(target, document('source'));
      expect(cubit.state.busy, isFalse);
    });
  });

  group('changes', () {
    test('rename, share settings and delete', () async {
      final doc = document('a', added: true);
      when(() => repository.renameDocument(any(), any()))
          .thenAnswer((_) async => doc.withTitle('Nouveau'));
      when(() => repository.setDocumentVisibility(any(), any()))
          .thenAnswer((_) async => {DocumentVisibility.buyers});
      when(() => repository.deleteDocument(any())).thenAnswer((_) async {});
      final cubit = await shown([doc, document('b')]);
      await cubit.rename(doc, 'Nouveau');
      expect(cubit.state.documentById('a')!.title, 'Nouveau');
      await cubit.setVisibility(doc, {DocumentVisibility.buyers});
      expect(cubit.state.documentById('a')!.visibility, {
        DocumentVisibility.buyers,
      });
      await cubit.delete(doc);
      expect(cubit.state.documentById('a'), isNull);
      expect(cubit.state.notice, VaultNotice.deleted);
      // Unknown property: nothing.
      await cubit.delete(document('x', propertyId: 'nope'));
    });

    test('a failure reloads the documents', () async {
      final doc = document('a');
      when(() => repository.renameDocument(any(), any()))
          .thenThrow(const PropertySaveFailure());
      when(() => repository.deleteDocument(any()))
          .thenThrow(const PropertyDeleteFailure());
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => [document('a', title: 'Serveur')]);
      final cubit = await shown([doc]);
      await cubit.rename(doc, 'x');
      expect(cubit.state.notice, VaultNotice.saveFailed);
      expect(cubit.state.documentById('a')!.title, 'Serveur');
      await cubit.delete(doc);
      expect(cubit.state.notice, VaultNotice.deleteFailed);
      when(() => repository.getDocuments(any()))
          .thenThrow(const PropertyLoadFailure());
      await cubit.rename(doc, 'x');
      expect(cubit.state.busyDocumentIds, isEmpty);
    });

    test('one change at a time per document', () async {
      final gate = Completer<PropertyDocument>();
      final doc = document('a');
      when(() => repository.renameDocument(any(), any()))
          .thenAnswer((_) => gate.future);
      final cubit = await shown([doc]);
      final first = cubit.rename(doc, 'x');
      await cubit.rename(doc, 'y');
      gate.complete(doc);
      await first;
      verify(() => repository.renameDocument('a', 'x')).called(1);
      verifyNever(() => repository.renameDocument('a', 'y'));
    });
  });

  group('deliver', () {
    test('opens a document through a signed URL', () async {
      when(
        () => repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) async => 'https://signed/a');
      final cubit = await shown([document('a')]);
      await cubit.open(document('a'));
      expect(opened, [Uri.parse('https://signed/a')]);
      openResult = false;
      await cubit.open(document('a'));
      expect(cubit.state.notice, VaultNotice.openFailed);
    });

    test('opens the report of a valuation', () async {
      when(
        () =>
            valuations.getReportUrl(any(), expiresIn: any(named: 'expiresIn')),
      ).thenAnswer((_) async => 'https://signed/report');
      final cubit = await shown();
      await cubit.openReport(testValuation);
      expect(opened.single.path, '/report');
    });

    test('shares a downloaded document', () async {
      when(() => repository.downloadDocument(any()))
          .thenAnswer((_) async => Uint8List.fromList([1, 2]));
      final cubit = await shown([document('a')]);
      await cubit.share(document('a'));
      expect(shared, ['a.pdf application/pdf 2']);
      await cubit.share(
        const PropertyDocument(
          id: 'b',
          propertyId: 'property-id',
          kind: DocumentKind.other,
          storagePath: 'u/p/b.bin',
        ),
      );
      expect(shared.last, 'b.bin application/octet-stream 2');
      when(() => repository.downloadDocument(any()))
          .thenThrow(const PropertyLoadFailure());
      await cubit.share(document('a'));
      expect(cubit.state.notice, VaultNotice.shareFailed);
    });

    test('one delivery at a time', () async {
      final gate = Completer<String>();
      when(
        () => repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) => gate.future);
      final cubit = await shown([document('a')]);
      final first = cubit.open(document('a'));
      await cubit.open(document('a'));
      gate.complete('https://x');
      await first;
      expect(opened, hasLength(1));
    });

    test('nothing is emitted once closed', () async {
      final gate = Completer<String>();
      when(
        () => repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) => gate.future);
      final cubit = await shown([document('a')]);
      final first = cubit.open(document('a'));
      await cubit.close();
      gate.complete('https://x');
      await first;
    });
  });

  test('state helpers', () {
    const state = VaultState(properties: [sentProperty]);
    expect(state.propertyById('nope'), isNull);
    expect(state.documentById('nope'), isNull);
    expect(const VaultTarget.lot('l').isLot, isTrue);
    expect(
      VaultFailedUpload(target: target, file: file),
      VaultFailedUpload(target: target, file: file),
    );
  });
}
