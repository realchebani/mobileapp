import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_space/vault/models/vault_rubric.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Status shown on a document of the vault.
enum VaultDocumentStatus {
  /// Uploaded, not analysed yet ("Reçu").
  received,

  /// Being analysed ("Analyse en cours").
  analyzing,

  /// Analysed ("Analysé").
  analyzed,

  /// Verified by the expert ("Vérifié expert").
  verified,

  /// Rejected by the expert ("À remplacer").
  toReplace;

  static VaultDocumentStatus of(PropertyDocument document) {
    if (document.status == DocumentStatus.rejected) return toReplace;
    if (document.isVerified) return verified;
    return switch (document.status) {
      DocumentStatus.analyzing => analyzing,
      DocumentStatus.analyzed => analyzed,
      DocumentStatus.received || DocumentStatus.rejected => received,
    };
  }
}

/// A row of the vault, about one of the [property] documents.
sealed class VaultEntry extends Equatable {
  const new({required this.property});

  final Property property;
}

/// A document of the seller.
final class VaultDocumentEntry extends VaultEntry {
  const new({required super.property, required this.document});

  final PropertyDocument document;

  VaultDocumentStatus get status => VaultDocumentStatus.of(document);

  /// Whether the dossier was sent: its documents are then locked, except
  /// the additions the expert has not verified (owner decision
  /// 2026-10-03; enforced by the database).
  bool get _isSent => property.status != PropertyStatus.draft;

  bool get _isOpenAddition =>
      document.addedAfterSubmission && !document.isVerified;

  /// "Supprimer": any document of a draft, else an unverified addition.
  bool get canDelete => !_isSent || _isOpenAddition;

  /// "Remplacer": like [canDelete], and any rejected document.
  bool get canReplace => canDelete || status == VaultDocumentStatus.toReplace;

  /// "Qui peut voir ce document ?": never for an identity document.
  bool get canShare => document.kind != DocumentKind.identityDocument;

  @override
  List<Object?> get props => [property, document];
}

/// A required document that is missing ("Manquant" + "Scanner"): the title
/// deed, or the identity document of an owner.
final class VaultMissingEntry extends VaultEntry {
  const new({required super.property, required this.kind, this.owner});

  final DocumentKind kind;

  /// The owner whose identity document is missing, when known.
  final PropertyOwner? owner;

  @override
  List<Object?> get props => [property, kind, owner];
}

/// The certified valuation of a property (produced by Realesty, read-only).
final class VaultValuationEntry extends VaultEntry {
  const new({required super.property, required this.valuation});

  final Valuation valuation;

  @override
  List<Object?> get props => [property, valuation];
}

/// The entries of one rubric.
final class VaultSection extends Equatable {
  const new({
    required this.rubric,
    this.documents = const [],
    this.missing = const [],
    this.valuations = const [],
  });

  final VaultRubric rubric;
  final List<VaultDocumentEntry> documents;
  final List<VaultMissingEntry> missing;
  final List<VaultValuationEntry> valuations;

  /// Documents in the rubric (including the valuations).
  int get count => documents.length + valuations.length;

  /// Documents verified by the expert (a valuation is).
  int get verifiedCount =>
      valuations.length +
      documents.where((d) => d.status == VaultDocumentStatus.verified).length;

  /// Documents the expert asks to replace.
  int get toReplaceCount =>
      documents.where((d) => d.status == VaultDocumentStatus.toReplace).length;

  /// Documents being analysed.
  int get analyzingCount =>
      documents.where((d) => d.status == VaultDocumentStatus.analyzing).length;

  @override
  List<Object?> get props => [rubric, documents, missing, valuations];
}

/// The vault of one property or of a lot: its documents by rubric, the
/// required documents missing, the latest ones (pure model).
final class VaultContents extends Equatable {
  const new _({required this.sections, required this.recents});

  /// Builds the vault of [properties] from their [documents], the
  /// [owners] of each property (by property id) and the latest
  /// [valuations] (by property id). Replaced documents are left out.
  factory of({
    required List<Property> properties,
    required List<PropertyDocument> documents,
    Map<String, List<PropertyOwner>> owners = const {},
    Map<String, Valuation> valuations = const {},
  }) {
    final byId = {for (final property in properties) property.id: property};
    final entries = [
      for (final document in documents)
        if (document.replacedBy == null && byId[document.propertyId] != null)
          VaultDocumentEntry(
            property: byId[document.propertyId]!,
            document: document,
          ),
    ];
    final missing = [
      for (final property in properties)
        ..._missingOf(property, [
          for (final entry in entries)
            if (entry.property.id == property.id) entry.document,
        ], owners[property.id] ?? const []),
    ];
    final valuationEntries = [
      for (final property in properties)
        if (valuations[property.id] case final valuation?)
          VaultValuationEntry(property: property, valuation: valuation),
    ];
    final sections = [
      for (final rubric in VaultRubric.values)
        VaultSection(
          rubric: rubric,
          documents: [
            for (final entry in entries)
              if (VaultRubric.of(entry.document.kind) == rubric) entry,
          ],
          missing: [
            for (final entry in missing)
              if (VaultRubric.of(entry.kind) == rubric) entry,
          ],
          valuations: rubric == VaultRubric.mandates ? valuationEntries : [],
        ),
    ];
    final dated = <(VaultEntry, DateTime)>[
      for (final entry in entries)
        (entry, entry.document.uploadedAt ?? DateTime(0)),
      for (final entry in valuationEntries)
        (entry, entry.valuation.certifiedAt),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return VaultContents._(
      sections: sections,
      recents: [for (final (entry, _) in dated.take(recentsCount)) entry],
    );
  }

  /// Number of latest documents shown in C1.
  static const recentsCount = 3;

  /// Every rubric, in order.
  final List<VaultSection> sections;

  /// The latest documents (and valuations), newest first.
  final List<VaultEntry> recents;

  /// The section of [rubric].
  VaultSection section(VaultRubric rubric) =>
      sections.firstWhere((section) => section.rubric == rubric);

  /// Documents in the vault.
  int get documentCount =>
      sections.fold(0, (sum, section) => sum + section.count);

  /// Required documents missing.
  List<VaultMissingEntry> get missing => [
    for (final section in sections) ...section.missing,
  ];

  /// Documents the expert asks to replace.
  List<VaultDocumentEntry> get toReplace => [
    for (final section in sections)
      for (final entry in section.documents)
        if (entry.status == VaultDocumentStatus.toReplace) entry,
  ];

  /// The documents whose [label] (title, kind, file name…) contains
  /// [query] (case-insensitive).
  List<VaultDocumentEntry> search(
    String query,
    String Function(VaultDocumentEntry entry) label,
  ) {
    final needle = _fold(query.trim());
    if (needle.isEmpty) return const [];
    return [
      for (final section in sections)
        for (final entry in section.documents)
          if (_fold(label(entry)).contains(needle)) entry,
    ];
  }

  /// Lower case, without the French accents.
  static String _fold(String text) {
    const from = 'àâäáçéèêëíîïôöóùûüúÿñœ';
    const to = 'aaaaceeeeiiiooouuuuyno';
    final buffer = StringBuffer();
    for (final char in text.toLowerCase().split('')) {
      final index = from.indexOf(char);
      buffer.write(index < 0 ? char : to[index]);
    }
    return buffer.toString();
  }

  /// The required documents of [property] that are missing: the title deed,
  /// and the identity document of each owner (a document filed for no
  /// particular owner covers the first owners without one).
  static List<VaultMissingEntry> _missingOf(
    Property property,
    List<PropertyDocument> documents,
    List<PropertyOwner> owners,
  ) {
    final missing = <VaultMissingEntry>[];
    if (!documents.any((d) => d.kind == DocumentKind.titleDeed)) {
      missing.add(
        VaultMissingEntry(property: property, kind: DocumentKind.titleDeed),
      );
    }
    final identities = [
      for (final document in documents)
        if (document.kind == DocumentKind.identityDocument) document,
    ];
    if (owners.isEmpty) {
      if (identities.isEmpty) {
        missing.add(
          VaultMissingEntry(
            property: property,
            kind: DocumentKind.identityDocument,
          ),
        );
      }
      return missing;
    }
    var unassigned = identities.where((d) => d.ownerRef == null).length;
    final sorted = [...owners]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final owner in sorted) {
      if (identities.any((d) => d.ownerRef != null && d.ownerRef == owner.id)) {
        continue;
      }
      if (unassigned > 0) {
        unassigned--;
        continue;
      }
      missing.add(
        VaultMissingEntry(
          property: property,
          kind: DocumentKind.identityDocument,
          owner: owner,
        ),
      );
    }
    return missing;
  }

  @override
  List<Object?> get props => [sections, recents];
}
