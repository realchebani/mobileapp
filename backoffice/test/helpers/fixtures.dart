import 'package:backoffice_repository/backoffice_repository.dart';

final submittedAt = DateTime.now().subtract(const Duration(days: 3));

DossierSummary summary({
  String id = 'p1',
  DossierStatus status = DossierStatus.submitted,
  LotRef? lot,
  StaffRef? assignedTo,
  DateTime? submitted,
  ValuationDraftStatus? draftStatus,
  int? draftVersion,
}) => DossierSummary(
  id: id,
  status: status,
  propertyType: 'maison',
  city: 'Chaponost',
  postcode: '69630',
  livingAreaM2: 115,
  submittedAt: submitted ?? submittedAt,
  ownerInitials: 'SD',
  lot: lot,
  assignedTo: assignedTo,
  documentsToVerify: 2,
  documentsAddedAfter: 1,
  photosCount: 14,
  hasVoice: true,
  draftStatus: draftStatus,
  draftVersion: draftVersion,
);

const team = [
  StaffMember(
    userId: 'expert-1',
    role: StaffRole.expert,
    displayName: 'Julien M.',
    initials: 'JM',
    active: true,
  ),
  StaffMember(
    userId: 'partner-1',
    role: StaffRole.partnerExpert,
    displayName: 'Paul P.',
    initials: 'PP',
    organisation: 'Cabinet Paul',
    active: true,
  ),
  StaffMember(
    userId: 'old-1',
    role: StaffRole.expert,
    displayName: 'Ancien',
    initials: 'AN',
    active: false,
  ),
];
