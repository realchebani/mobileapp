import 'package:backoffice_repository/src/models/json.dart';
import 'package:equatable/equatable.dart';

/// Kind of file `bo-files` signs.
enum FileKind {
  document('document'),
  photo('photo'),
  report('report');

  new(this.value);

  final String value;

  static FileKind parse(Object? value) =>
      values.firstWhere((k) => k.value == value, orElse: () => document);
}

/// {@template file_request}
/// A file to sign: a document, a room photo or the valuation report.
/// {@endtemplate}
class FileRequest extends Equatable {
  /// {@macro file_request}
  const new(this.kind, this.id);

  final FileKind kind;
  final String id;

  JsonMap toJson() => {'type': kind.value, 'id': id};

  @override
  List<Object?> get props => [kind, id];
}

/// {@template signed_file}
/// A short-lived URL (5 minutes) of a dossier file.
/// {@endtemplate}
class SignedFile extends Equatable {
  /// {@macro signed_file}
  const new({
    required this.kind,
    required this.id,
    required this.url,
    this.fileName,
    this.mimeType,
  });

  factory fromJson(JsonMap json) => SignedFile(
    kind: FileKind.parse(json['type']),
    id: json['id'] as String,
    url: json['url'] as String,
    fileName: json['file_name'] as String?,
    mimeType: json['mime_type'] as String?,
  );

  final FileKind kind;
  final String id;
  final String url;
  final String? fileName;
  final String? mimeType;

  @override
  List<Object?> get props => [kind, id, url, fileName, mimeType];
}
