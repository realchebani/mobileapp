import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:test/test.dart';

void main() {
  group('Json', () {
    test('reads tolerant shapes', () {
      expect(Json.integer(2.7), 2);
      expect(Json.integer('12'), 12);
      expect(Json.integer(null), isNull);
      expect(Json.number('1.5'), 1.5);
      expect(Json.number(2), 2.0);
      expect(Json.number(true), isNull);
      expect(Json.date('2026-10-03T10:00:00Z'), DateTime.utc(2026, 10, 3, 10));
      expect(Json.date(3), isNull);
      expect(Json.text(' '), isNull);
      expect(Json.text('a'), 'a');
      expect(Json.map({'a': 1}), {'a': 1});
      expect(Json.map('x'), isNull);
      expect(
        Json.maps([
          {'a': 1},
          'x',
        ]),
        [
          {'a': 1},
        ],
      );
      expect(Json.maps(null), isEmpty);
    });
  });

  group(StaffMe, () {
    test('parses a member and their capabilities', () {
      final me = StaffMe.fromJson(const {
        'user_id': 'u1',
        'email': 'julien@example.test',
        'role': 'partner_expert',
        'display_name': 'Julien M.',
        'initials': 'JM',
        'organisation': 'Cabinet',
        'aal2': true,
        'capabilities': ['submit_for_approval', 'nope'],
      });
      expect(me.isMember, isTrue);
      expect(me.role, StaffRole.partnerExpert);
      expect(me.can(BackOfficeCapability.submitForApproval), isTrue);
      expect(me.can(BackOfficeCapability.certify), isFalse);
      expect(me.props, hasLength(8));
    });

    test('a non-member has no role', () {
      final me = StaffMe.fromJson(const {'user_id': 'u1', 'role': null});
      expect(me.isMember, isFalse);
      expect(me.aal2, isFalse);
      expect(me.capabilities, isEmpty);
      expect(StaffRole.parse('x'), isNull);
    });
  });

  group(StaffMember, () {
    test('parses a team row with defaults', () {
      final member = StaffMember.fromJson(const {
        'user_id': 'u1',
        'email': 'a@b.c',
        'role': 'admin',
        'display_name': 'Ana',
        'initials': 'A',
        'organisation': ' ',
        'active': false,
        'created_at': '2026-10-03T10:00:00Z',
        'deactivated_at': '2026-10-04T10:00:00Z',
        'mfa_enrolled': true,
        'active_assignments': 2,
      });
      expect(member.role, StaffRole.admin);
      expect(member.organisation, isNull);
      expect(member.active, isFalse);
      expect(member.mfaEnrolled, isTrue);
      expect(member.activeAssignments, 2);
      final fallback = StaffMember.fromJson(const {'user_id': 'u2'});
      expect(fallback.role, StaffRole.expert);
      expect(fallback.displayName, '');
      expect(fallback.active, isTrue);
      expect(fallback.props, hasLength(11));
    });
  });

  group(DossierSummary, () {
    test('parses a queue row', () {
      final row = DossierSummary.fromJson(const {
        'id': 'p1',
        'status': 'in_review',
        'property_type': 'maison',
        'property_type_other': '',
        'city': 'Chaponost',
        'postcode': '69630',
        'living_area_m2': 115,
        'usable_area_m2': null,
        'submitted_at': '2026-10-01T08:00:00Z',
        'owner_initials': 'AP',
        'owner_deactivated': true,
        'lot': {
          'id': 'l1',
          'name': 'Maison + terrain',
          'sale_mode': 'ensemble',
          'main_property_id': 'p1',
        },
        'assigned_to': {
          'user_id': 'u1',
          'display_name': 'Julien M.',
          'initials': 'JM',
        },
        'documents_to_verify': 3,
        'documents_added_after': 1,
        'photos_count': 12,
        'has_voice': true,
        'draft': {'status': 'submitted_for_approval', 'version': 4},
      });
      expect(row.status, DossierStatus.inReview);
      expect(row.areaM2, 115);
      expect(row.propertyTypeOther, isNull);
      expect(row.lot?.name, 'Maison + terrain');
      expect(row.assignedTo?.displayName, 'Julien M.');
      expect(row.draftStatus, ValuationDraftStatus.submittedForApproval);
      expect(row.draftVersion, 4);
      expect(row.props, hasLength(19));
    });

    test('defaults', () {
      final row = DossierSummary.fromJson(const {
        'id': 'p1',
        'status': 'weird',
        'usable_area_m2': 18,
      });
      expect(row.status, DossierStatus.submitted);
      expect(row.areaM2, 18);
      expect(row.lot, isNull);
      expect(row.assignedTo, isNull);
      expect(row.draftStatus, isNull);
      expect(row.documentsToVerify, 0);
    });
  });

  group(Dossier, () {
    const json = {
      'role': 'expert',
      'property': {
        'id': 'p1',
        'status': 'submitted',
        'property_type': 'maison',
        'address_city': 'Chaponost',
        'living_area_m2': 115.5,
        'submitted_at': '2026-10-01T08:00:00Z',
      },
      'seller': {'first_name': 'Anne', 'deactivated': true},
      'owners': [
        {
          'id': 'o1',
          'position': 1,
          'first_name': 'Anne',
          'last_name': 'Probe',
          'phone': '06',
          'email': 'a@b.c',
          'identity_verified_at': '2026-10-02T08:00:00Z',
        },
        {'id': 'o2', 'position': 2, 'initials': 'MP', 'city': 'Chaponost'},
      ],
      'parcels': [
        {'idu': '69043000AB0012'},
      ],
      'rooms': [
        {
          'id': 'r1',
          'name': 'Séjour',
          'level': 'rdc',
          'area_m2': 32.5,
          'is_main': true,
          'is_annex': false,
          'source': 'voice',
          'description': 'Lumineux',
          'floor_covering': 'parquet',
          'glazing': 'double',
          'photos_count': 2,
        },
      ],
      'documents': [
        {
          'id': 'd1',
          'kind': 'piece_identite',
          'status': 'received',
          'title': 'CNI',
          'file_name': 'cni.pdf',
          'mime_type': 'application/pdf',
          'size_bytes': 1000,
          'uploaded_at': '2026-10-01T08:00:00Z',
          'added_after_submission': true,
        },
        {
          'id': 'd2',
          'kind': 'titre_propriete',
          'status': 'rejected',
          'rejected_reason': 'Illisible',
          'replaced_by': 'd3',
          'verified_at': null,
        },
        {'id': 'd3', 'verified_at': '2026-10-02T08:00:00Z'},
      ],
      'photos': [
        {
          'id': 'ph2',
          'room_id': 'r1',
          'sort_order': 1,
          'quality': {
            'issues': ['dark', 3],
          },
        },
        {
          'id': 'ph1',
          'room_id': 'r1',
          'sort_order': 0,
          'width': 2048,
          'height': 1536,
          'analysis': {'room_type': 'sejour'},
          'taken_at': '2026-10-01T08:00:00Z',
        },
        {'id': 'ph3', 'room_id': 'r2'},
      ],
      'voice_thread': [
        {
          'step': 'rooms',
          'at': '2026-10-01T08:00:00Z',
          'transcript': 'Le séjour fait 32 m²',
          'reply_fr': 'Noté',
          'retained': {'patch': <String, dynamic>{}},
          'rejected': [
            {'field': 'x'},
          ],
          'cross_step': <dynamic>[],
          'undone': true,
          'error': null,
        },
      ],
      'fill_sheet': [
        {
          'step': 'rooms',
          'label_fr': 'Surface',
          'entity_label': 'Séjour',
          'value': '32,5 m²',
          'source': 'dicte',
          'quote': 'Le séjour fait 32 m²',
          'said_at': '2026-10-01T08:00:00Z',
          'confirmed': true,
          'confirmation': 'continuer',
          'verified': false,
        },
        {'field': 'area_m2'},
      ],
      'market': {'estimate_median_eur': 500000},
      'lot': {
        'id': 'l1',
        'name': 'Lot',
        'members': [
          {
            'id': 'p1',
            'status': 'submitted',
            'property_type': 'maison',
            'city': 'Chaponost',
            'living_area_m2': 115,
            'accessible': true,
          },
        ],
      },
      'valuation': {'value_eur': 525000},
      'draft': {
        'payload': {'value_eur': 1},
        'version': 3,
        'status': 'editing',
        'updated_at': '2026-10-02T08:00:00Z',
        'updated_by_name': 'Julien M.',
        'submitted_by': 'u2',
        'submitted_by_name': 'Paul P.',
        'submitted_at': '2026-10-02T09:00:00Z',
        'approval_note': 'Revoir les comparables',
      },
      'assignment': {
        'user_id': 'u1',
        'display_name': 'Julien M.',
        'initials': 'JM',
        'role': 'expert',
        'assigned_at': '2026-10-02T08:00:00Z',
        'note': 'Urgent',
      },
    };

    test('parses every section', () {
      final dossier = Dossier.fromJson(json);
      expect(dossier.id, 'p1');
      expect(dossier.role, StaffRole.expert);
      expect(dossier.status, DossierStatus.submitted);
      expect(dossier.propertyType, 'maison');
      expect(dossier.city, 'Chaponost');
      expect(dossier.areaM2, 115.5);
      expect(dossier.submittedAt, DateTime.utc(2026, 10, 1, 8));
      expect(dossier.sellerDeactivated, isTrue);
      expect(dossier.owners.first.displayName, 'Anne Probe');
      expect(dossier.owners.first.isMasked, isFalse);
      expect(dossier.owners.last.isMasked, isTrue);
      expect(dossier.owners.last.displayName, 'MP · Chaponost');
      expect(dossier.parcels, hasLength(1));
      expect(dossier.rooms.single.photosCount, 2);
      final [identity, rejected, verified] = dossier.documents;
      expect(identity.isIdentity, isTrue);
      expect(identity.toVerify, isTrue);
      expect(rejected.isRejected && rejected.isReplaced, isTrue);
      expect(rejected.toVerify, isFalse);
      expect(verified.isVerified, isTrue);
      expect(verified.kind, 'autre');
      expect(dossier.photosOf('r1').map((p) => p.id), ['ph2', 'ph1']);
      expect(dossier.photos.first.issues, ['dark']);
      expect(dossier.photos[1].issues, isEmpty);
      expect(dossier.voiceThread.single.undone, isTrue);
      expect(dossier.voiceThread.single.rejected, hasLength(1));
      expect(dossier.fillSheet.first.verified, isFalse);
      expect(dossier.fillSheet.last.label, 'area_m2');
      expect(dossier.market?['estimate_median_eur'], 500000);
      expect(dossier.lot?.members.single.accessible, isTrue);
      expect(dossier.valuation?['value_eur'], 525000);
      expect(dossier.draft?.version, 3);
      expect(dossier.draft?.approvalNote, 'Revoir les comparables');
      expect(dossier.assignment?.note, 'Urgent');
      expect(dossier.assignment?.role, StaffRole.expert);
      expect(dossier.props, hasLength(20));
      for (final part in <List<Object?>>[
        dossier.owners.first.props,
        dossier.documents.first.props,
        dossier.rooms.first.props,
        dossier.photos.first.props,
        dossier.fillSheet.first.props,
        dossier.voiceThread.first.props,
        dossier.lot!.props,
        dossier.lot!.members.first.props,
        dossier.draft!.props,
        dossier.assignment!.props,
      ]) {
        expect(part, isNotEmpty);
      }
    });

    test('a minimal dossier', () {
      final dossier = Dossier.fromJson(const {
        'property': {'id': 'p1', 'usable_area_m2': 18},
      });
      expect(dossier.role, StaffRole.partnerExpert);
      expect(dossier.areaM2, 18);
      expect(dossier.lot, isNull);
      expect(dossier.draft, isNull);
      expect(dossier.assignment, isNull);
      expect(dossier.sellerDeactivated, isFalse);
    });
  });

  group(ValuationDraft, () {
    test('defaults', () {
      final draft = ValuationDraft.fromJson(const {});
      expect(draft.payload, isEmpty);
      expect(draft.version, 0);
      expect(draft.status, ValuationDraftStatus.editing);
    });
  });

  group(AuditEntry, () {
    test('parses a journal line', () {
      final entry = AuditEntry.fromJson(const {
        'id': 7,
        'at': '2026-10-03T10:00:00Z',
        'actor_user_id': 'u1',
        'actor_role': 'expert',
        'actor_name': 'Julien M.',
        'action': 'certified',
        'property_id': 'p1',
        'target_type': 'valuation',
        'target_id': 'v1',
        'details': {'value_eur': 1},
      });
      expect(entry.action, 'certified');
      expect(entry.details, {'value_eur': 1});
      expect(entry.props, hasLength(10));
      final empty = AuditEntry.fromJson(const {});
      expect(empty.at, DateTime.fromMillisecondsSinceEpoch(0));
      expect(empty.actorRole, '');
      expect(empty.details, isEmpty);
    });
  });

  group(SignedFile, () {
    test('requests and answers', () {
      const request = FileRequest(FileKind.photo, 'ph1');
      expect(request.toJson(), {'type': 'photo', 'id': 'ph1'});
      expect(request.props, [FileKind.photo, 'ph1']);
      final file = SignedFile.fromJson(const {
        'type': 'report',
        'id': 'v1',
        'url': 'https://signed',
        'file_name': 'avis.pdf',
        'mime_type': 'application/pdf',
      });
      expect(file.kind, FileKind.report);
      expect(file.props, hasLength(5));
      expect(FileKind.parse('x'), FileKind.document);
    });
  });
}
