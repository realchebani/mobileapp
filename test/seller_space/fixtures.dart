import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// A certified dossier like the V9 mockup.
const certifiedProperty = Property(
  id: 'property-id',
  ownerId: 'user-id',
  status: PropertyStatus.certified,
  currentStep: 8,
  propertyType: PropertyType.house,
  livingAreaM2: 115,
  roomsCount: 5,
  addressHousenumber: '12',
  addressStreet: 'rue de la Colombe',
  addressPostcode: '69630',
  addressCity: 'Chaponost',
  transparencyScore: 92,
  measurementMethod: MeasurementMethod.scan,
);

/// The V9b mockup report (sample data).
final testValuation = Valuation(
  id: 'valuation-id',
  propertyId: 'property-id',
  valueEur: 525000,
  lowEur: 505000,
  highEur: 545000,
  priceM2Eur: 4565,
  aiTrendEur: 518000,
  estimatedDelayWeeks: 8,
  expertDisplayName: 'Julien M.',
  expertInitials: 'JM',
  certifiedAt: DateTime(2026, 9, 25, 10),
  validUntil: DateTime(2026, 12, 25),
  reportStoragePath: 'user-id/property-id/report.pdf',
  reportPages: 11,
  methodSteps: const [
    ValuationMethodStep(
      label: 'Tendance IA',
      detail: 'avant la visite',
      amountEur: 518000,
    ),
    ValuationMethodStep(
      label: 'Constat de visite',
      detail: 'luminosité, état relevé',
      amountEur: 4000,
      isDelta: true,
    ),
    ValuationMethodStep(label: 'Valeur certifiée', amountEur: 525000),
  ],
  reasons: const [
    ValuationReason(text: 'Piscine et garage-atelier', positive: true),
    ValuationReason(text: 'Salle de bain à rafraîchir', positive: false),
  ],
  delayCurve: const [
    ValuationDelayPoint(priceEur: 505000, label: '≈ 5 semaines'),
    ValuationDelayPoint(priceEur: 525000, label: '≈ 8 semaines'),
    ValuationDelayPoint(priceEur: 555000, label: 'plus de 5 mois'),
    ValuationDelayPoint(priceEur: 585000, label: 'très peu de visites'),
  ],
  expertQuote: 'Ce bien réunit ce que les familles cherchent.',
  description: 'Maison familiale de 115 m² avec piscine.',
  technicalSheet: const [
    ValuationTechnicalItem(label: 'Construction', value: '1998 · parpaing'),
    ValuationTechnicalItem(
      label: 'Toiture',
      value: 'Tuiles · 2016',
      provenance: ValuationProvenance.document,
    ),
    ValuationTechnicalItem(
      label: 'Assainissement',
      value: 'Tout-à-l’égout',
      provenance: ValuationProvenance.external,
    ),
    ValuationTechnicalItem(
      label: 'DPE',
      value: 'Classe C',
      provenance: ValuationProvenance.verified,
    ),
  ],
  comparables: [
    ValuationComparable(
      street: 'rue Lucien Cozon',
      soldOn: DateTime(2025, 10),
      areaM2: 107,
      landM2: 576,
      priceEur: 457000,
    ),
    const ValuationComparable(
      street: 'rue des Fauvettes',
      priceEur: 674831,
      excluded: true,
    ),
  ],
  comparablesNote: 'Médiane retenue : 4 250 €/m².',
  competitorsSummary: '19 maisons en vente',
  competitors: const [
    ValuationCompetitor(
      label: 'T5 · 113 m²',
      priceEur: 429000,
      note: 'Comparable direct',
      daysOnline: 114,
    ),
    ValuationCompetitor(label: 'T6 · 120 m²', retained: false),
  ],
  risksNote: 'aucun risque d’inondation recensé',
  adjustments: const [
    ValuationAmountLine(
      label: 'Base ventes signées',
      amountEur: 489000,
      kind: ValuationLineKind.base,
    ),
    ValuationAmountLine(label: 'Piscine', amountEur: 20000),
    ValuationAmountLine(label: 'Vis-à-vis', amountEur: -5000),
    ValuationAmountLine(
      label: 'Méthode 1 corrigée',
      amountEur: 528000,
      kind: ValuationLineKind.total,
    ),
  ],
  methodSummary: const [
    ValuationAmountLine(
      label: 'Contrôle : tendance IA',
      amountEur: 518000,
      kind: ValuationLineKind.control,
    ),
  ],
  worksLabel: 'Salle de bain à rafraîchir',
  worksEstimateEur: 5000,
  sources: 'Base DVF · Géorisques',
);

/// Rooms on two levels plus an annex.
const testRooms = [
  Room(
    propertyId: 'property-id',
    name: 'Séjour',
    areaM2: 38.5,
    level: RoomLevel.groundFloor,
  ),
  Room(
    propertyId: 'property-id',
    name: 'Chambre 1',
    areaM2: 12.4,
    level: RoomLevel.firstFloor,
  ),
  Room(propertyId: 'property-id', name: 'Bureau', areaM2: 7),
  Room(propertyId: 'property-id', name: 'Garage', areaM2: 22, isAnnex: true),
];

/// The certification notification.
final testNotification = AppNotification(
  id: 'notification-id',
  kind: AppNotificationKind.valuationCertified,
  title: 'Votre avis de valeur certifié est disponible',
  body: 'Découvrez la valeur de votre bien.',
  route: '/vendeur/rapport',
  createdAt: DateTime(2026, 9, 25, 10, 5),
);
