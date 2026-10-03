import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';

/// Cells a spreadsheet would read as a formula get a leading quote.
String _defuse(String value) =>
    value.isNotEmpty && '=+-@\t\r'.contains(value[0]) ? "'$value" : value;

String _cell(String raw) {
  final value = _defuse(raw);
  final needsQuotes = RegExp('[;"\n\r]').hasMatch(value);
  final escaped = value.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

/// The journal as CSV (semicolons, for French spreadsheets).
String auditCsv(AppLocalizations l10n, List<AuditEntry> entries) {
  final rows = [
    [
      l10n.auditColAt,
      l10n.auditColActor,
      'role',
      l10n.auditColAction,
      'action',
      l10n.auditColDossier,
      'target',
      l10n.auditColDetails,
    ],
    for (final e in entries)
      [
        e.at.toUtc().toIso8601String(),
        auditActorLabel(l10n, e),
        e.actorRole,
        auditActionLabel(l10n, e.action),
        e.action,
        e.propertyId ?? '',
        [e.targetType, e.targetId].whereType<String>().join(':'),
        if (e.details.isEmpty) '' else compactJson(e.details),
      ],
  ];
  return '${rows.map((r) => r.map(_cell).join(';')).join('\r\n')}\r\n';
}
