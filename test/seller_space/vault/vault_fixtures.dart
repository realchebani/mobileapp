import 'package:property_repository/property_repository.dart';

import '../fixtures.dart';

/// A draft and a certified property of the same seller.
const draftProperty = Property(
  id: 'draft-id',
  ownerId: 'user-id',
  propertyType: PropertyType.parking,
  addressCity: 'Lyon',
);

const Property sentProperty = certifiedProperty;

const sophie = PropertyOwner(
  id: 'owner-1',
  propertyId: 'property-id',
  position: 1,
  firstName: 'Sophie',
  lastName: 'Durand',
  profileId: 'user-id',
);

const marc = PropertyOwner(
  id: 'owner-2',
  propertyId: 'property-id',
  position: 2,
  firstName: 'Marc',
  lastName: 'Durand',
);

/// A document of [propertyId].
PropertyDocument document(
  String id, {
  String propertyId = 'property-id',
  DocumentKind kind = DocumentKind.other,
  DocumentStatus status = DocumentStatus.received,
  String? title,
  String? ownerRef,
  bool added = false,
  DateTime? verifiedAt,
  DateTime? uploadedAt,
  String? rejectedReason,
  String? replacedBy,
  String mimeType = 'application/pdf',
  int? sizeBytes = 2048,
  Set<DocumentVisibility> visibility = const {},
  Map<String, dynamic>? extracted,
}) => PropertyDocument(
  id: id,
  propertyId: propertyId,
  kind: kind,
  storagePath: 'user-id/$propertyId/$id.pdf',
  fileName: '$id.pdf',
  mimeType: mimeType,
  sizeBytes: sizeBytes,
  status: status,
  title: title,
  ownerRef: ownerRef,
  addedAfterSubmission: added,
  verifiedAt: verifiedAt,
  uploadedAt: uploadedAt ?? DateTime(2026, 9, 12),
  rejectedReason: rejectedReason,
  replacedBy: replacedBy,
  visibility: visibility,
  extracted: extracted,
);
