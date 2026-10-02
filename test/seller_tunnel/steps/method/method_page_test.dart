import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/method/widgets/method_card.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

MethodCard _card(WidgetTester tester, String title) =>
    tester.widget<MethodCard>(find.widgetWithText(MethodCard, title));

void main() {
  group(MethodPage, () {
    testWidgets('shows the methods, only the manual entry is available', (
      tester,
    ) async {
      usePhoneSurface();
      await tester.pumpTunnelPage(const MethodPage());

      expect(find.text('Étape 5 · Pièces'), findsOneWidget);
      expect(find.text('5/7'), findsOneWidget);
      expect(
        find.text(
          'C’est le moment le plus important$_nbsp: la visite '
          'guidée$_nbsp! Comment préférez-vous relever vos pièces$_nbsp?',
        ),
        findsOneWidget,
      );
      expect(find.text('Bientôt'), findsNWidgets(2));
      // The available method comes first.
      expect(
        tester.getTopLeft(find.text('Saisir manuellement')).dy,
        lessThan(tester.getTopLeft(find.text('Scanner avec la caméra')).dy),
      );
      expect(_card(tester, 'Scanner avec la caméra').onTap, isNull);
      expect(_card(tester, 'Importer ou photographier un plan').onTap, isNull);
      final manual = _card(tester, 'Saisir manuellement');
      expect(manual.onTap, isNotNull);
      expect(manual.highlighted, isTrue);
      expect(
        find.text(
          'Les mesures réalisées au téléphone sont estimatives. Elles sont '
          'distinguées des surfaces issues d’un plan et vérifiées par '
          'l’expert.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AgentActionBar), findsNothing);
    });

    testWidgets('"Saisir manuellement" saves the method and continues', (
      tester,
    ) async {
      final cubit = mockSellerTunnelCubit();
      await tester.pumpTunnelPage(const MethodPage(), sellerTunnelCubit: cubit);

      await tester.tap(find.text('Saisir manuellement'));

      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.method, {
          PropertyColumns.measurementMethod: MeasurementMethod.manual,
        }),
      ).called(1);
    });

    testWidgets('is disabled with a spinner while saving', (tester) async {
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          saveStatus: SellerTunnelSaveStatus.inProgress,
          property: testProperty,
        ),
      );
      await tester.pumpTunnelPage(const MethodPage(), sellerTunnelCubit: cubit);

      final manual = _card(tester, 'Saisir manuellement');
      expect(manual.onTap, isNull);
      expect(manual.isLoading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('back goes to the technical audit', (tester) async {
      final router = MockGoRouter();
      when(() => router.go(any())).thenReturn(null);
      await tester.pumpTunnelPage(const MethodPage(), goRouter: router);

      await tester.tap(find.byType(RealestyIconButton).first);

      verify(() => router.go(auditRoute(SellerTunnelStep.technical))).called(1);
    });

    testWidgets('"Autre" can skip the rooms', (tester) async {
      usePhoneSurface();
      final router = MockGoRouter();
      when(() => router.go(any())).thenReturn(null);
      const other = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.other,
        ),
      );
      final cubit = mockSellerTunnelCubit(other);
      when(() => cubit.saveAndContinue(SellerTunnelStep.surfaces))
          .thenAnswer((_) async {
            when(() => cubit.state).thenReturn(
              other.copyWith(
                saveStatus: SellerTunnelSaveStatus.success,
                nextStep: SellerTunnelStep.lifestyle,
              ),
            );
          });
      await tester.pumpTunnelPage(
        const MethodPage(),
        sellerTunnelCubit: cubit,
        goRouter: router,
      );
      await tester.ensureVisible(find.text('Passer cette étape'));
      await tester.tap(find.text('Passer cette étape'));
      await tester.pump();
      verify(() => router.go('/vendeur/biens/p/audit/cadre-de-vie')).called(1);
    });

    testWidgets('a house cannot skip the rooms', (tester) async {
      await tester.pumpTunnelPage(const MethodPage());
      expect(find.text('Passer cette étape'), findsNothing);
    });
  });
}
