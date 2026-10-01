import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_card.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/widgets/co_owner_sheet.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _owner1 = PropertyOwner(
  id: 'o1',
  propertyId: 'property-id',
  position: 1,
  profileId: 'user-id',
  firstName: 'Sophie',
  lastName: 'Durand',
  phone: '+33612345678',
  email: 'sophie@email.fr',
);
const _owner2 = PropertyOwner(
  id: 'o2',
  propertyId: 'property-id',
  position: 2,
  firstName: 'Marc',
  lastName: 'Durand',
  phone: '+33698765432',
);

/// The text field labelled [label] in [scope] (the whole page by default).
Finder _field(String label, {Finder? scope}) {
  final field = find.widgetWithText(RealestyTextField, label);
  return find.descendant(
    of: scope == null
        ? field.first
        : find.descendant(of: scope, matching: field),
    matching: find.byType(TextField),
  );
}

Finder _sheetField(String label) =>
    _field(label, scope: find.byType(CoOwnerSheet));

void main() {
  late MockPropertyRepository repository;
  late MockGoRouter goRouter;

  setUpAll(() => registerFallbackValue(_owner1));

  setUp(() {
    repository = MockPropertyRepository();
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => repository.deleteOwner(any())).thenAnswer((_) async {});
    when(() => repository.saveOwner(any())).thenAnswer((invocation) async {
      final row = invocation.positionalArguments.single as PropertyOwner;
      return row.id != null
          ? row
          : PropertyOwner(
              id: 'new-${row.position}',
              propertyId: row.propertyId,
              position: row.position,
              profileId: row.profileId,
              firstName: row.firstName,
              lastName: row.lastName,
              phone: row.phone,
              email: row.email,
            );
    });
  });

  MockSellerTunnelCubit tunnel({
    List<PropertyOwner> owners = const [],
    OwnershipType? ownershipType,
    SellerTunnelSaveStatus saveStatus = SellerTunnelSaveStatus.idle,
  }) {
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        saveStatus: saveStatus,
        property: Property(
          id: testProperty.id,
          ownerId: testProperty.ownerId,
          ownershipType: ownershipType,
        ),
        owners: owners,
      ),
    );
    when(() => cubit.updateChildren(owners: any(named: 'owners')))
        .thenReturn(null);
    return cubit;
  }

  Future<void> pump(
    WidgetTester tester,
    SellerTunnelCubit cubit, {
    String? firstName,
    String? email,
  }) async {
    usePhoneSurface();
    final profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      ProfileState(
        status: ProfileStatus.success,
        profile: Profile(id: 'user-id', firstName: firstName),
      ),
    );
    final appBloc = MockAppBloc();
    when(
      () => appBloc.state,
    ).thenReturn(AppState.authenticated(AuthUser(id: 'user-id', email: email)));
    await tester.pumpTunnelPage(
      BlocProvider<ProfileCubit>.value(
        value: profileCubit,
        child: const OwnersPage(),
      ),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      appBloc: appBloc,
      goRouter: goRouter,
    );
  }

  AgentActionBar actionBar(WidgetTester tester) =>
      tester.widget<AgentActionBar>(find.byType(AgentActionBar));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group(OwnersPage, () {
    testWidgets('prefills owner 1 from the profile and the account', (
      tester,
    ) async {
      await pump(tester, tunnel(), firstName: 'Sophie', email: 's@email.fr');

      expect(find.text('Étape 1 · Propriétaires'), findsOneWidget);
      expect(
        find.textContaining('êtes-vous le seul et unique propriétaire'),
        findsOneWidget,
      );
      expect(find.text('PROPRIÉTAIRE 1 · VOUS'), findsOneWidget);
      expect(find.text('Sophie'), findsOneWidget);
      expect(find.text('s@email.fr'), findsOneWidget);
      expect(find.text('Ajouter un co-propriétaire'), findsNothing);

      // "Continuer" shows what is missing and saves nothing.
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indiquez si vous êtes le seul propriétaire'),
        findsOneWidget,
      );
      expect(find.text('Champ obligatoire'), findsNWidgets(2));
      verifyNever(() => repository.saveOwner(any()));

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.seller)).called(1);
    });

    testWidgets('shows field errors once left', (tester) async {
      await pump(tester, tunnel());

      await tester.showKeyboard(_field('Prénom'));
      await tester.enterText(_field('Téléphone'), '06');
      await tester.enterText(_field('E-mail'), 'x');
      await tester.showKeyboard(_field('Nom'));
      await tester.pump();

      expect(find.text('Champ obligatoire'), findsOneWidget);
      expect(
        find.text(
          'Numéro invalide, par exemple 06\u00a012\u00a034\u00a056\u00a078',
        ),
        findsOneWidget,
      );
      expect(find.text('Adresse e-mail invalide'), findsOneWidget);
    });

    testWidgets('saves a single owner and continues', (tester) async {
      final cubit = tunnel();
      await pump(tester, cubit, firstName: 'Sophie', email: 's@email.fr');

      await tester.tap(find.text('Plusieurs propriétaires'));
      await tester.pump();
      expect(find.text('Ajouter un co-propriétaire'), findsOneWidget);
      await tester.tap(find.text('Unique propriétaire'));
      await tester.enterText(_field('Nom'), 'Durand');
      await tester.enterText(_field('Téléphone'), '06 12 34 56 78');
      await tester.pump();

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      final saved =
          verify(() => repository.saveOwner(captureAny())).captured.single
              as PropertyOwner;
      expect(saved.phone, '+33612345678');
      expect(saved.profileId, 'user-id');
      verify(
        () => cubit.updateChildren(
          owners: const [
            PropertyOwner(
              id: 'new-1',
              propertyId: 'property-id',
              position: 1,
              profileId: 'user-id',
              firstName: 'Sophie',
              lastName: 'Durand',
              phone: '+33612345678',
              email: 's@email.fr',
            ),
          ],
        ),
      ).called(1);
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.owners, {
          PropertyColumns.ownershipType: OwnershipType.single,
        }),
      ).called(1);
    });

    testWidgets('adds, edits and removes co-owners', (tester) async {
      final cubit = tunnel(
        owners: [_owner1, _owner2],
        ownershipType: OwnershipType.multiple,
      );
      await pump(tester, cubit);

      expect(find.byType(CoOwnerCard), findsOneWidget);
      expect(
        find.text('Co-propriétaire · 06\u00a098\u00a076\u00a054\u00a032'),
        findsOneWidget,
      );

      // Edit Marc.
      await tapVisible(tester, find.bySemanticsLabel('Modifier Marc Durand'));
      await tester.enterText(_sheetField('Prénom'), 'Marcel');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Marcel Durand'), findsOneWidget);

      // Cancel an edit.
      await tapVisible(tester, find.bySemanticsLabel('Modifier Marcel Durand'));
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('Marcel Durand'), findsOneWidget);

      // Add Léa, then cancel an addition.
      await tapVisible(tester, find.text('Ajouter un co-propriétaire'));
      await tester.enterText(_sheetField('Prénom'), 'Léa');
      await tester.enterText(_sheetField('Nom'), 'Roy');
      await tester.enterText(_sheetField('Téléphone'), '07 11 22 33 44');
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Ajouter un co-propriétaire'));
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CoOwnerCard), findsNWidgets(2));

      // Remove Marcel.
      await tapVisible(tester, find.bySemanticsLabel('Modifier Marcel Durand'));
      await tester.tap(find.text('Supprimer ce co-propriétaire'));
      await tester.pumpAndSettle();
      expect(find.byType(CoOwnerCard), findsOneWidget);

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      verify(() => repository.deleteOwner('o2')).called(1);
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.owners, {
          PropertyColumns.ownershipType: OwnershipType.multiple,
        }),
      ).called(1);

      // Switching to a single owner hides the co-owners.
      await tester.ensureVisible(find.text('Unique propriétaire'));
      await tester.tap(find.text('Unique propriétaire'));
      await tester.pump();
      expect(find.byType(CoOwnerCard), findsNothing);
    });

    testWidgets('shows an error when saving fails', (tester) async {
      when(() => repository.saveOwner(any()))
          .thenThrow(const PropertySaveFailure());
      final cubit = tunnel(
        owners: [_owner1],
        ownershipType: OwnershipType.single,
      );
      await pump(tester, cubit);
      await tester.enterText(_field('Téléphone'), '07 00 00 00 00');
      await tester.pump();

      await tester.tap(find.text('Continuer'));
      await tester.pump();
      expect(
        find.text(
          'L’enregistrement a échoué. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
    });

    testWidgets('reveals the missing co-owner and the invalid fields', (
      tester,
    ) async {
      final cubit = tunnel(
        owners: [_owner1],
        ownershipType: OwnershipType.multiple,
      );
      await pump(tester, cubit);
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Ajoutez au moins un co-propriétaire'), findsOneWidget);

      await tester.enterText(_field('E-mail'), 'x');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Adresse e-mail invalide'), findsOneWidget);
      verifyNever(() => repository.saveOwner(any()));
    });

    testWidgets('disables the form while saving the owners', (tester) async {
      final completer = Completer<PropertyOwner>();
      when(() => repository.saveOwner(any()))
          .thenAnswer((_) => completer.future);
      final cubit = tunnel(
        owners: [_owner1],
        ownershipType: OwnershipType.single,
      );
      await pump(tester, cubit);
      await tester.enterText(_field('Téléphone'), '07 00 00 00 00');
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      expect(actionBar(tester).isLoading, isTrue);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      for (final card in tester.widgetList<SelectableCard>(
        find.byType(SelectableCard),
      )) {
        expect(card.onTap, isNull);
      }

      completer.complete(_owner1);
      await tester.pumpAndSettle();
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.owners, {
          PropertyColumns.ownershipType: OwnershipType.single,
        }),
      ).called(1);
    });

    testWidgets('is busy while the tunnel saves', (tester) async {
      await pump(
        tester,
        tunnel(
          owners: [_owner1, _owner2],
          ownershipType: OwnershipType.multiple,
          saveStatus: SellerTunnelSaveStatus.inProgress,
        ),
      );
      expect(actionBar(tester).isLoading, isTrue);
      final card = tester.widget<CoOwnerCard>(find.byType(CoOwnerCard));
      expect(card.onEdit, isNull);
      expect(
        tester
            .widget<RealestyButton>(
              find.widgetWithText(RealestyButton, 'Ajouter un co-propriétaire'),
            )
            .onPressed,
        isNull,
      );
    });
  });
}
