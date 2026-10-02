import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  late MockGoRouter goRouter;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
  });

  Future<void> pump(WidgetTester tester, List<Property> properties) {
    return tester.pumpApp(
      BlocProvider<SellerPropertiesCubit>.value(
        value: mockSellerPropertiesCubit(properties: properties),
        child: const LegacySellerRedirect(segments: ['audit', 'technique']),
      ),
      goRouter: goRouter,
    );
  }

  group(LegacySellerRedirect, () {
    testWidgets('opens the screen of the most recently updated property', (
      tester,
    ) async {
      await pump(tester, [
        Property(id: 'old', ownerId: 'u', updatedAt: DateTime(2026)),
        Property(id: 'new', ownerId: 'u', updatedAt: DateTime(2026, 9)),
        const Property(id: 'unknown', ownerId: 'u'),
      ]);
      await tester.pump();
      verify(() => goRouter.go('/vendeur/biens/new/audit/technique')).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('opens the seller space without property', (tester) async {
      await pump(tester, const []);
      await tester.pump();
      verify(() => goRouter.go('/vendeur')).called(1);
    });
  });

  group(FirstPropertyScope, () {
    testWidgets('provides the dossier of the first property', (tester) async {
      final tunnel = mockSellerTunnelCubit();
      await tester.pumpApp(
        RepositoryProvider<SellerTunnelCubits>.value(
          value: mockSellerTunnelCubits(tunnel),
          child: BlocProvider<SellerPropertiesCubit>.value(
            value: mockSellerPropertiesCubit(),
            child: FirstPropertyScope(
              child: Builder(
                builder: (context) =>
                    Text(context.read<SellerTunnelCubit>().state.property!.id),
              ),
            ),
          ),
        ),
      );
      expect(find.text('property-id'), findsOneWidget);
    });

    testWidgets('shows the child alone without property', (tester) async {
      await tester.pumpApp(
        BlocProvider<SellerPropertiesCubit>.value(
          value: mockSellerPropertiesCubit(properties: const []),
          child: const FirstPropertyScope(child: Text('child')),
        ),
      );
      expect(find.text('child'), findsOneWidget);
    });
  });

  group('SellerTunnelNavigation', () {
    testWidgets('leaves the tunnel for the page of one property among '
        'several', (tester) async {
      await tester.pumpTunnelPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => context.goBackFrom(SellerTunnelStep.owners),
            child: const Text('back'),
          ),
        ),
        sellerPropertiesCubit: mockSellerPropertiesCubit(
          properties: const [
            testProperty,
            Property(id: 'other', ownerId: 'user-id'),
          ],
        ),
        goRouter: goRouter,
      );
      await tester.tap(find.text('back'));
      verify(() => goRouter.go('/vendeur/biens/property-id')).called(1);
    });
  });
}
