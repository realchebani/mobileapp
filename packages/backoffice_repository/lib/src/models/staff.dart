import 'package:backoffice_repository/src/models/json.dart';
import 'package:equatable/equatable.dart';

/// Role of a team member (`staff_members.role`).
enum StaffRole {
  admin('admin'),
  expert('expert'),
  partnerExpert('partner_expert');

  new(this.value);

  final String value;

  static StaffRole? parse(Object? value) {
    for (final role in values) {
      if (role.value == value) return role;
    }
    return null;
  }
}

/// What the back-office may show to the caller (`bo_me().capabilities`).
enum BackOfficeCapability {
  queueAll('queue_all'),
  assign('assign'),
  take('take'),
  startReview('start_review'),
  editDraft('edit_draft'),
  certify('certify'),
  submitForApproval('submit_for_approval'),
  attachReport('attach_report'),
  verifyDocuments('verify_documents'),
  identityDocuments('identity_documents'),
  verifyIdentity('verify_identity'),
  team('team'),
  auditAll('audit_all');

  new(this.value);

  final String value;

  static Set<BackOfficeCapability> parseAll(Object? value) => {
    if (value is List)
      for (final capability in values)
        if (value.contains(capability.value)) capability,
  };
}

/// {@template staff_me}
/// The signed-in user as the back-office sees them (`bo_me()`).
/// {@endtemplate}
class StaffMe extends Equatable {
  /// {@macro staff_me}
  const new({
    required this.userId,
    required this.aal2,
    this.email,
    this.role,
    this.displayName,
    this.initials,
    this.organisation,
    this.capabilities = const {},
  });

  factory fromJson(JsonMap json) => StaffMe(
    userId: json['user_id'] as String,
    email: json['email'] as String?,
    role: StaffRole.parse(json['role']),
    displayName: json['display_name'] as String?,
    initials: json['initials'] as String?,
    organisation: json['organisation'] as String?,
    aal2: json['aal2'] == true,
    capabilities: BackOfficeCapability.parseAll(json['capabilities']),
  );

  final String userId;
  final String? email;

  /// Null when the user is not an active member of the team.
  final StaffRole? role;
  final String? displayName;
  final String? initials;
  final String? organisation;

  /// Whether the session passed the TOTP code.
  final bool aal2;
  final Set<BackOfficeCapability> capabilities;

  bool get isMember => role != null;

  bool can(BackOfficeCapability capability) =>
      capabilities.contains(capability);

  @override
  List<Object?> get props => [
    userId,
    email,
    role,
    displayName,
    initials,
    organisation,
    aal2,
    capabilities,
  ];
}

/// {@template staff_ref}
/// A team member named on a dossier (assignee, author of a draft).
/// {@endtemplate}
class StaffRef extends Equatable {
  /// {@macro staff_ref}
  const new({
    required this.userId,
    required this.displayName,
    this.initials,
    this.role,
    this.assignedAt,
    this.note,
  });

  factory fromJson(JsonMap json) => StaffRef(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String? ?? '',
    initials: json['initials'] as String?,
    role: StaffRole.parse(json['role']),
    assignedAt: Json.date(json['assigned_at']),
    note: Json.text(json['note']),
  );

  final String userId;
  final String displayName;
  final String? initials;
  final StaffRole? role;
  final DateTime? assignedAt;
  final String? note;

  @override
  List<Object?> get props => [
    userId,
    displayName,
    initials,
    role,
    assignedAt,
    note,
  ];
}

/// {@template staff_member}
/// A row of the team screen (`bo_list_team()`).
/// {@endtemplate}
class StaffMember extends Equatable {
  /// {@macro staff_member}
  const new({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.initials,
    required this.active,
    this.email,
    this.organisation,
    this.createdAt,
    this.deactivatedAt,
    this.mfaEnrolled = false,
    this.activeAssignments = 0,
  });

  factory fromJson(JsonMap json) => StaffMember(
    userId: json['user_id'] as String,
    email: json['email'] as String?,
    role: StaffRole.parse(json['role']) ?? StaffRole.expert,
    displayName: json['display_name'] as String? ?? '',
    initials: json['initials'] as String? ?? '',
    organisation: Json.text(json['organisation']),
    active: json['active'] != false,
    createdAt: Json.date(json['created_at']),
    deactivatedAt: Json.date(json['deactivated_at']),
    mfaEnrolled: json['mfa_enrolled'] == true,
    activeAssignments: Json.integer(json['active_assignments']) ?? 0,
  );

  final String userId;
  final String? email;
  final StaffRole role;
  final String displayName;
  final String initials;
  final String? organisation;
  final bool active;
  final DateTime? createdAt;
  final DateTime? deactivatedAt;
  final bool mfaEnrolled;
  final int activeAssignments;

  @override
  List<Object?> get props => [
    userId,
    email,
    role,
    displayName,
    initials,
    organisation,
    active,
    createdAt,
    deactivatedAt,
    mfaEnrolled,
    activeAssignments,
  ];
}
