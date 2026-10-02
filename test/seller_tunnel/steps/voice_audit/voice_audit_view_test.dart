import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _MockConversation extends MockCubit<VoiceConversationState>
    implements VoiceConversationCubit;

const _house = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
);

void main() {
  late MockGoRouter goRouter;
  late _MockConversation conversation;
  late _MockDocumentPicker picker;
  late MockPropertyRepository repository;
  late MockSellerTunnelCubit tunnel;

  setUpAll(() {
    registerFallbackValue(DocumentSource.files);
    registerFallbackValue(DocumentKind.plan);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    conversation = _MockConversation();
    for (final call in <Future<void> Function()>[
      conversation.start,
      conversation.stop,
      conversation.pause,
      conversation.resume,
      conversation.retry,
      conversation.toggleMute,
      conversation.finishSpeaking,
    ]) {
      when(call).thenAnswer((_) async {});
    }
    picker = _MockDocumentPicker();
    repository = MockPropertyRepository();
    tunnel = mockSellerTunnelCubit(
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: _house,
      ),
    );
    when(() => tunnel.updateChildren(documents: any(named: 'documents')))
        .thenReturn(null);
  });

  Future<void> pump(
    WidgetTester tester,
    VoiceConversationState state, {
    bool consentGiven = true,
    List<Uri>? openedUrls,
  }) async {
    final view = tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    when(() => conversation.state).thenReturn(state);
    final services = await testVoiceServices(
      consentGiven: consentGiven,
      openedUrls: openedUrls,
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: services,
        child: BlocProvider<VoiceConversationCubit>.value(
          value: conversation,
          child: VoiceAuditView(documentPicker: picker),
        ),
      ),
      sellerTunnelCubit: tunnel,
      propertyRepository: repository,
      goRouter: goRouter,
    );
    await tester.pumpAndSettle();
  }

  const listening = VoiceConversationState(
    phase: VoicePhase.listening,
    levels: [0.5],
    messages: [
      VoiceMessage(text: 'Bonjour', fromAgent: true),
      VoiceMessage(text: 'Elle date de 1998', fromAgent: false),
    ],
    facts: [AgentPill(field: 'construction_year', label: 'Construction 1998')],
    pending: [AgentPill(field: 'sanitation', label: 'Assainissement ?')],
  );

  testWidgets('listening: conversation, pills, finish, pause, mute', (
    tester,
  ) async {
    await pump(tester, listening);
    verify(conversation.start).called(1);
    expect(find.text('L’agent vous écoute…'), findsOneWidget);
    expect(find.text('Elle date de 1998'), findsOneWidget);
    await tester.tap(find.text('J’ai fini'));
    verify(conversation.finishSpeaking).called(1);
    await tester.tap(find.bySemanticsLabel('Mettre en pause'));
    verify(conversation.pause).called(1);
    await tester.tap(find.text('Couper la voix de l’agent'));
    verify(conversation.toggleMute).called(1);
    await tester.tap(find.text('Construction 1998'));
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
    await tester.tap(find.text('Assainissement ?'));
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
  });

  testWidgets('declined consent opens the screen mode', (tester) async {
    await pump(tester, listening, consentGiven: false);
    await tester.tap(find.text('Continuer à l’écran'));
    await tester.pumpAndSettle();
    verifyNever(conversation.start);
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
  });

  testWidgets('close, keyboard and skip', (tester) async {
    await pump(tester, const VoiceConversationState(muted: true));
    expect(find.text('Réactiver la voix de l’agent'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Fermer'));
    verify(() => goRouter.go(AppRoutes.sellerContext)).called(1);
    await tester.tap(find.bySemanticsLabel('Passer en mode écran'));
    await tester.tap(find.text('Passer'));
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(2);
    verify(conversation.stop).called(3);
  });

  testWidgets('paused: resume', (tester) async {
    await pump(tester, const VoiceConversationState(phase: VoicePhase.paused));
    expect(find.text('En pause'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Reprendre'));
    verify(conversation.resume).called(1);
  });

  testWidgets('done: review on V4b', (tester) async {
    await pump(tester, const VoiceConversationState(phase: VoicePhase.done));
    await tester.tap(find.text('Vérifier mes réponses'));
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
  });

  testWidgets('errors: retry, or screen mode only', (tester) async {
    await pump(tester, const VoiceConversationState(error: VoiceError.network));
    await tester.tap(find.text('Réessayer'));
    verify(conversation.retry).called(1);
    await pump(tester, const VoiceConversationState(error: VoiceError.quota));
    expect(find.text('Réessayer'), findsNothing);
    await tester.tap(find.text('Passer en mode écran').first);
    verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
  });

  testWidgets('a refused microphone links to the settings', (tester) async {
    final urls = <Uri>[];
    await pump(
      tester,
      const VoiceConversationState(error: VoiceError.permissionDenied),
      openedUrls: urls,
    );
    await tester.tap(find.text('Réglages'));
    await tester.pump();
    expect(urls, [Uri.parse('app-settings:')]);
  });

  testWidgets('shows a spinner while the plan uploads', (tester) async {
    final file = Completer<XFile?>();
    when(() => picker.pick(any())).thenAnswer((_) => file.future);
    await pump(tester, const VoiceConversationState());
    await tester.tap(find.text('Importer'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    file.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Importer'), findsOneWidget);
  });

  group('plan import', () {
    testWidgets('uploads a plan to the vault', (tester) async {
      when(() => picker.pick(any())).thenAnswer(
        (_) async =>
            XFile.fromData(Uint8List.fromList([1, 2]), path: 'plan.PDF'),
      );
      const document = PropertyDocument(
        id: 'd1',
        propertyId: 'property-id',
        kind: DocumentKind.plan,
        storagePath: 'p',
        fileName: 'plan.PDF',
      );
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => document);
      await pump(tester, const VoiceConversationState());
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      verify(
        () => repository.uploadDocument(
          ownerId: 'user-id',
          propertyId: 'property-id',
          kind: DocumentKind.plan,
          fileName: 'plan.PDF',
          bytes: any(named: 'bytes'),
          mimeType: 'application/pdf',
        ),
      ).called(1);
      verify(() => tunnel.updateChildren(documents: [document])).called(1);
      expect(find.text('Plan ajouté à votre coffre'), findsOneWidget);
    });

    testWidgets('cancel, then failure', (tester) async {
      when(() => picker.pick(any())).thenAnswer((_) async => null);
      await pump(tester, const VoiceConversationState());
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      when(() => picker.pick(any())).thenThrow(Exception('denied'));
      await tester.tap(find.text('Importer'));
      await tester.pumpAndSettle();
      expect(find.text('Le plan n’a pas pu être importé.'), findsOneWidget);
    });

    testWidgets('mime types of images', (tester) async {
      for (final name in ['a.png', 'b.heic', 'c.jpg']) {
        when(() => picker.pick(any()))
            .thenAnswer((_) async => XFile.fromData(Uint8List(1), path: name));
        when(
          () => repository.uploadDocument(
            ownerId: any(named: 'ownerId'),
            propertyId: any(named: 'propertyId'),
            kind: any(named: 'kind'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenThrow(Exception('offline'));
        await pump(tester, const VoiceConversationState());
        await tester.tap(find.text('Importer'));
        await tester.pumpAndSettle();
      }
      for (final mime in ['image/png', 'image/heic', 'image/jpeg']) {
        verify(
          () => repository.uploadDocument(
            ownerId: any(named: 'ownerId'),
            propertyId: any(named: 'propertyId'),
            kind: any(named: 'kind'),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            mimeType: mime,
          ),
        ).called(1);
      }
    });
  });

  testWidgets('shows the latest exchange and offers the screen mode', (
    tester,
  ) async {
    await pump(
      tester,
      const VoiceConversationState(
        suggestScreenMode: true,
        messages: [
          VoiceMessage(text: 'Bonjour', fromAgent: true),
          VoiceMessage(text: 'euh', fromAgent: false),
          VoiceMessage(text: 'Pardon ?', fromAgent: true),
        ],
      ),
    );
    expect(find.text('Bonjour'), findsNothing);
    expect(find.text('euh'), findsOneWidget);
    expect(find.text('Pardon ?'), findsOneWidget);
    expect(find.textContaining('Je n’arrive pas à retenir'), findsOneWidget);
  });
}
