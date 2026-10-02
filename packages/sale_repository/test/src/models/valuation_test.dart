import 'package:sale_repository/sale_repository.dart';
import 'package:test/test.dart';

void main() {
  const minimal = {
    'id': 'v1',
    'property_id': 'p1',
    'value_eur': 525000,
    'low_eur': 505000,
    'high_eur': 545000,
    'expert_display_name': 'Julien M.',
    'certified_at': '2026-09-25T10:00:00Z',
    'valid_until': '2026-12-25',
  };

  group('Valuation.fromJson', () {
    test('reads the required columns with empty sections', () {
      final valuation = Valuation.fromJson(minimal);
      expect(
        valuation,
        Valuation(
          id: 'v1',
          propertyId: 'p1',
          valueEur: 525000,
          lowEur: 505000,
          highEur: 545000,
          expertDisplayName: 'Julien M.',
          certifiedAt: DateTime.utc(2026, 9, 25, 10),
          validUntil: DateTime(2026, 12, 25),
        ),
      );
      expect(valuation.hasReport, isFalse);
      expect(valuation.methodSteps, isEmpty);
    });

    test('reads every section and skips malformed entries', () {
      final valuation = Valuation.fromJson(const {
        ...minimal,
        'price_m2_eur': 4565,
        'ai_trend_eur': 518000,
        'estimated_delay_weeks': 8,
        'method_steps': [
          {'label': 'Tendance IA', 'amount_eur': 518000},
          {
            'label': 'Constat',
            'detail': 'luminosité',
            'amount_eur': 4000,
            'is_delta': true,
          },
          {'label': 'broken'},
          'not a map',
        ],
        'reasons': [
          {'text': 'Piscine', 'positive': true},
          {'text': 'Vis-à-vis', 'positive': false},
        ],
        'delay_curve': [
          {'price_eur': 505000, 'label': '≈ 5 semaines'},
        ],
        'expert_quote': '  Belle maison  ',
        'description': '',
        'technical_sheet': [
          {'label': 'DPE', 'value': 'C', 'provenance': 'verified'},
          {'label': 'Toit', 'value': 'Tuiles', 'provenance': 'unknown'},
        ],
        'comparables': [
          {
            'street': 'rue Lucien Cozon',
            'sold_on': '2025-10-01',
            'area_m2': 107,
            'land_m2': 576,
            'price_eur': 457000,
          },
          {
            'street': 'rue des Fauvettes',
            'price_eur': 674831,
            'excluded': true,
          },
        ],
        'comparables_note': 'Médiane retenue',
        'competitors_summary': '19 maisons',
        'competitors': [
          {
            'label': 'T5 · 113 m²',
            'price_eur': 429000,
            'note': 'Comparable',
            'days_online': 114,
          },
          {'label': 'T6', 'retained': false},
        ],
        'risks_note': 'Aucun risque',
        'adjustments': [
          {'label': 'Base', 'amount_eur': 489000, 'kind': 'base'},
          {'label': 'Piscine', 'amount_eur': 20000},
          {'label': 'Total', 'amount_eur': 528000, 'kind': 'total'},
        ],
        'method_summary': [
          {'label': 'IA', 'amount_eur': 518000, 'kind': 'control'},
        ],
        'works_label': 'Salle de bain',
        'works_estimate_eur': 5000,
        'sources': 'DVF',
        'expert_initials': 'JM',
        'report_storage_path': 'u/p/r.pdf',
        'report_pages': 11,
      });
      expect(valuation.priceM2Eur, 4565);
      expect(valuation.aiTrendEur, 518000);
      expect(valuation.estimatedDelayWeeks, 8);
      expect(valuation.methodSteps, const [
        ValuationMethodStep(label: 'Tendance IA', amountEur: 518000),
        ValuationMethodStep(
          label: 'Constat',
          detail: 'luminosité',
          amountEur: 4000,
          isDelta: true,
        ),
      ]);
      expect(valuation.reasons, const [
        ValuationReason(text: 'Piscine', positive: true),
        ValuationReason(text: 'Vis-à-vis', positive: false),
      ]);
      expect(valuation.delayCurve, const [
        ValuationDelayPoint(priceEur: 505000, label: '≈ 5 semaines'),
      ]);
      expect(valuation.expertQuote, 'Belle maison');
      expect(valuation.description, isNull);
      expect(valuation.technicalSheet, const [
        ValuationTechnicalItem(
          label: 'DPE',
          value: 'C',
          provenance: ValuationProvenance.verified,
        ),
        ValuationTechnicalItem(label: 'Toit', value: 'Tuiles'),
      ]);
      expect(valuation.comparables, [
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
      ]);
      expect(valuation.comparables.first.priceM2Eur, 4271);
      expect(valuation.comparables.last.priceM2Eur, isNull);
      expect(valuation.comparablesNote, 'Médiane retenue');
      expect(valuation.competitorsSummary, '19 maisons');
      expect(valuation.competitors, const [
        ValuationCompetitor(
          label: 'T5 · 113 m²',
          priceEur: 429000,
          note: 'Comparable',
          daysOnline: 114,
        ),
        ValuationCompetitor(label: 'T6', retained: false),
      ]);
      expect(valuation.risksNote, 'Aucun risque');
      expect(valuation.adjustments.map((line) => line.kind), [
        ValuationLineKind.base,
        ValuationLineKind.line,
        ValuationLineKind.total,
      ]);
      expect(valuation.methodSummary, const [
        ValuationAmountLine(
          label: 'IA',
          amountEur: 518000,
          kind: ValuationLineKind.control,
        ),
      ]);
      expect(valuation.worksLabel, 'Salle de bain');
      expect(valuation.worksEstimateEur, 5000);
      expect(valuation.sources, 'DVF');
      expect(valuation.expertInitials, 'JM');
      expect(valuation.reportPages, 11);
      expect(valuation.hasReport, isTrue);
    });

    test('ignores sections that are not lists', () {
      final valuation = Valuation.fromJson(const {
        ...minimal,
        'reasons': 'oops',
      });
      expect(valuation.reasons, isEmpty);
    });
  });
}
