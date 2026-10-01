import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_item_row.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_item_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/noise_slider.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _asset = LifestyleItem(
  id: 'a1',
  propertyId: 'property-id',
  kind: LifestyleItemKind.asset,
  label: 'École primaire à 4 min à pied',
);
const _watch = LifestyleItem(
  id: 'w1',
  propertyId: 'property-id',
  kind: LifestyleItemKind.watchPoint,
  label: 'Rue principale chargée',
);

void main() {
  late MockPropertyRepository repository;
  late MockGoRouter goRouter;

  setUpAll(() => registerFallbackValue(_asset));

  setUp(() {
    repository = MockPropertyRepository();
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => repository.deleteLifestyleItem(any())).thenAnswer((_) async {});
    when(() => repository.saveLifestyleItem(any()))
        .thenAnswer((i) async => i.positionalArguments.single as LifestyleItem);
  });

  MockSellerTunnelCubit tunnel({
    Property property = testProperty,
    List<LifestyleItem> items = const [],
    SellerTunnelSaveStatus saveStatus = SellerTunnelSaveStatus.idle,
  }) {
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        saveStatus: saveStatus,
        property: property,
        lifestyleItems: items,
      ),
    );
    when(
      () => cubit.updateChildren(lifestyleItems: any(named: 'lifestyleItems')),
    ).thenReturn(null);
    return cubit;
  }

  Future<void> pump(WidgetTester tester, SellerTunnelCubit cubit) async {
    usePhoneSurface();
    await tester.pumpTunnelPage(
      const LifestylePage(),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      goRouter: goRouter,
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder sheetField() => find.descendant(
    of: find.byType(LifestyleItemSheet),
    matching: find.byType(TextField),
  );

  group('LifestylePage', () {
    testWidgets('shows the screen mode and the saved answers', (tester) async {
      await pump(
        tester,
        tunnel(
          property: const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.house,
            noiseLevel: 3,
            overlooking: Overlooking.slight,
            secretNote: 'Boulangerie',
          ),
          items: [_asset, _watch],
        ),
      );
      expect(
        tester.widget<TunnelHeader>(find.byType(TunnelHeader)).mode,
        TunnelHeaderMode.screen,
      );
      expect(find.textContaining('atouts de la maison'), findsOneWidget);
      expect(find.text(_asset.label), findsOneWidget);
      expect(find.text(_watch.label), findsOneWidget);
      final icons = tester
          .widgetList<RealestyIcon>(find.byType(RealestyIcon))
          .map((icon) => icon.icon);
      expect(icons, containsAll([RealestyIcons.check, RealestyIcons.warning]));
      expect(find.text('3/10 · Calme'), findsOneWidget);
      expect(find.text('Boulangerie'), findsOneWidget);
      expect(find.text('11/500'), findsOneWidget);
      expect(find.text('Données du quartier'), findsOneWidget);
      expect(find.text('Toutes les questions sont facultatives'), findsOne);
      expect(find.bySemanticsLabel('1 atout'), findsOneWidget);
      expect(find.bySemanticsLabel('1 point de vigilance'), findsOneWidget);
    });

    testWidgets('adapts the question to the property type', (tester) async {
      await pump(
        tester,
        tunnel(
          property: const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.apartment,
          ),
        ),
      );
      expect(find.textContaining('atouts de l’appartement'), findsOneWidget);
      expect(find.text('Non renseigné'), findsOneWidget);
    });

    testWidgets('goes back to the surfaces', (tester) async {
      await pump(tester, tunnel());
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.sellerSurfaces)).called(1);
    });

    testWidgets('adds, edits and deletes items', (tester) async {
      await pump(tester, tunnel());
      expect(find.textContaining('du bien'), findsOneWidget);

      // Dismissed: nothing added.
      await tap(tester, find.text('Ajouter un atout'));
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.byType(LifestyleItemRow), findsNothing);

      await tap(tester, find.text('Ajouter un atout'));
      await tester.enterText(sheetField(), 'Calme absolu');
      await tap(tester, find.text('Ajouter').last);
      expect(find.text('Calme absolu'), findsOneWidget);

      await tap(tester, find.text('Ajouter un point'));
      expect(find.text('Ajouter un point de vigilance'), findsOneWidget);
      await tester.enterText(sheetField(), 'Voisins');
      await tap(tester, find.text('Ajouter').last);
      expect(find.text('Voisins'), findsOneWidget);

      await tap(tester, find.text('Calme absolu'));
      expect(find.text('Modifier l’atout'), findsOneWidget);
      await tester.enterText(sheetField(), 'Très calme le soir');
      await tap(tester, find.text('Enregistrer'));
      expect(find.text('Très calme le soir'), findsOneWidget);

      // Dismissed edit: unchanged.
      await tap(tester, find.text('Très calme le soir'));
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.text('Très calme le soir'), findsOneWidget);

      await tap(tester, find.text('Voisins'));
      expect(find.text('Modifier le point de vigilance'), findsOneWidget);
      await tap(tester, find.text('Supprimer'));
      expect(find.text('Voisins'), findsNothing);
    });

    testWidgets('replaces the add button once the list is full', (
      tester,
    ) async {
      await pump(
        tester,
        tunnel(
          items: [
            for (var i = 0; i < lifestyleItemsMax; i++)
              LifestyleItem(
                id: 'w$i',
                propertyId: 'property-id',
                kind: LifestyleItemKind.watchPoint,
                label: 'Point $i',
                sortOrder: i,
              ),
          ],
        ),
      );
      expect(find.text('Ajouter un point'), findsNothing);
      expect(find.text('Maximum atteint (10)'), findsOneWidget);
    });

    testWidgets('saves the answers and continues', (tester) async {
      final cubit = tunnel(items: [_asset]);
      await pump(tester, cubit);
      await tester.ensureVisible(find.byType(NoiseSlider));
      await tester.pumpAndSettle();
      final slider = tester.getRect(find.byType(NoiseSlider));
      // Level 8 on the track (inset 14 on each side).
      await tester.tapAt(
        Offset(slider.left + 14 + (slider.width - 28) * 7 / 9, slider.top + 18),
      );
      await tester.pumpAndSettle();
      expect(find.text('8/10 · Bruyant'), findsOneWidget);
      await tap(tester, find.text('Important'));
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(
            RealestyTextField,
            'Note secrète pour les futurs visiteurs',
          ),
          matching: find.byType(TextField),
        ),
        ' Marché le dimanche ',
      );
      await tap(tester, find.text('Continuer'));

      verify(() => cubit.updateChildren(lifestyleItems: [_asset])).called(1);
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.lifestyle, {
          PropertyColumns.noiseLevel: 8,
          PropertyColumns.overlooking: Overlooking.significant,
          PropertyColumns.secretNote: 'Marché le dimanche',
          PropertyColumns.provenance: {
            PropertyColumns.noiseLevel: 'declared',
            PropertyColumns.overlooking: 'declared',
            PropertyColumns.secretNote: 'declared',
          },
        }),
      ).called(1);
    });

    testWidgets('shows an error when the items cannot be saved', (
      tester,
    ) async {
      when(() => repository.saveLifestyleItem(any()))
          .thenThrow(Exception('offline'));
      final cubit = tunnel();
      await pump(tester, cubit);
      await tap(tester, find.text('Ajouter un atout'));
      await tester.enterText(sheetField(), 'Calme');
      await tap(tester, find.text('Ajouter').last);
      await tap(tester, find.text('Continuer'));
      expect(
        find.text(
          'L’enregistrement a échoué. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
    });

    testWidgets('disables the inputs while the tunnel saves', (tester) async {
      final cubit = tunnel(
        items: [_asset],
        saveStatus: SellerTunnelSaveStatus.inProgress,
      );
      await pump(tester, cubit);
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
      expect(
        tester.widget<LifestyleItemRow>(find.byType(LifestyleItemRow)).onEdit,
        isNull,
      );
      expect(
        tester.widget<TunnelHeader>(find.byType(TunnelHeader)).onBack,
        isNull,
      );
      expect(
        tester.widget<NoiseSlider>(find.byType(NoiseSlider)).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<RealestySegmentedControl<Overlooking?>>(
              find.byType(RealestySegmentedControl<Overlooking?>),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<RealestyTextField>(find.byType(RealestyTextField))
            .enabled,
        isFalse,
      );
    });

    testWidgets('disables the inputs while the items are saved', (
      tester,
    ) async {
      final completer = Completer<LifestyleItem>();
      when(() => repository.saveLifestyleItem(any()))
          .thenAnswer((_) => completer.future);
      final cubit = tunnel();
      whenListen(
        cubit,
        const Stream<SellerTunnelState>.empty(),
        initialState: cubit.state,
      );
      await pump(tester, cubit);
      await tap(tester, find.text('Ajouter un atout'));
      await tester.enterText(sheetField(), 'Calme');
      await tap(tester, find.text('Ajouter').last);
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
      completer.complete(_asset);
      await tester.pumpAndSettle();
    });
  });

  group('noiseLevelLabel / noiseBadgeVariant', () {
    testWidgets('map every level', (tester) async {
      await pump(tester, tunnel());
      final l10n = tester.element(find.byType(LifestyleView)).l10n;
      expect(
        [for (var l = 1; l <= 10; l++) noiseLevelLabel(l10n, l)],
        [
          'Très calme',
          'Très calme',
          'Calme',
          'Calme',
          'Modéré',
          'Modéré',
          'Bruyant',
          'Bruyant',
          'Très bruyant',
          'Très bruyant',
        ],
      );
      expect(noiseBadgeVariant(null), RealestyBadgeVariant.neutral);
      expect(noiseBadgeVariant(4), RealestyBadgeVariant.certified);
      expect(noiseBadgeVariant(6), RealestyBadgeVariant.toComplete);
      expect(noiseBadgeVariant(7), RealestyBadgeVariant.missing);
    });
  });
}
