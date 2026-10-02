import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  final l10n = AppLocalizationsFr();

  test('names, subtitles and icons of every type', () {
    expect(PropertyType.values.map((t) => propertyTypeName(l10n, t)), [
      'Maison',
      'Appartement',
      'Terrain',
      'Garage / parking',
      'Dépendance',
      'Local commercial',
      'Immeuble entier',
      'Autre',
    ]);
    expect(propertyTypeSubtitle(l10n, PropertyType.house), isNull);
    expect(propertyTypeSubtitle(l10n, PropertyType.parking), 'Box, place…');
    expect(
      propertyTypeSubtitle(l10n, PropertyType.outbuilding),
      'Cave, cellier, grange…',
    );
    expect(
      propertyTypeSubtitle(l10n, PropertyType.commercial),
      'Boutique, bureau…',
    );
    expect(
      propertyTypeSubtitle(l10n, PropertyType.building),
      'Plusieurs logements',
    );
    expect(propertyTypeSubtitle(l10n, PropertyType.other), 'Péniche, moulin…');
    expect([...PropertyType.values, null].map(propertyTypeIcon), [
      RealestyIcons.home,
      RealestyIcons.building,
      RealestyIcons.land,
      RealestyIcons.garage,
      RealestyIcons.cube,
      RealestyIcons.store,
      RealestyIcons.buildings,
      RealestyIcons.grid,
      RealestyIcons.grid,
    ]);
  });

  test('labels a property by its type, precision and address', () {
    const draft = Property(id: 'p', ownerId: 'u');
    expect(propertyTypeLabel(l10n, draft), isNull);
    expect(propertyShortLabel(l10n, draft), 'Nouveau bien');
    const barn = Property(
      id: 'p',
      ownerId: 'u',
      propertyType: PropertyType.outbuilding,
      propertyTypeOther: ' Grange ',
      addressCity: 'Chaponost',
    );
    expect(propertyTypeLabel(l10n, barn), 'Grange');
    expect(propertyShortLabel(l10n, barn), 'Grange · Chaponost');
    const house = Property(
      id: 'p',
      ownerId: 'u',
      propertyType: PropertyType.house,
      propertyTypeOther: 'ignored',
      addressHousenumber: '12',
      addressStreet: 'rue des Lilas',
      addressCity: 'Chaponost',
    );
    expect(propertyShortLabel(l10n, house), 'Maison · 12 rue des Lilas');
    const other = Property(
      id: 'p',
      ownerId: 'u',
      propertyType: PropertyType.other,
    );
    expect(propertyShortLabel(l10n, other), 'Autre');
  });

  test('statuses', () {
    const draft = Property(
      id: 'p',
      ownerId: 'u',
      propertyType: PropertyType.parking,
      currentStep: 7,
    );
    expect(propertyStatusLabel(l10n, draft), 'Brouillon · étape 5/5');
    expect(
      propertyStatusLabel(l10n, const Property(id: 'p', ownerId: 'u')),
      'Brouillon · étape 1/7',
    );
    String status(PropertyStatus status) => propertyStatusLabel(
      l10n,
      Property(id: 'p', ownerId: 'u', status: status),
    );
    expect(status(PropertyStatus.submitted), 'Envoyé');
    expect(status(PropertyStatus.inReview), 'Analyse en cours');
    expect(status(PropertyStatus.certified), 'Certifié');
  });
}
