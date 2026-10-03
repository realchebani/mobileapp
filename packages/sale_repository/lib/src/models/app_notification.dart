import 'package:equatable/equatable.dart';

/// What an [AppNotification] is about (`notifications.kind`).
enum AppNotificationKind {
  /// An expert took the dossier over (`review_started`).
  reviewStarted('review_started'),

  /// The certified valuation is available (`valuation_certified`).
  valuationCertified('valuation_certified'),

  /// The test mandate of a sale is signed (EPIC-08).
  mandateSigned('mandate_signed'),

  /// A listing is online (EPIC-08).
  listingPublished('listing_published'),

  /// The team verified an owner's identity (EPIC-08).
  identityVerified('identity_verified'),

  /// The team planned, closed or cancelled a service request (EPIC-08).
  saleRequestUpdated('sale_request_updated'),

  /// A sale was withdrawn (EPIC-08).
  saleWithdrawn('sale_withdrawn'),

  /// A kind this version of the app does not know.
  other('other');

  new(this.value);

  /// Value stored in the database.
  final String value;

  static AppNotificationKind parse(Object? value) =>
      values.firstWhere((kind) => kind.value == value, orElse: () => other);
}

/// An in-app notification of the signed-in user (`notifications` table).
class AppNotification extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.propertyId,
    this.route,
    this.readAt,
  });

  factory fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    kind: AppNotificationKind.parse(json['kind']),
    title: json['title'] as String,
    body: json['body'] as String?,
    propertyId: json['property_id'] as String?,
    route: json['route'] as String?,
    readAt: json['read_at'] == null
        ? null
        : DateTime.parse(json['read_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final AppNotificationKind kind;
  final String title;
  final String? body;

  /// The property the notification is about, if any.
  final String? propertyId;

  /// App location to open (e.g. `/vendeur/rapport`).
  final String? route;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    propertyId: propertyId,
    route: route,
    readAt: readAt ?? at,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    body,
    propertyId,
    route,
    readAt,
    createdAt,
  ];
}
