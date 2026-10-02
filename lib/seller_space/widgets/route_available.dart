import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Whether the app router knows [location] (e.g. a screen another epic
/// adds, such as V8b `/vendeur/marche`), so links to it can stay hidden
/// until it exists.
bool isRouteAvailable(BuildContext context, String location) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  try {
    return router.configuration.findMatch(Uri.parse(location)).isNotEmpty;
  } on Object {
    return false;
  }
}
