import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/gen/app_localizations_fr.dart';

import '../../helpers/helpers.dart';

void main() {
  final l10n = AppLocalizationsFr();

  test('formats', () {
    final date = DateTime(2026, 10, 3, 9, 5);
    expect(dateFr(date), '03/10/2026');
    expect(dateTimeFr(date), '03/10/2026 09:05');
    expect(euros(525000), '525 000 €');
    expect(squareMeters(115), '115 m²');
    expect(squareMeters(32.5), '32,5 m²');
  });

  test('labels', () {
    expect(StaffRole.values.map((r) => r.label(l10n)), [
      'Administrateur',
      'Expert',
      'Expert partenaire',
    ]);
    expect(DossierStatus.values.map((s) => s.label(l10n)), [
      'Brouillon',
      'Envoyé',
      'En examen',
      'Certifié',
    ]);
    for (final type in [
      'maison',
      'appartement',
      'terrain',
      'stationnement',
      'dependance',
      'local_commercial',
      'immeuble',
    ]) {
      expect(propertyTypeLabel(l10n, type), isNot(l10n.typeAutre));
    }
    expect(propertyTypeLabel(l10n, 'autre'), l10n.typeAutre);
    expect(propertyTypeLabel(l10n, 'autre', 'Péniche'), 'Péniche');
  });

  test('failureText covers every reason', () {
    for (final reason in BackOfficeFailureReason.values) {
      expect(failureText(l10n, BackOfficeFailure(reason)), isNotEmpty);
    }
    expect(
      failureText(
        l10n,
        const BackOfficeFailure(
          BackOfficeFailureReason.draftConflict,
          details: 'Paul P.',
        ),
      ),
      contains('Paul P.'),
    );
    expect(failureText(l10n, Exception('x')), l10n.failureUnknown);
  });

  testWidgets('runGuarded tells success and failure', (tester) async {
    final session = sessionWith(adminMe);
    when(() => session.onFailure(any())).thenReturn(null);
    late BuildContext context;
    await tester.pumpBo(
      Builder(
        builder: (c) {
          context = c;
          return const BoCard(
            title: 'Titre',
            trailing: Text('Action'),
            child: Column(
              children: [
                BoChip('Puce'),
                BoMessage(title: 'Vide', body: 'Rien', action: Text('Go')),
              ],
            ),
          );
        },
      ),
      session: session,
    );
    expect(await runGuarded(context, () async {}, success: 'Fait'), isTrue);
    await tester.pump();
    expect(find.text('Fait'), findsOneWidget);
    final error = Exception('x');
    expect(await runGuarded(context, () async => throw error), isFalse);
    await tester.pump();
    expect(find.text(l10n.failureUnknown), findsOneWidget);
    verify(() => session.onFailure(error)).called(1);
    expect(find.text('Titre'), findsOneWidget);
  });
}
