import 'package:backoffice_repository/backoffice_repository.dart';

final DateTime submittedAt = DateTime.now().subtract(const Duration(days: 3));

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

/// A dossier with every section filled, as `bo_get_dossier` returns it.
JsonMap dossierJson({
  String role = 'admin',
  String status = 'submitted',
  JsonMap? draft,
  JsonMap? valuation,
  bool partner = false,
}) => {
  'role': role,
  'property': {
    'id': 'p1',
    'status': status,
    'property_type': 'maison',
    'address_label': '12 rue de la Colombe 69630 Chaponost',
    'address_city': 'Chaponost',
    'living_area_m2': 115,
    'annex_area_m2': 20,
    'lat': 45.7,
    'lng': 4.74,
    'submitted_at': submittedAt.toIso8601String(),
    'ai_estimate_median_eur': 518000,
    'step_notes': {'technical': 'Toiture refaite en 2016', 'other': 3},
  },
  'seller': partner
      ? {'initials': 'SD', 'city': 'Chaponost', 'deactivated': false}
      : {
          'first_name': 'Sophie',
          'last_name': 'Durand',
          'email': 'sophie@example.test',
          'phone': '0600000000',
          'deactivated': true,
        },
  'owners': [
    if (partner)
      {'id': 'o1', 'position': 1, 'initials': 'SD', 'city': 'Chaponost'}
    else ...[
      {
        'id': 'o1',
        'position': 1,
        'first_name': 'Sophie',
        'last_name': 'Durand',
        'phone': '0600000000',
        'email': 'sophie@example.test',
      },
      {
        'id': 'o2',
        'position': 2,
        'first_name': 'Marc',
        'last_name': 'Durand',
        'identity_verified_at': '2026-10-02T08:00:00Z',
      },
    ],
  ],
  'parcels': [
    {'idu': '69043000AB0012', 'section': 'AB', 'numero': '12', 'area_m2': 540},
    {'idu': '69043000AB0013', 'section': 'AB', 'numero': '13'},
  ],
  'previous_estimates': [
    {'agency_name': 'Agence du Centre', 'price_eur': 510000},
    {'estimated_month': '2025-01-01'},
  ],
  'rooms': [
    {
      'id': 'r1',
      'name': 'Séjour',
      'level': 'rdc',
      'area_m2': 32.5,
      'is_main': true,
      'source': 'voice',
      'description': 'Lumineux',
      'photos_count': 2,
    },
    {'id': 'r2', 'name': 'Chambre', 'is_main': true, 'source': 'plan'},
    {'id': 'r3', 'name': 'Garage', 'is_annex': true, 'source': 'manual'},
  ],
  'documents': [
    if (!partner)
      {
        'id': 'd1',
        'kind': 'piece_identite',
        'status': 'received',
        'file_name': 'cni.pdf',
        'uploaded_at': '2026-10-01T08:00:00Z',
      },
    {
      'id': 'd2',
      'kind': 'titre_propriete',
      'status': 'received',
      'title': 'Titre 2010',
      'file_name': 'titre.pdf',
      'added_after_submission': true,
    },
    {
      'id': 'd3',
      'kind': 'dpe',
      'status': 'analyzed',
      'verified_at': '2026-10-02T08:00:00Z',
    },
    {
      'id': 'd4',
      'kind': 'taxe_fonciere',
      'status': 'rejected',
      'rejected_reason': 'Illisible',
      'replaced_by': 'd5',
    },
  ],
  'photos': [
    {
      'id': 'ph1',
      'room_id': 'r1',
      'sort_order': 0,
      'quality': {
        'issues': ['dark'],
      },
      'analysis': {
        'room_kind': 'séjour',
        'floor_covering': 'parquet',
        'glazing': 'double',
        'condition_notes': ['fissure au plafond'],
        'people_visible': true,
      },
    },
    {'id': 'ph2', 'room_id': 'r1', 'sort_order': 1},
  ],
  'voice_thread': [
    {
      'step': 'rooms',
      'at': '2026-10-01T08:00:00Z',
      'transcript': 'Le séjour fait trente-deux mètres carrés',
      'reply_fr': 'C’est noté.',
      'retained': {
        'patch': {'area_m2': 32.5},
        'evidence': ['trente-deux'],
      },
      'rejected': [
        {'field': 'glazing', 'reason': 'not_said'},
      ],
      'cross_step': [
        {'target_step': 'technical', 'field': 'roof_year'},
      ],
      'undone': true,
      'error': 'timeout',
    },
    {'step': 'technical', 'retained': <String, dynamic>{}},
  ],
  'fill_sheet': [
    {
      'step': 'technical',
      'label_fr': 'Année de construction',
      'value': '1998',
      'source': 'dicte',
      'quote': 'construite en 1998',
      'confirmed': true,
      'verified': false,
    },
    {
      'step': 'technical',
      'label_fr': 'Toiture',
      'value': 'Tuiles',
      'source': 'extrait',
    },
    {
      'step': 'technical',
      'label_fr': 'Assainissement',
      'value': 'Tout-à-l’égout',
      'source': 'externe',
    },
    {
      'step': 'technical',
      'label_fr': 'Piscine',
      'value': 'oui',
      'source': 'dicte_autre_etape',
      'confirmed': false,
      'quote': 'on a une piscine',
    },
    {
      'step': 'rooms',
      'entity_label': 'Séjour',
      'label_fr': 'Surface',
      'value': '32,5 m²',
      'source': 'saisi',
    },
    {'step': 'mystery', 'label_fr': 'Autre', 'source': 'invalide'},
    {'step': 'location', 'label_fr': 'Adresse', 'source': 'non_trace'},
  ],
  'market': {
    'estimate_low_eur': 495000,
    'estimate_median_eur': 512000,
    'estimate_high_eur': 530000,
    'price_m2_median': 4450,
    'confidence': 72,
    'comparables_count': 11,
    'radius_m': 1000,
    'months': 24,
    'explanation_fr': 'Onze ventes récentes.',
    'comparables': [
      {
        'street': 'rue Lucien Cozon',
        'sold_year': 2025,
        'area_m2': 107,
        'land_m2': 576,
        'price_eur': 457000,
      },
      {'street': null, 'sold_year': 2024, 'price_eur': 400000},
    ],
  },
  'lot': {
    'id': 'l1',
    'name': 'Maison + terrain',
    'sale_mode': 'ensemble',
    'members': [
      {'id': 'p1', 'status': status, 'accessible': true},
      {
        'id': 'p9',
        'status': 'certified',
        'property_type': 'terrain',
        'accessible': true,
      },
      {'id': 'p8', 'status': 'submitted', 'accessible': false},
    ],
  },
  'valuation': valuation,
  'draft': draft,
  'assignment': {
    'user_id': 'expert-1',
    'display_name': 'Julien M.',
    'role': 'expert',
  },
};

Dossier dossierFixture({
  String role = 'admin',
  String status = 'submitted',
  JsonMap? draft,
  JsonMap? valuation,
  bool partner = false,
}) => Dossier.fromJson(
  dossierJson(
    role: role,
    status: status,
    draft: draft,
    valuation: valuation,
    partner: partner,
  ),
);

const validPayload = <String, dynamic>{
  'value_eur': 525000,
  'low_eur': 505000,
  'high_eur': 545000,
};
