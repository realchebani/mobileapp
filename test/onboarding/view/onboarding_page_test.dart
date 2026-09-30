import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/onboarding/onboarding.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  group(OnboardingPage, () {
    late OnboardingRepository onboardingRepository;
    late MockGoRouter goRouter;

    setUp(() {
      onboardingRepository = MockOnboardingRepository();
      when(onboardingRepository.markSeen).thenAnswer((_) async {});
      goRouter = MockGoRouter();
    });

    testWidgets('marks the onboarding seen and goes to the login', (
      tester,
    ) async {
      await tester.pumpApp(
        const OnboardingPage(),
        onboardingRepository: onboardingRepository,
        goRouter: goRouter,
      );

      await tester.tap(find.text('Passer'));
      await tester.pump();

      verify(onboardingRepository.markSeen).called(1);
      verify(() => goRouter.go(AppRoutes.login)).called(1);
    });

    testWidgets('still goes to the login when saving the flag fails', (
      tester,
    ) async {
      when(onboardingRepository.markSeen).thenThrow(Exception('disk full'));
      await tester.pumpApp(
        const OnboardingPage(),
        onboardingRepository: onboardingRepository,
        goRouter: goRouter,
      );

      await tester.tap(find.text('Passer'));
      await tester.pump();

      verify(() => goRouter.go(AppRoutes.login)).called(1);
    });

    testWidgets('does not navigate once unmounted', (tester) async {
      final seen = Completer<void>();
      when(onboardingRepository.markSeen).thenAnswer((_) => seen.future);
      await tester.pumpApp(
        const OnboardingPage(),
        onboardingRepository: onboardingRepository,
        goRouter: goRouter,
      );

      await tester.tap(find.text('J’ai déjà un compte'));
      await tester.pumpApp(
        const SizedBoxPage(),
        onboardingRepository: onboardingRepository,
      );
      seen.complete();
      await tester.pump();

      verify(onboardingRepository.markSeen).called(1);
      verifyNever(() => goRouter.go(any()));
    });
  });

  group(OnboardingView, () {
    testWidgets('pages through the four slides', (tester) async {
      var finished = 0;
      await tester.pumpApp(OnboardingView(onFinished: () => finished++));

      expect(find.byType(SavingsIllustration), findsOneWidget);
      expect(find.text('Vendez sans payer 5 % d’honoraires'), findsOneWidget);
      expect(find.text('Commencer'), findsNothing);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpertFileIllustration), findsOneWidget);
      expect(find.text('Scannez'), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.byType(VisitPassIllustration), findsOneWidget);
      expect(find.text('Financement validé'), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.byType(MatchingIllustration), findsOneWidget);
      expect(find.text('Suivant'), findsNothing);

      await tester.tap(find.text('Commencer'));
      expect(finished, 1);
    });

    testWidgets('fits the slide text on a 375×667 screen', (tester) async {
      final view = tester.view
        ..physicalSize = const Size(375, 647)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      await tester.pumpApp(OnboardingView(onFinished: () {}));

      for (var page = 0; page < OnboardingView.pageCount; page++) {
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PageView),
                matching: find.byType(Scrollable),
              )
              .at(1),
        );
        expect(scrollable.position.maxScrollExtent, 0, reason: 'page $page');
        if (page < OnboardingView.pageCount - 1) {
          await tester.tap(find.text('Suivant'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('jumps to a page from its dot', (tester) async {
      await tester.pumpApp(OnboardingView(onFinished: () {}));

      await tester.tap(find.bySemanticsLabel('Écran 3'));
      await tester.pumpAndSettle();

      expect(find.byType(VisitPassIllustration), findsOneWidget);
    });

    testWidgets('swipes between pages', (tester) async {
      await tester.pumpApp(OnboardingView(onFinished: () {}));

      await tester.fling(
        find.byType(SavingsIllustration),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpertFileIllustration), findsOneWidget);
    });
  });
}

class SizedBoxPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
