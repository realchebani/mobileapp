import 'dart:async';
import 'dart:js_interop';

import 'package:realesty_backoffice/app/browser/browser.dart';
import 'package:web/web.dart' as web;

/// [Browser] on the web (not loaded by the VM tests).
class WebBrowser implements Browser {
  @override
  Future<void> open(String url) async {
    web.window.open(url, '_blank', 'noopener,noreferrer');
  }

  @override
  Future<void> openPending(Future<String> Function() load) async {
    // Opened before the await: a tab opened after it would be blocked.
    final tab = web.window.open('', '_blank');
    try {
      final url = await load();
      if (tab == null) {
        web.window.open(url, '_blank', 'noopener,noreferrer');
      } else {
        tab
          ..opener = null
          ..location.href = url;
      }
    } catch (_) {
      tab?.close();
      rethrow;
    }
  }

  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'text/csv;charset=utf-8',
  }) async {
    // UTF-8 BOM so spreadsheet tools read the accents.
    final blob = web.Blob(
      ['﻿$text'.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    (web.document.createElement('a') as web.HTMLAnchorElement)
      ..href = url
      ..download = fileName
      ..click();
    // Revoked later: some browsers start the download asynchronously.
    unawaited(
      Future<void>.delayed(
        const Duration(minutes: 1),
        () => web.URL.revokeObjectURL(url),
      ),
    );
  }

  @override
  Future<PickedFile?> pickPdf() {
    final completer = Completer<PickedFile?>();
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = 'application/pdf';
    input
      ..onchange = (web.Event _) {
        final file = input.files?.item(0);
        if (file == null) {
          completer.complete(null);
          return;
        }
        unawaited(
          file.arrayBuffer().toDart.then((buffer) {
            completer.complete(
              PickedFile(name: file.name, bytes: buffer.toDart.asUint8List()),
            );
          }, onError: completer.completeError),
        );
      }.toJS
      ..oncancel = (web.Event _) {
        if (!completer.isCompleted) completer.complete(null);
      }.toJS
      ..click();
    // Browsers without `cancel`: the window gets the focus back when the
    // dialog closes; no file a moment later means it was cancelled.
    late final JSFunction onFocus;
    onFocus = (web.Event _) {
      web.window.removeEventListener('focus', onFocus);
      unawaited(
        Future<void>.delayed(const Duration(seconds: 1), () {
          if (!completer.isCompleted && (input.files?.length ?? 0) == 0) {
            completer.complete(null);
          }
        }),
      );
    }.toJS;
    web.window.addEventListener('focus', onFocus);
    return completer.future;
  }
}
