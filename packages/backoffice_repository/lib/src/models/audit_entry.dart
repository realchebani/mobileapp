import 'package:backoffice_repository/src/models/json.dart';
import 'package:equatable/equatable.dart';

/// {@template audit_entry}
/// A line of `staff_audit_log` (`bo_audit`).
/// {@endtemplate}
class AuditEntry extends Equatable {
  /// {@macro audit_entry}
  const new({
    required this.id,
    required this.at,
    required this.actorRole,
    required this.action,
    this.actorUserId,
    this.actorName,
    this.propertyId,
    this.targetType,
    this.targetId,
    this.details = const {},
  });

  factory fromJson(JsonMap json) => AuditEntry(
    id: Json.integer(json['id']) ?? 0,
    at: Json.date(json['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    actorUserId: json['actor_user_id'] as String?,
    actorRole: json['actor_role'] as String? ?? '',
    actorName: json['actor_name'] as String?,
    action: json['action'] as String? ?? '',
    propertyId: json['property_id'] as String?,
    targetType: json['target_type'] as String?,
    targetId: json['target_id'] as String?,
    details: Json.map(json['details']) ?? const {},
  );

  final int id;
  final DateTime at;
  final String? actorUserId;
  final String actorRole;
  final String? actorName;
  final String action;
  final String? propertyId;
  final String? targetType;
  final String? targetId;
  final JsonMap details;

  @override
  List<Object?> get props => [
    id,
    at,
    actorUserId,
    actorRole,
    actorName,
    action,
    propertyId,
    targetType,
    targetId,
    details,
  ];
}
