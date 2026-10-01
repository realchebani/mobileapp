import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';

part 'document_scan_state.dart';

/// A multi-page scanning session: the user scans pages (several at a time
/// with the system scanner), reviews, reorders or deletes them, then they
/// are combined into one PDF ([DocumentScanState.result]).
class DocumentScanCubit extends Cubit<DocumentScanState> {
  new({required this._documentPicker, required this._pdfBuilder})
    : super(const DocumentScanState());

  /// Most pages of a document.
  static const maxPages = 30;

  final DocumentPicker _documentPicker;
  final ScanPdfBuilder _pdfBuilder;
  int _nextId = 0;

  /// Opens the scanner and adds the pages it returns.
  Future<void> addPages() async {
    if (state.isBusy || state.isFull) return;
    emit(state.copyWith(status: DocumentScanStatus.capturing));
    final added = <ScannedPage>[];
    DocumentScanNotice? notice;
    try {
      final files = await _documentPicker.scanPages(
        maxPages: maxPages - state.pages.length,
      );
      for (final file in files ?? const <XFile>[]) {
        added.add(ScannedPage(id: _nextId++, bytes: await file.readAsBytes()));
      }
    } on DocumentAccessDenied catch (error, stackTrace) {
      addError(error, stackTrace);
      notice = DocumentScanNotice.accessDenied;
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      notice = DocumentScanNotice.captureFailed;
    }
    if (isClosed) return;
    final room = maxPages - state.pages.length;
    if (added.length > room) notice = DocumentScanNotice.truncated;
    emit(
      state.copyWith(
        pages: [...state.pages, ...added.take(room)],
        status: DocumentScanStatus.idle,
        captures: state.captures + 1,
        notice: notice,
      ),
    );
  }

  /// Removes the page [id].
  void removePage(int id) {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        pages: [
          for (final page in state.pages)
            if (page.id != id) page,
        ],
      ),
    );
  }

  /// Moves the page at [from] to [to] (indexes in the list without it).
  void movePage(int from, int to) {
    if (state.isBusy) return;
    final pages = [...state.pages];
    pages.insert(to, pages.removeAt(from));
    emit(state.copyWith(pages: pages));
  }

  /// Combines the pages into one PDF named [fileName].
  Future<void> finish(String fileName) async {
    if (state.isBusy || state.pages.isEmpty) return;
    emit(state.copyWith(status: DocumentScanStatus.building));
    try {
      final pdf = await _pdfBuilder.build([
        for (final page in state.pages) page.bytes,
      ], maxBytes: DocumentsCubit.maxFileBytes);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: DocumentScanStatus.done,
          result: PickedDocument(
            fileName: fileName,
            mimeType: 'application/pdf',
            bytes: pdf,
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          status: DocumentScanStatus.idle,
          notice: error is ScanTooLarge
              ? DocumentScanNotice.tooLarge
              : DocumentScanNotice.buildFailed,
        ),
      );
    }
  }
}
