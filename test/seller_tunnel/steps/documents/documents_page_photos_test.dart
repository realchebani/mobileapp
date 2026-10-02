import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

PropertyDocument _document(String id, DocumentKind kind) => PropertyDocument(
  id: id,
  propertyId: 'property-id',
  kind: kind,
  storagePath: 'user-id/property-id/$id',
);

Room _room(String name, {int photos = 0}) => Room(
  id: name,
  propertyId: 'property-id',
  name: name,
  areaM2: 10,
  isMain: true,
  photosCount: photos,
);

SellerTunnelState _state({
  List<Room> rooms = const [],
  bool documents = true,
}) => SellerTunnelState(
  status: SellerTunnelStatus.success,
  property: const Property(
    id: 'property-id',
    ownerId: 'user-id',
    currentStep: 7,
    propertyType: PropertyType.house,
    sanitation: Sanitation.mainsSewer,
  ),
  documents: [
    if (documents) ...[
      _document('t', DocumentKind.titleDeed),
      _document('i', DocumentKind.identityDocument),
      _document('d', DocumentKind.diagnostics),
    ],
  ],
  rooms: rooms,
);

void main() {
  late MockGoRouter router;

  setUpAll(() {
    registerFallbackValue(SellerTunnelStep.owners);
  });

  setUp(() {
    router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester,
    SellerTunnelState state,
  ) async {
    usePhoneSurface();
    final cubit = mockSellerTunnelCubit(state);
    await tester.pumpTunnelPage(
      const DocumentsPage(),
      sellerTunnelCubit: cubit,
      goRouter: router,
    );
    return cubit;
  }

  Finder send() =>
      find.widgetWithText(RealestyButton, 'Envoyer mon dossier à l’expert');

  group('DocumentsPage · photos (EPIC-15)', () {
    testWidgets('the main rooms without a photo block the sending', (
      tester,
    ) async {
      final cubit = await pump(
        tester,
        _state(
          rooms: [
            _room('Séjour'),
            _room('Chambre 1'),
            _room('Bureau', photos: 1),
          ],
        ),
      );
      expect(
        find.text(
          'Une photo de chaque pièce principale est requise pour l’envoi',
        ),
        findsOneWidget,
      );
      await tester.tap(send());
      await tester.pumpAndSettle();
      verifyNever(() => cubit.saveAndContinue(any(), any()));
      expect(
        find.text('Ajoutez au moins une photo de$_nbsp: Séjour, Chambre 1.'),
        findsOneWidget,
      );
      // Tapped again: the message is revealed at once.
      await tester.tap(send());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ajouter les photos'));
      await tester.tap(find.text('Ajouter les photos'));
      await tester.pumpAndSettle();
      verify(() => router.go(SellerTunnelStep.surfaces.routeFor('property-id')))
          .called(1);
    });

    testWidgets('the documents are revealed before the photos', (tester) async {
      await pump(tester, _state(rooms: [_room('Séjour')], documents: false));
      expect(find.textContaining('pièce d’identité requis'), findsOneWidget);
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(
        find.text('Ajoutez au moins une photo de$_nbsp: Séjour.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Ajoutez les photos de vos pièces principales pour gagner des '
          'points.',
        ),
        findsNothing,
      );
    });

    testWidgets('the score points to the photos when they weigh most', (
      tester,
    ) async {
      await pump(tester, _state(rooms: [_room('Séjour')]));
      expect(
        find.text(
          'Ajoutez les photos de vos pièces principales pour gagner des '
          'points.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('with the photos, the dossier is sent', (tester) async {
      final cubit = await pump(
        tester,
        _state(rooms: [_room('Séjour', photos: 2)]),
      );
      await tester.tap(send());
      await tester.pumpAndSettle();
      verify(() => cubit.saveAndContinue(SellerTunnelStep.documents, any()))
          .called(1);
    });
  });
}
