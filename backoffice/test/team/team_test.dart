import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/team/team.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

Finder field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(EditableText),
);

void main() {
  late MockBackOfficeRepository repository;

  setUp(() {
    repository = MockBackOfficeRepository();
    when(() => repository.listTeam()).thenAnswer(
      (_) async => [
        ...team.take(2),
        StaffMember(
          userId: 'old-1',
          role: StaffRole.expert,
          displayName: 'Ancien',
          initials: 'AN',
          active: false,
          deactivatedAt: DateTime(2026, 9, 30),
          mfaEnrolled: true,
        ),
        const StaffMember(
          userId: 'admin-1',
          role: StaffRole.admin,
          displayName: 'Maxime C.',
          initials: 'MC',
          active: true,
        ),
      ],
    );
    when(
      () => repository.upsertMember(
        email: any(named: 'email'),
        role: any(named: 'role'),
        displayName: any(named: 'displayName'),
        initials: any(named: 'initials'),
        organisation: any(named: 'organisation'),
      ),
    ).thenAnswer((_) async => 'u');
    when(() => repository.deactivateMember(any())).thenAnswer((_) async {});
  });

  blocTest<TeamCubit, TeamState>(
    'loads, fails',
    build: () => TeamCubit(repository: repository),
    act: (cubit) async {
      await cubit.load();
      when(() => repository.listTeam()).thenThrow(Exception('x'));
      await expectLater(cubit.load(), throwsException);
    },
    verify: (cubit) => expect(cubit.state.status, TeamStatus.failure),
  );

  testWidgets('lists, adds, edits and removes members', (tester) async {
    tester.useDesktopSurface();
    await tester.pumpBo(const TeamPage(), repository: repository);
    await tester.pump();
    expect(find.text('Julien M.'), findsOneWidget);
    expect(find.textContaining('Retiré le 30/09/2026'), findsOneWidget);
    expect(find.textContaining('Activée'), findsOneWidget);
    expect(find.text('Retirer l’accès'), findsNWidgets(2));

    await tester.tap(find.text('Ajouter un membre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.textContaining('Renseignez'), findsOneWidget);
    await tester.enterText(
      field('Adresse e-mail du compte'),
      'rita@cabinet.fr',
    );
    await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expert partenaire').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Accord de confidentialité'), findsOneWidget);
    await tester.enterText(
      field('Nom affiché au vendeur (ex. : Julien M.)'),
      'Rita R.',
    );
    await tester.enterText(field('Initiales (1 à 3)'), 'rr');
    await tester.enterText(field('Cabinet (expert partenaire)'), 'Cabinet R');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    verify(
      () => repository.upsertMember(
        email: 'rita@cabinet.fr',
        role: StaffRole.partnerExpert,
        displayName: 'Rita R.',
        initials: 'RR',
        organisation: 'Cabinet R',
      ),
    ).called(1);

    await tester.tap(find.text('Modifier').first);
    await tester.pumpAndSettle();
    expect(find.text('Modifier le membre'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retirer l’accès').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.deactivateMember(any()));
    await tester.tap(find.text('Retirer l’accès').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Retirer l’accès').last);
    await tester.pumpAndSettle();
    verify(() => repository.deactivateMember('expert-1')).called(1);
  });

  testWidgets('empty team, then a failure and a retry', (tester) async {
    tester.useDesktopSurface();
    when(() => repository.listTeam()).thenAnswer((_) async => []);
    await tester.pumpBo(const TeamPage(), repository: repository);
    await tester.pump();
    expect(find.text('Aucun membre.'), findsOneWidget);
    when(() => repository.listTeam()).thenThrow(Exception('x'));
    await tester.tap(find.text('Ajouter un membre'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Adresse e-mail du compte'), 'a@b.fr');
    await tester.enterText(
      field('Nom affiché au vendeur (ex. : Julien M.)'),
      'A',
    );
    await tester.enterText(field('Initiales (1 à 3)'), 'A');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('L’équipe n’a pas pu être chargée.'), findsOneWidget);
    when(() => repository.listTeam()).thenAnswer((_) async => team);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(find.text('Paul P.'), findsOneWidget);
  });
}
