import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/location/widgets/parcel_card.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../../../helpers/helpers.dart';
import '../location_fixtures.dart';

void main() {
  testWidgets('shows a parcel with its cadastral area and source', (
    tester,
  ) async {
    await tester.pumpApp(ParcelCard(parcels: [testParcel]));
    expect(find.text('Section · Parcelle'), findsOneWidget);
    expect(find.text('AB · 98'), findsOneWidget);
    expect(find.text('Surface cadastrale'), findsOneWidget);
    expect(find.text('540\u00a0m²'), findsOneWidget);
    expect(find.byType(ProvenanceTag), findsOneWidget);
    expect(find.text('Source externe'), findsOneWidget);
    expect(
      find.text(
        'Registre cadastral · à confirmer avec votre titre de propriété',
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists several parcels with their total area', (tester) async {
    await tester.pumpApp(
      ParcelCard(
        parcels: [
          testParcel,
          eastParcel,
          squareParcel(idu: 'x', section: 'AC', numero: '0001', areaM2: null),
        ],
      ),
    );
    expect(find.text('AB · 98, AB · 99, AC · 1'), findsOneWidget);
    expect(find.text('850\u00a0m²'), findsOneWidget);
  });

  testWidgets('LocationErrorText shows an error', (tester) async {
    await tester.pumpApp(const LocationErrorText('Erreur'));
    expect(find.text('Erreur'), findsOneWidget);
  });
}
