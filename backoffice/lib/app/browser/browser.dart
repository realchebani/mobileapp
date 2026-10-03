import 'dart:typed_data';

/// {@template picked_file}
/// A file chosen by the user.
/// {@endtemplate}
class PickedFile {
  /// {@macro picked_file}
  const new({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// What the back-office asks of the browser (a fake in tests; the web
/// implementation is `web_browser.dart`).
abstract class Browser {
  /// Opens [url] in a new tab.
  Future<void> open(String url);

  /// Opens a new tab at once (still within the click, so it is not blocked)
  /// and sends it to the URL [load] returns (a signed URL).
  Future<void> openPending(Future<String> Function() load);

  /// Saves [text] as a downloaded file.
  Future<void> saveText(String fileName, String text, {String mimeType});

  /// Lets the user choose a PDF; null when cancelled.
  Future<PickedFile?> pickPdf();
}
