import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/pending_answers_card.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

/// EPIC-16: V7 lists the answers still to confirm, never blocking.
void main() {
  testWidgets('lists them with « Voir », or nothing', (tester) async {
    final goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    await tester.pumpTunnelPage(
      const PendingAnswersCard(),
      sellerTunnelCubit: mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: testProperty,
          pendingAnswers: [
            PendingAnswer(
              id: 'a',
              propertyId: 'property-id',
              targetStep: 'technical',
              kind: PendingKind.field,
              field: 'construction_year',
              value: 1998,
              label: 'Construction 1998',
              quote: 'q',
              sourceStep: 'context',
            ),
            PendingAnswer(
              id: 'b',
              propertyId: 'property-id',
              targetStep: 'rooms',
              kind: PendingKind.room,
              value: {},
              label: 'Cuisine · 12 m²',
              quote: 'q',
              sourceStep: 'context',
            ),
          ],
        ),
      ),
      goRouter: goRouter,
    );
    expect(find.text('Informations dictées à confirmer (2)'), findsOneWidget);
    expect(find.text('Technique · Construction 1998'), findsOneWidget);
    expect(find.text('Pièces · Cuisine · 12 m²'), findsOneWidget);
    await tester.tap(find.text('Voir').first);
    verify(
      () => goRouter.go(SellerTunnelStep.technical.routeFor('property-id')),
    ).called(1);
  });

  testWidgets('shows nothing without pending answers', (tester) async {
    await tester.pumpTunnelPage(const PendingAnswersCard());
    expect(find.textContaining('Informations dictées'), findsNothing);
  });
}
