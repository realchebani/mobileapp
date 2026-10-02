import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  const draft = Property(
    id: 'property-id',
    ownerId: 'user-id',
    propertyType: PropertyType.house,
    lotId: 'lot',
  );
  const garage = Property(
    id: 'garage',
    ownerId: 'user-id',
    propertyType: PropertyType.parking,
    lotId: 'lot',
  );

  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  group(PropertyHomePage, () {
    testWidgets('a property of a lot, among several', (tester) async {
      await tester.pumpSellerSpacePage(
        const PropertyHomePage(showBack: true),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: draft,
          ),
        ),
        sellerPropertiesCubit: mockSellerPropertiesCubit(
          properties: const [draft, garage],
          lots: const [PropertyLot(id: 'lot', ownerId: 'user-id')],
        ),
        goRouter: goRouter,
      );
      expect(find.byType(SellerHomePage), findsOneWidget);
      expect(find.text('Fait partie du lot Lot de 2 biens'), findsOneWidget);
      expect(find.text('Ajouter un bien'), findsNothing);

      await tester.tap(find.text('Fait partie du lot Lot de 2 biens'));
      verify(() => goRouter.go('/vendeur/lots/lot')).called(1);
      await tester.tap(find.bySemanticsLabel('Mes biens'));
      verify(() => goRouter.go('/vendeur')).called(1);
    });

    testWidgets('the only property offers to add another one', (tester) async {
      await tester.pumpSellerSpacePage(
        const PropertyHomePage(),
        goRouter: goRouter,
      );
      expect(find.byType(DashboardPage), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Ajouter un bien'), 200);
      await tester.tap(find.text('Ajouter un bien'));
      verify(() => goRouter.push<Object?>('/vendeur/biens/nouveau')).called(1);
      expect(find.bySemanticsLabel('Mes biens'), findsNothing);
    });

    testWidgets('nothing below a property of several, in no lot', (
      tester,
    ) async {
      await tester.pumpSellerSpacePage(
        const PropertyHomePage(),
        sellerTunnelCubit: mockSellerTunnelCubit(),
        sellerPropertiesCubit: mockSellerPropertiesCubit(
          properties: const [testProperty, garage],
        ),
        goRouter: goRouter,
      );
      expect(find.byType(PropertyHomeFooter), findsOneWidget);
      expect(find.text('Ajouter un bien'), findsNothing);
      expect(find.textContaining('Fait partie du lot'), findsNothing);
    });
  });
}
