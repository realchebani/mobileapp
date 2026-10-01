import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/cubit/document_scan_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _MockScanPdfBuilder extends Mock implements ScanPdfBuilder;

XFile _file(int byte) =>
    XFile.fromData(Uint8List.fromList([byte]), path: 'page-$byte.jpg');

ScannedPage _page(int id) =>
    ScannedPage(id: id, bytes: Uint8List.fromList([id]));

final _pdf = Uint8List.fromList([9, 9]);

void main() {
  late _MockDocumentPicker picker;
  late _MockScanPdfBuilder pdfBuilder;

  setUp(() {
    picker = _MockDocumentPicker();
    pdfBuilder = _MockScanPdfBuilder();
    when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
        .thenAnswer((_) async => [_file(0), _file(1)]);
    when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => _pdf);
  });

  DocumentScanCubit build() =>
      DocumentScanCubit(documentPicker: picker, pdfBuilder: pdfBuilder);

  group(DocumentScanCubit, () {
    test('starts with no page', () {
      final state = build().state;
      expect(state, const DocumentScanState());
      expect(state.isBusy, isFalse);
      expect(state.isFull, isFalse);
    });

    group('addPages', () {
      blocTest<DocumentScanCubit, DocumentScanState>(
        'adds the scanned pages after the others',
        build: build,
        seed: () => DocumentScanState(pages: [_page(7)]),
        act: (cubit) => cubit.addPages(),
        expect: () => [
          DocumentScanState(
            pages: [_page(7)],
            status: DocumentScanStatus.capturing,
          ),
          DocumentScanState(pages: [_page(7), _page(0), _page(1)], captures: 1),
        ],
        verify: (cubit) {
          verify(
            () => picker.scanPages(maxPages: DocumentScanCubit.maxPages - 1),
          ).called(1);
          expect(cubit.state.pages[1].bytes, [0]);
        },
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'counts a cancelled scan',
        setUp: () =>
            when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
                .thenAnswer((_) async => null),
        build: build,
        act: (cubit) => cubit.addPages(),
        skip: 1,
        expect: () => const [DocumentScanState(captures: 1)],
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'keeps at most ${DocumentScanCubit.maxPages} pages',
        build: build,
        seed: () => DocumentScanState(
          pages: [
            for (var i = 0; i < DocumentScanCubit.maxPages - 1; i++)
              _page(100 + i),
          ],
        ),
        act: (cubit) => cubit.addPages(),
        verify: (cubit) {
          expect(cubit.state.pages, hasLength(DocumentScanCubit.maxPages));
          expect(cubit.state.isFull, isTrue);
          expect(cubit.state.notice, DocumentScanNotice.truncated);
        },
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'does nothing once full',
        build: build,
        seed: () => DocumentScanState(
          pages: [
            for (var i = 0; i < DocumentScanCubit.maxPages; i++) _page(i),
          ],
        ),
        act: (cubit) => cubit.addPages(),
        expect: () => const <DocumentScanState>[],
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'does nothing while busy',
        build: build,
        seed: () =>
            const DocumentScanState(status: DocumentScanStatus.building),
        act: (cubit) => cubit.addPages(),
        expect: () => const <DocumentScanState>[],
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'tells when the camera access was refused',
        setUp: () => when(
          () => picker.scanPages(maxPages: any(named: 'maxPages')),
        ).thenThrow(DocumentAccessDenied(PlatformException(code: 'denied'))),
        build: build,
        act: (cubit) => cubit.addPages(),
        skip: 1,
        expect: () => const [
          DocumentScanState(
            captures: 1,
            notice: DocumentScanNotice.accessDenied,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<DocumentAccessDenied>()],
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'tells when the scan failed',
        setUp: () =>
            when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
                .thenThrow(Exception('boom')),
        build: build,
        act: (cubit) => cubit.addPages(),
        skip: 1,
        expect: () => const [
          DocumentScanState(
            captures: 1,
            notice: DocumentScanNotice.captureFailed,
            noticeCount: 1,
          ),
        ],
        errors: () => [isA<Exception>()],
      );

      test('ignores the pages once closed', () async {
        final pages = Completer<List<XFile>?>();
        when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
            .thenAnswer((_) => pages.future);
        final cubit = build();
        final adding = cubit.addPages();
        await cubit.close();
        pages.complete([_file(1)]);
        await adding;
        expect(cubit.state.pages, isEmpty);
      });
    });

    blocTest<DocumentScanCubit, DocumentScanState>(
      'removePage removes a page',
      build: build,
      seed: () => DocumentScanState(pages: [_page(1), _page(2), _page(3)]),
      act: (cubit) => cubit.removePage(2),
      expect: () => [
        DocumentScanState(pages: [_page(1), _page(3)]),
      ],
    );

    blocTest<DocumentScanCubit, DocumentScanState>(
      'movePage moves a page',
      build: build,
      seed: () => DocumentScanState(pages: [_page(1), _page(2), _page(3)]),
      act: (cubit) => cubit
        ..movePage(0, 2)
        ..movePage(2, 0),
      expect: () => [
        DocumentScanState(pages: [_page(2), _page(3), _page(1)]),
        DocumentScanState(pages: [_page(1), _page(2), _page(3)]),
      ],
    );

    blocTest<DocumentScanCubit, DocumentScanState>(
      'pages cannot change while busy',
      build: build,
      seed: () => DocumentScanState(
        pages: [_page(1), _page(2)],
        status: DocumentScanStatus.building,
      ),
      act: (cubit) => cubit
        ..removePage(1)
        ..movePage(0, 1),
      expect: () => const <DocumentScanState>[],
    );

    group('finish', () {
      blocTest<DocumentScanCubit, DocumentScanState>(
        'combines the pages, in order, into a PDF',
        build: build,
        seed: () => DocumentScanState(pages: [_page(2), _page(1)]),
        act: (cubit) => cubit.finish('scan.pdf'),
        expect: () => [
          DocumentScanState(
            pages: [_page(2), _page(1)],
            status: DocumentScanStatus.building,
          ),
          DocumentScanState(
            pages: [_page(2), _page(1)],
            status: DocumentScanStatus.done,
            result: PickedDocument(
              fileName: 'scan.pdf',
              mimeType: 'application/pdf',
              bytes: _pdf,
            ),
          ),
        ],
        verify: (cubit) {
          expect(cubit.state.isBusy, isTrue);
          expect(cubit.state.result!.bytes, _pdf);
          verify(
            () => pdfBuilder.build([
              Uint8List.fromList([2]),
              Uint8List.fromList([1]),
            ], maxBytes: DocumentsCubit.maxFileBytes),
          ).called(1);
        },
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'does nothing without pages',
        build: build,
        act: (cubit) => cubit.finish('scan.pdf'),
        expect: () => const <DocumentScanState>[],
      );

      blocTest<DocumentScanCubit, DocumentScanState>(
        'does nothing while busy',
        build: build,
        seed: () => DocumentScanState(
          pages: [_page(1)],
          status: DocumentScanStatus.capturing,
        ),
        act: (cubit) => cubit.finish('scan.pdf'),
        expect: () => const <DocumentScanState>[],
      );

      for (final (error, notice) in [
        (const ScanTooLarge(), DocumentScanNotice.tooLarge),
        (const FormatException('page'), DocumentScanNotice.buildFailed),
      ]) {
        blocTest<DocumentScanCubit, DocumentScanState>(
          'tells when the PDF fails: $notice',
          setUp: () => when(
            () => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')),
          ).thenThrow(error),
          build: build,
          seed: () => DocumentScanState(pages: [_page(1)]),
          act: (cubit) => cubit.finish('scan.pdf'),
          skip: 1,
          expect: () => [
            DocumentScanState(
              pages: [_page(1)],
              notice: notice,
              noticeCount: 1,
            ),
          ],
          errors: () => [error],
        );
      }

      for (final fails in [false, true]) {
        test('ignores the PDF once closed (fails: $fails)', () async {
          final pdf = Completer<Uint8List>();
          when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
              .thenAnswer((_) => pdf.future);
          final cubit = build()..emit(DocumentScanState(pages: [_page(1)]));
          final finishing = cubit.finish('scan.pdf');
          await cubit.close();
          if (fails) {
            pdf.completeError(const ScanTooLarge());
          } else {
            pdf.complete(_pdf);
          }
          await finishing;
          expect(cubit.state.result, isNull);
        });
      }
    });

    test('pages are equal by id', () {
      expect(
        ScannedPage(id: 1, bytes: Uint8List(1)),
        ScannedPage(id: 1, bytes: Uint8List(2)),
      );
    });
  });
}
