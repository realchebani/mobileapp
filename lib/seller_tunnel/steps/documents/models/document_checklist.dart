import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:property_repository/property_repository.dart';

/// Computed status of a kind of document in the vault.
enum DocumentRowStatus {
  /// Required and not provided ("Manquant").
  missing,

  /// Not required and not provided ("Facultatif").
  optional,

  /// Not applicable to this property ("Non concerné").
  notConcerned,

  /// Every file was rejected by the expert ("À renvoyer").
  rejected,

  /// Uploaded, waiting for the expert ("Reçu").
  received,

  /// Being analysed ("Analyse en cours").
  analyzing,

  /// Analysed ("Analysé").
  analyzed;

  /// Whether files of this kind were provided (and not all rejected).
  bool get isProvided => index >= received.index;
}

/// Why the sanitation report row is (not) required.
enum SanitationReportRule {
  /// Individual sanitation: required.
  required,

  /// Connected to the sewer: not concerned.
  mainsSewer,

  /// Sanitation not answered: optional.
  unknown,
}

/// One row of the vault: a kind of document, its files and its status.
final class DocumentRow extends Equatable {
  const new({
    required this.kind,
    required this.status,
    required this.isRequired,
    this.documents = const [],
  });

  final DocumentKind kind;
  final DocumentRowStatus status;

  /// Whether a missing file counts as missing for the dossier.
  final bool isRequired;

  /// Files of this kind, oldest first.
  final List<PropertyDocument> documents;

  @override
  List<Object?> get props => [kind, status, isRequired, documents];
}

/// The documents expected for a property, their statuses and the
/// transparency score (v1, computed in the app).
final class DocumentChecklist extends Equatable {
  const new _({
    required this.rows,
    required this.sanitationRule,
    required this.score,
    required this.nextBestKind,
  });

  /// Computes the checklist of [property] given its [documents]; the
  /// listed documents and the answers of the score depend on its type
  /// (`PropertyTypeProfile`).
  factory of(Property property, List<PropertyDocument> documents) {
    final profile = PropertyTypeProfile.of(property.propertyType);
    final listed = profile.documentKinds;
    final sanitationRule = switch (property.sanitation) {
      Sanitation.mainsSewer => SanitationReportRule.mainsSewer,
      Sanitation.septicTank ||
      Sanitation.soakaway => SanitationReportRule.required,
      null => SanitationReportRule.unknown,
    };
    final rows = <DocumentRow>[];
    for (final kind in DocumentKind.values) {
      final files = [
        for (final document in documents)
          if (document.kind == kind) document,
      ];
      final isListed = listed.contains(kind);
      if (!isListed && files.isEmpty) continue;
      final isRequired =
          requiredKinds.contains(kind) ||
          (kind == DocumentKind.sanitationReport &&
              sanitationRule == SanitationReportRule.required);
      final notConcerned =
          kind == DocumentKind.sanitationReport &&
          sanitationRule == SanitationReportRule.mainsSewer;
      rows.add(
        DocumentRow(
          kind: kind,
          isRequired: isRequired,
          documents: files,
          status: _statusOf(
            files,
            isRequired: isRequired,
            notConcerned: notConcerned,
          ),
        ),
      );
    }

    // Weighted completeness of the documents and of the answers.
    var expected = 0;
    var provided = 0;
    DocumentKind? nextBest;
    var nextBestWeight = 0;
    for (final row in rows) {
      final weight = scoreWeights[row.kind] ?? 0;
      if (weight == 0 || row.status == DocumentRowStatus.notConcerned) {
        continue;
      }
      // An optional report (sanitation not answered) can only raise the
      // score.
      if (row.status == DocumentRowStatus.optional &&
          row.kind == DocumentKind.sanitationReport) {
        continue;
      }
      expected += weight;
      if (row.status.isProvided) {
        provided += weight;
      } else if (weight > nextBestWeight) {
        nextBest = row.kind;
        nextBestWeight = weight;
      }
    }
    final answers = profile.scoredAnswers(property);
    final answered = answers.where((answered) => answered).length;
    final score =
        documentsShare * provided / expected +
        (100 - documentsShare) * answered / answers.length;

    return DocumentChecklist._(
      rows: rows,
      sanitationRule: sanitationRule,
      score: score.round().clamp(0, 100),
      nextBestKind: nextBest,
    );
  }

  /// Kinds required for every property (the sanitation report is required
  /// when the sanitation is individual). The diagnostics are optional: they
  /// only count in the score, like the energy bills.
  static const Set<DocumentKind> requiredKinds = {
    DocumentKind.titleDeed,
    DocumentKind.propertyTax,
    DocumentKind.identityDocument,
  };

  /// Kinds without which the dossier cannot be sent (a file not rejected
  /// is needed), in display order.
  static const List<DocumentKind> submissionKinds = [
    DocumentKind.titleDeed,
    DocumentKind.identityDocument,
  ];

  /// Weight of each kind in the documents part of the score.
  static const Map<DocumentKind, int> scoreWeights = {
    DocumentKind.titleDeed: 20,
    DocumentKind.identityDocument: 15,
    DocumentKind.diagnostics: 20,
    DocumentKind.propertyTax: 10,
    DocumentKind.energyBills: 10,
    DocumentKind.worksInvoice: 5,
    DocumentKind.sanitationReport: 10,
  };

  /// Share of the documents in the score (the rest: answers).
  static const documentsShare = 70;

  /// Rows of the vault, in display order.
  final List<DocumentRow> rows;

  /// Rule applied to the sanitation report.
  final SanitationReportRule sanitationRule;

  /// Transparency score, 0–100.
  final int score;

  /// The missing document that would raise the score the most, if any.
  final DocumentKind? nextBestKind;

  /// Required documents not provided.
  int get missingCount =>
      rows.where((row) => row.isRequired && !row.status.isProvided).length;

  /// The [submissionKinds] not provided yet, in display order: the dossier
  /// can only be sent once there are none.
  List<DocumentKind> get blockingKinds => [
    for (final row in rows)
      if (submissionKinds.contains(row.kind) && !row.status.isProvided)
        row.kind,
  ];

  /// Whether the dossier can be sent ([blockingKinds] is empty).
  bool get canSubmit => blockingKinds.isEmpty;

  /// Required documents not provided that do not block the sending (the
  /// expert can ask for them later).
  int get optionalMissingCount => rows
      .where(
        (row) =>
            row.isRequired &&
            !row.status.isProvided &&
            !submissionKinds.contains(row.kind),
      )
      .length;

  static DocumentRowStatus _statusOf(
    List<PropertyDocument> files, {
    required bool isRequired,
    required bool notConcerned,
  }) {
    final kept = [
      for (final file in files)
        if (file.status != DocumentStatus.rejected) file,
    ];
    if (kept.isEmpty) {
      if (files.isNotEmpty) return DocumentRowStatus.rejected;
      if (notConcerned) return DocumentRowStatus.notConcerned;
      return isRequired
          ? DocumentRowStatus.missing
          : DocumentRowStatus.optional;
    }
    if (kept.any((file) => file.status == DocumentStatus.analyzing)) {
      return DocumentRowStatus.analyzing;
    }
    if (kept.every((file) => file.status == DocumentStatus.analyzed)) {
      return DocumentRowStatus.analyzed;
    }
    return DocumentRowStatus.received;
  }

  @override
  List<Object?> get props => [rows, sanitationRule, score, nextBestKind];
}
