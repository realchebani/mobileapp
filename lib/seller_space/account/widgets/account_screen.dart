import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/ui/ui.dart';

/// Full-screen page of the account (V19, notifications, deletion): a back
/// button, an optional [eyebrow], the [title] and the [children], with an
/// optional [bottom] bar (sticky button).
class AccountScreen extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.eyebrow,
    this.trailing,
    this.bottom,
    this.onBack,
    this.fallbackLocation = AppRoutes.sellerAccount,
    this.controller,
    super.key,
  });

  final String title;
  final String? eyebrow;

  /// Next to the back button (e.g. "Tout marquer comme lu").
  final Widget? trailing;
  final List<Widget> children;
  final Widget? bottom;

  /// Replaces the default back (pop, else [fallbackLocation]).
  final VoidCallback? onBack;
  final String fallbackLocation;
  final ScrollController? controller;

  /// Pops this screen, or opens [location] when there is nothing to pop.
  static void back(BuildContext context, String location) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final eyebrow = this.eyebrow;
    final bottom = this.bottom;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.xs,
                RealestySpacing.xs,
                RealestySpacing.gutter,
                0,
              ),
              child: Row(
                children: [
                  RealestyIconButton(
                    icon: RealestyIcons.chevronLeft,
                    semanticLabel: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    onPressed: onBack ?? () => back(context, fallbackLocation),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xs,
                  RealestySpacing.gutter,
                  RealestySpacing.xl,
                ),
                children: [
                  if (eyebrow != null)
                    Text(
                      eyebrow,
                      style: RealestyTextStyles.caption.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: RealestyTextStyles.title1.copyWith(
                        fontSize: 24,
                        color: c.encre,
                      ),
                    ),
                  ),
                  const SizedBox(height: RealestySpacing.lg),
                  ...children,
                ],
              ),
            ),
            if (bottom != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.bordureCarte)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RealestySpacing.gutter,
                      RealestySpacing.sm,
                      RealestySpacing.gutter,
                      RealestySpacing.sm,
                    ),
                    child: bottom,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
