import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

class _MockGoRouterState extends Mock implements GoRouterState;

void main() {
  late MockPropertyRepository repository;
  late MockProfileCubit profileCubit;

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.listLots(any())).thenAnswer((_) async => []);
    when(() => repository.getProperty(any()))
        .thenAnswer((_) async => testProperty);
    when(() => repository.getOwners(any())).thenAnswer((_) async => []);
    when(() => repository.getParcels(any())).thenAnswer((_) async => []);
    when(() => repository.getPreviousEstimates(any()))
        .thenAnswer((_) async => []);
    when(() => repository.getRooms(any())).thenAnswer((_) async => []);
    when(() => repository.getLifestyleItems(any())).thenAnswer((_) async => []);
    when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(
        status: ProfileStatus.success,
        profile: Profile(id: 'user-id', role: UserRole.seller),
      ),
    );
  });

  group(SellerTunnelShell, () {
    testWidgets('loads the properties of the user, then shows the child', (
      tester,
    ) async {
      final properties = Completer<List<Property>>();
      when(() => repository.listProperties(any()))
          .thenAnswer((_) => properties.future);
      await tester.pumpApp(
        const SellerTunnelShell(child: Text('child')),
        propertyRepository: repository,
        profileCubit: profileCubit,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      properties.complete([testProperty]);
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      verify(() => repository.listProperties('user-id')).called(1);
    });

    testWidgets('offers to retry or sign out after a failure', (tester) async {
      var calls = 0;
      when(() => repository.listProperties(any())).thenAnswer((_) async {
        if (calls++ == 0) throw const PropertyLoadFailure();
        return [testProperty];
      });
      final appBloc = MockAppBloc();
      when(() => appBloc.state).thenReturn(const AppState());
      await tester.pumpApp(
        const SellerTunnelShell(child: Text('child')),
        propertyRepository: repository,
        profileCubit: profileCubit,
        appBloc: appBloc,
      );
      await tester.pumpAndSettle();

      expect(find.text('Impossible de charger votre dossier.'), findsOneWidget);
      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('provides one dossier cubit per property', (tester) async {
      when(() => repository.listProperties(any()))
          .thenAnswer((_) async => [testProperty]);
      await tester.pumpApp(
        const SellerTunnelShell(
          child: PropertyRouteScope(
            propertyId: 'property-id',
            child: Text('child'),
          ),
        ),
        propertyRepository: repository,
        profileCubit: profileCubit,
      );
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      verify(() => repository.getProperty('property-id')).called(1);
      final context = tester.element(find.text('child'));
      expect(
        context.read<SellerTunnelCubit>().state.property?.id,
        'property-id',
      );
      // Tells "Mes biens" about the loaded property.
      expect(context.read<SellerPropertiesCubit>().state.properties, [
        testProperty,
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group(PropertyGate, () {
    late MockGoRouter goRouter;

    void routeAt(String location) {
      final routerState = _MockGoRouterState();
      when(() => routerState.matchedLocation).thenReturn(location);
      when(() => goRouter.state).thenReturn(routerState);
    }

    setUp(() {
      goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      routeAt(auditRoute(SellerTunnelStep.owners));
    });

    testWidgets('offers to retry or sign out after a failure', (tester) async {
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(status: SellerTunnelStatus.failure),
      );
      final appBloc = MockAppBloc();
      when(() => appBloc.state).thenReturn(const AppState());
      await tester.pumpTunnelPage(
        const PropertyGate(child: Text('child')),
        sellerTunnelCubit: cubit,
        appBloc: appBloc,
      );

      expect(find.text('Impossible de charger votre dossier.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      verify(cubit.retry).called(1);
      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
    });

    testWidgets('goes back to the seller space when the property is gone', (
      tester,
    ) async {
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.failure,
          notFound: true,
        ),
      );
      await tester.pumpTunnelPage(
        const PropertyGate(child: Text('child')),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();
      verify(() => goRouter.go(AppRoutes.seller)).called(1);
    });

    testWidgets('opens the next step after a successful save', (tester) async {
      final cubit = mockSellerTunnelCubit();
      const loaded = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: testProperty,
      );
      whenListen(
        cubit,
        Stream.fromIterable([
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
          loaded.copyWith(
            saveStatus: SellerTunnelSaveStatus.success,
            nextStep: SellerTunnelStep.location,
            continuedFrom: SellerTunnelStep.owners,
          ),
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.success),
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
          // Saved from a step the user already left: no navigation.
          loaded.copyWith(
            saveStatus: SellerTunnelSaveStatus.success,
            nextStep: SellerTunnelStep.technical,
            continuedFrom: SellerTunnelStep.context,
          ),
        ]),
        initialState: loaded,
      );
      await tester.pumpTunnelPage(
        const PropertyGate(child: Text('child')),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();

      verify(() => goRouter.go(auditRoute(SellerTunnelStep.location)))
          .called(1);
      verifyNever(() => goRouter.go(auditRoute(SellerTunnelStep.technical)));
    });

    testWidgets('ignores saves of a screen that is not visible', (
      tester,
    ) async {
      final cubit = mockSellerTunnelCubit();
      const loaded = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: testProperty,
      );
      whenListen(
        cubit,
        Stream.value(
          loaded.copyWith(
            saveStatus: SellerTunnelSaveStatus.success,
            nextStep: SellerTunnelStep.location,
            continuedFrom: SellerTunnelStep.owners,
          ),
        ),
        initialState: loaded,
      );
      await tester.pumpTunnelPage(
        const TickerMode(
          enabled: false,
          child: PropertyGate(child: Text('child')),
        ),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();
      verifyNever(() => goRouter.go(any()));
    });

    testWidgets('sends the steps of a sent dossier to V8', (tester) async {
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.inReview,
            currentStep: 8,
          ),
        ),
      );
      await tester.pumpTunnelPage(
        const PropertyGate(auditSegment: 'proprietaires', child: Text('child')),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      expect(find.text('child'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump();
      verify(() => goRouter.go(auditRoute(SellerTunnelStep.submitted)))
          .called(1);
    });

    testWidgets('shows V8 of a sent dossier', (tester) async {
      routeAt(auditRoute(SellerTunnelStep.submitted));
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.certified,
          ),
        ),
      );
      await tester.pumpTunnelPage(
        const PropertyGate(auditSegment: 'envoye', child: Text('child')),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();
      expect(find.text('child'), findsOneWidget);
      verifyNever(() => goRouter.go(any()));
    });

    testWidgets('shows an error when a save failed', (tester) async {
      final cubit = mockSellerTunnelCubit();
      const loaded = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: testProperty,
      );
      whenListen(
        cubit,
        Stream.fromIterable([
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.failure),
        ]),
        initialState: loaded,
      );
      await tester.pumpTunnelPage(
        const Scaffold(body: PropertyGate(child: Text('child'))),
        sellerTunnelCubit: cubit,
      );
      await tester.pump();

      expect(
        find.text(
          'L’enregistrement a échoué. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
    });

    Future<MockGoRouter> continueFromV3(
      WidgetTester tester,
      Property property,
    ) async {
      routeAt(SellerTunnelStep.context.routeFor(property.id));
      final cubit = mockSellerTunnelCubit();
      final loaded = SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: property,
      );
      whenListen(
        cubit,
        Stream.value(
          loaded.copyWith(
            saveStatus: SellerTunnelSaveStatus.success,
            nextStep: SellerTunnelStep.technical,
            continuedFrom: SellerTunnelStep.context,
          ),
        ),
        initialState: loaded,
      );
      await tester.pumpTunnelPage(
        RepositoryProvider.value(
          value: await testVoiceServices(),
          child: const PropertyGate(child: Text('child')),
        ),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();
      return goRouter;
    }

    testWidgets('V3 opens the voice audit (V4) when voice is available', (
      tester,
    ) async {
      await continueFromV3(tester, testProperty);
      verify(() => goRouter.go(voiceAuditRoute)).called(1);
    });

    testWidgets('V3 opens V4b for a type without voice', (tester) async {
      await continueFromV3(
        tester,
        const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      );
      verify(() => goRouter.go('/vendeur/biens/p/audit/technique')).called(1);
    });
  });
}
