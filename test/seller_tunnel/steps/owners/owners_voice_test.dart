import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/cubit/owners_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _owner1 = PropertyOwner(
  id: 'o1',
  propertyId: 'p',
  position: 1,
  firstName: 'Sophie',
  lastName: 'Martin',
  phone: '+33612345678',
  email: 's@e.fr',
);

const _coOwner = AgentEntityChange(
  entity: AgentEntity.coOwner,
  op: AgentEntityOp.create,
  target: 'new',
  label: 'Marc Durand',
  values: {'first_name': ' Marc ', 'last_name': 'Durand'},
);

const _turn = AgentTurn(
  turnId: 't1#c1',
  transcript: '',
  reply: '',
  patch: {'ownership_type': 'multiple'},
  entityOps: [
    _coOwner,
    // Not a co-owner creation, or without names: ignored.
    AgentEntityChange(
      entity: AgentEntity.coOwner,
      op: AgentEntityOp.delete,
      target: 'P2',
      label: 'x',
    ),
    AgentEntityChange(
      entity: AgentEntity.room,
      op: AgentEntityOp.create,
      target: 'new',
      label: 'x',
    ),
    AgentEntityChange(
      entity: AgentEntity.coOwner,
      op: AgentEntityOp.create,
      target: 'new',
      label: 'x',
      values: {'first_name': 'A'},
    ),
  ],
);

void main() {
  OwnersCubit build() => OwnersCubit(
    propertyRepository: MockPropertyRepository(),
    propertyId: 'p',
    profileId: 'u',
    owners: const [_owner1],
  );

  group('OwnersCubit voice', () {
    test('no name is sent; a confirmed co-owner is added', () async {
      final cubit = build();
      expect(
        cubit.voiceContext,
        const AgentTurnContext(
          draft: {'ownership_type': null},
          coOwnersCount: 0,
        ),
      );
      await cubit.voiceTurnApplied(_turn);
      expect(cubit.state.ownershipType, OwnershipType.multiple);
      expect(cubit.state.coOwners, const [
        OwnerDraft(firstName: 'Marc', lastName: 'Durand'),
      ]);
      expect(cubit.state.dictated, {'ownership_type', 'co_owner:Marc Durand'});
      expect(cubit.voiceContext.coOwnersCount, 1);
      expect(cubit.acceptsVoice, isTrue);
      // The dictated co-owner still needs a phone number.
      expect(cubit.state.isValid, isFalse);
      expect(cubit.state.coOwnerIncomplete(0), isFalse);
      await cubit.submit();
      expect(cubit.state.coOwnerIncomplete(0), isTrue);
      cubit.coOwnerEdited(
        0,
        const OwnerDraft(
          firstName: 'Marc',
          lastName: 'Durand',
          phone: '06 98 76 54 32',
        ),
      );
      expect(cubit.state.isValid, isTrue);
      await cubit.close();
    });
  });

  test('the intro follows the owner decision Q1', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
    expect(ownersVoiceIntro(l10n, names: true), l10n.ownersVoiceIntro);
    expect(
      ownersVoiceIntro(l10n, names: false),
      l10n.ownersVoiceIntroWithoutNames,
    );
  });

  group('V1 voice sheet', () {
    late VoiceSheetMocks mocks;

    setUp(
      () => mocks = VoiceSheetMocks(
        turn: const AgentTurn(
          turnId: 't1',
          transcript: 'avec mon frère Marc Durand',
          reply: 'Est-ce bien Marc Durand ?',
          confirmations: [
            AgentConfirmation(
              id: 'c1',
              reason: AgentConfirmationReason.coOwner,
              label: 'Marc Durand ?',
              patch: {'ownership_type': 'multiple'},
              entityOps: [_coOwner],
            ),
          ],
        ),
      ),
    );
    tearDown(() => mocks.dispose());

    testWidgets('a dictated co-owner, confirmed, to complete on screen', (
      tester,
    ) async {
      final view = tester.view
        ..physicalSize = const Size(390, 1800)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      await tester.pumpTunnelPage(
        RepositoryProvider.value(
          value: await mocks.services(),
          child: const OwnersPage(),
        ),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: Property(id: 'p', ownerId: 'u'),
            owners: [_owner1],
          ),
        ),
      );
      await tester.tap(find.byType(RealestyMicButton));
      await tester.pumpAndSettle();
      expect(find.text('Propriétaires à la voix'), findsOneWidget);
      await mocks.speak(tester);
      await tester.ensureVisible(find.text('Oui'));
      await tester.tap(find.text('Oui'));
      await tester.pumpAndSettle();
      await mocks.close(tester);
      expect(find.text('Marc Durand'), findsOneWidget);
      expect(find.text('Dicté'), findsOneWidget);
      // The ownership type and the co-owner.
      expect(find.text('2 réponses ajoutées'), findsOneWidget);
      // The snackbar goes away.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('À compléter\u00a0: téléphone'), findsOneWidget);
    });
  });
}
