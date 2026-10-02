import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  const nb = ' ';

  late AppLocalizations l10n;
  late BuildContext context;

  Future<void> setUpL10n(WidgetTester tester) async {
    await tester.pumpApp(
      Builder(
        builder: (builderContext) {
          context = builderContext;
          l10n = builderContext.l10n;
          return const SizedBox();
        },
      ),
    );
  }

  testWidgets('formats amounts, areas and dates', (tester) async {
    await setUpL10n(tester);
    expect(euros(l10n, 525000), '525${nb}000$nb€');
    expect(signedEuros(l10n, 4000), '+ 4${nb}000$nb€');
    expect(signedEuros(l10n, -5000), '− 5${nb}000$nb€');
    expect(squareMeters(l10n, 115), '115${nb}m²');
    expect(squareMeters(l10n, 38.5), '38,5${nb}m²');
    expect(longDate(context, DateTime(2026, 9, 25)), '25 septembre 2026');
  });

  testWidgets('labels the property type', (tester) async {
    await setUpL10n(tester);
    const base = Property(id: 'p', ownerId: 'u');
    String? label(Property property) => propertyTypeLabel(l10n, property);
    expect(label(base), isNull);
    expect(
      label(
        const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.house),
      ),
      'Maison',
    );
    expect(
      label(
        const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.apartment,
        ),
      ),
      'Appartement',
    );
    expect(
      label(
        const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      ),
      'Terrain',
    );
    expect(
      label(
        const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.other),
      ),
      'Autre',
    );
    expect(
      label(
        const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.other,
          propertyTypeOther: ' Local ',
        ),
      ),
      'Local',
    );
  });

  test('builds the address', () {
    expect(
      propertyAddress(
        const Property(
          id: 'p',
          ownerId: 'u',
          addressHousenumber: '12',
          addressStreet: 'rue de la Colombe',
          addressCity: 'Chaponost',
        ),
      ),
      '12 rue de la Colombe, Chaponost',
    );
    expect(
      propertyAddress(
        const Property(id: 'p', ownerId: 'u', addressStreet: 'rue A'),
      ),
      'rue A',
    );
    expect(
      propertyAddress(
        const Property(id: 'p', ownerId: 'u', addressLabel: 'Lieu-dit'),
      ),
      'Lieu-dit',
    );
  });
}
