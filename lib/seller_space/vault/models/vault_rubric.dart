import 'package:property_repository/property_repository.dart';

/// A rubric of the vault (C1 / V18): a group of document kinds. The code is
/// the `rubrique` query parameter of the routes (also written by the staff
/// functions in the notifications, see `vault_rubric_of` in the database).
enum VaultRubric {
  /// Title deed, plans, co-ownership.
  property('propriete', [
    DocumentKind.titleDeed,
    DocumentKind.plan,
    DocumentKind.coOwnership,
  ]),

  /// Property tax.
  tax('fiscalite', [DocumentKind.propertyTax]),

  /// Diagnostics, DPE, energy bills, maintenance contracts.
  energy('energie', [
    DocumentKind.dpe,
    DocumentKind.diagnostics,
    DocumentKind.energyBills,
    DocumentKind.maintenanceContract,
  ]),

  /// Works invoices, sanitation report, insurance.
  works('travaux', [
    DocumentKind.worksInvoice,
    DocumentKind.sanitationReport,
    DocumentKind.insurance,
  ]),

  /// Identity documents of the owners (never shared).
  identity('identite', [DocumentKind.identityDocument]),

  /// Documents produced by Realesty (certified valuation; the mandates of
  /// EPIC-08 later), read-only.
  mandates('mandats', []),

  /// Anything else.
  other('autres', [DocumentKind.other]);

  new(this.code, this.kinds);

  /// Query parameter value (`?rubrique=energie`).
  final String code;

  /// The kinds of documents the seller files in this rubric.
  final List<DocumentKind> kinds;

  /// The rubric of a document [kind].
  static VaultRubric of(DocumentKind kind) {
    for (final rubric in values) {
      if (rubric.kinds.contains(kind)) return rubric;
    }
    return other;
  }

  /// The rubric of [code], or null.
  static VaultRubric? fromCode(String? code) {
    for (final rubric in values) {
      if (rubric.code == code) return rubric;
    }
    return null;
  }

  /// Whether the seller can add documents to this rubric.
  bool get acceptsDocuments => kinds.isNotEmpty;
}
