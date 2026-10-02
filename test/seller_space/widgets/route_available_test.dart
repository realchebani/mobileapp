import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/widgets/route_available.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('answers whether the router knows a location', (tester) async {
    late BuildContext context;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (builderContext, state) {
            context = builderContext;
            return const SizedBox();
          },
        ),
        GoRoute(path: '/vendeur', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpAppRouter(router);
    expect(isRouteAvailable(context, '/vendeur'), isTrue);
    expect(isRouteAvailable(context, '/vendeur/marche'), isFalse);
  });

  testWidgets('false without a router or with a broken one', (tester) async {
    late BuildContext context;
    await tester.pumpApp(
      Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox();
        },
      ),
    );
    expect(isRouteAvailable(context, '/vendeur'), isFalse);

    await tester.pumpApp(
      Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox();
        },
      ),
      goRouter: MockGoRouter(),
    );
    expect(isRouteAvailable(context, '/vendeur'), isFalse);
  });
}
