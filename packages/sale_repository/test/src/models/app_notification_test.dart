import 'package:sale_repository/sale_repository.dart';
import 'package:test/test.dart';

void main() {
  group('AppNotification', () {
    test('fromJson reads a row', () {
      final notification = AppNotification.fromJson(const {
        'id': 'n1',
        'kind': 'valuation_certified',
        'title': 'Disponible',
        'body': 'Corps',
        'property_id': 'p1',
        'route': '/vendeur/biens/p1/rapport',
        'read_at': '2026-09-26T08:00:00Z',
        'created_at': '2026-09-25T10:00:00Z',
      });
      expect(
        notification,
        AppNotification(
          id: 'n1',
          kind: AppNotificationKind.valuationCertified,
          title: 'Disponible',
          body: 'Corps',
          propertyId: 'p1',
          route: '/vendeur/biens/p1/rapport',
          readAt: DateTime.utc(2026, 9, 26, 8),
          createdAt: DateTime.utc(2026, 9, 25, 10),
        ),
      );
      expect(notification.isRead, isTrue);
    });

    test('unknown kinds parse as other', () {
      final notification = AppNotification.fromJson(const {
        'id': 'n1',
        'kind': 'new_offer',
        'title': 'Offre',
        'created_at': '2026-09-25T10:00:00Z',
      });
      expect(notification.kind, AppNotificationKind.other);
      expect(notification.isRead, isFalse);
      expect(
        AppNotificationKind.parse('review_started'),
        AppNotificationKind.reviewStarted,
      );
    });

    test('markedRead keeps an earlier read time', () {
      final created = DateTime.utc(2026);
      final first = DateTime.utc(2026, 2);
      final unread = AppNotification(
        id: 'n1',
        kind: AppNotificationKind.reviewStarted,
        title: 'T',
        createdAt: created,
      );
      final read = unread.markedRead(first);
      expect(read.readAt, first);
      expect(read.markedRead(DateTime.utc(2026, 3)).readAt, first);
      expect(read.title, 'T');
    });
  });
}
