import 'dart:async';

import 'package:bloc_test/bloc_test.dart';

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
  group(SellerTunnelShell, () {
    testWidgets('loads the dossier of the user, then shows the child', (
      tester,
    ) async {
      final repository = MockPropertyRepository();
      final draft = Completer<Property>();
      when(() => repository.getOrCreateDossier(any()))
          .thenAnswer((_) => draft.future);
      when(() => repository.getOwners(any())).thenAnswer((_) async => []);
      when(() => repository.getParcels(any())).thenAnswer((_) async => []);
      when(() => repository.getPreviousEstimates(any()))
          .thenAnswer((_) async => []);
      when(() => repository.getRooms(any())).thenAnswer((_) async => []);
      when(() => repository.getLifestyleItems(any()))
          .thenAnswer((_) async => []);
      when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
      final profileCubit = MockProfileCubit();
      when(() => profileCubit.state).thenReturn(
        const ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'user-id', role: UserRole.seller),
        ),
      );

      await tester.pumpApp(
        const SellerTunnelShell(child: Text('child')),
        propertyRepository: repository,
        profileCubit: profileCubit,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      draft.complete(testProperty);
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      verify(() => repository.getOrCreateDossier('user-id')).called(1);
    });
  });

  group(SellerTunnelGate, () {
    late MockGoRouter goRouter;

    setUp(() {
      goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      final routerState = _MockGoRouterState();
      when(() => routerState.matchedLocation)
          .thenReturn(AppRoutes.sellerOwners);
      when(() => goRouter.state).thenReturn(routerState);
    });

    testWidgets('offers to retry or sign out after a failure', (tester) async {
      final cubit = mockSellerTunnelCubit(
        const SellerTunnelState(status: SellerTunnelStatus.failure),
      );
      final appBloc = MockAppBloc();
      when(() => appBloc.state).thenReturn(const AppState());
      await tester.pumpTunnelPage(
        const SellerTunnelGate(child: Text('child')),
        sellerTunnelCubit: cubit,
        appBloc: appBloc,
      );

      expect(find.text('Impossible de charger votre dossier.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      verify(cubit.retry).called(1);
      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
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
        const SellerTunnelGate(child: Text('child')),
        sellerTunnelCubit: cubit,
        goRouter: goRouter,
      );
      await tester.pump();

      verify(() => goRouter.go(AppRoutes.sellerLocation)).called(1);
      verifyNever(() => goRouter.go(AppRoutes.sellerTechnical));
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
        const Scaffold(body: SellerTunnelGate(child: Text('child'))),
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
  });
}
