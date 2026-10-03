import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// Layout of the sale screens (V11, V11a, V11b, V11c): back button, a
/// [title] with its [badges], the scrollable [children] with pull to
/// refresh, and an optional sticky [bottom] action.
class SaleScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.badges = const [],
    this.actions = const [],
    this.bottom,
    this.onRefresh,
    this.scrollController,
    super.key,
  });

  final String title;
  final List<Widget> badges;

  /// Icon buttons at the end of the header (e.g. "Aperçu").
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? bottom;
  final Future<void> Function()? onRefresh;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final bottom = this.bottom;
    final onRefresh = this.onRefresh;
    Widget list = ListView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        RealestySpacing.gutter,
        RealestySpacing.xs,
        RealestySpacing.gutter,
        RealestySpacing.xl,
      ),
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(height: 14),
          child,
        ],
      ],
    );
    if (onRefresh != null) {
      list = RefreshIndicator(
        color: c.vertTexte,
        onRefresh: onRefresh,
        child: list,
      );
    }
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.sm,
                RealestySpacing.gutter,
                RealestySpacing.sm,
              ),
              child: Row(
                spacing: RealestySpacing.sm,
                children: [
                  RealestyIconButton(
                    icon: RealestyIcons.chevronLeft,
                    semanticLabel: l10n.saleBack,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.seller),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: RealestySpacing.xxs,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: RealestyTextStyles.title2.copyWith(
                              color: c.encre,
                            ),
                          ),
                        ),
                        if (badges.isNotEmpty)
                          Wrap(
                            spacing: RealestySpacing.xs,
                            runSpacing: RealestySpacing.xxs,
                            children: badges,
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(child: list),
            if (bottom != null)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.sm,
                  RealestySpacing.gutter,
                  RealestySpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: c.ivoire,
                  border: Border(top: BorderSide(color: c.ligne)),
                ),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}
