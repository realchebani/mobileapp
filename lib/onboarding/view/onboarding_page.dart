import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/onboarding/view/onboarding_illustrations.dart';
import 'package:mobileapp/ui/ui.dart';

/// 00b · Découvrir: four pages introducing Realesty, shown until seen.
class OnboardingPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingView(
      onFinished: () async {
        await context.read<OnboardingRepository>().markSeen();
        if (context.mounted) context.go(AppRoutes.login);
      },
    );
  }
}

class OnboardingView extends StatefulWidget {
  const new({required this.onFinished, super.key});

  /// Called by "Passer", "Commencer" and "J’ai déjà un compte".
  final VoidCallback onFinished;

  static const pageCount = 4;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == OnboardingView.pageCount - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: RealestyMotion.page,
      curve: RealestyMotion.pageCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final pages = [
      _OnboardingSlide(
        illustration: const SavingsIllustration(),
        title: l10n.onboarding1Title,
        body: l10n.onboarding1Body,
      ),
      _OnboardingSlide(
        illustration: const ExpertFileIllustration(),
        title: l10n.onboarding2Title,
        body: l10n.onboarding2Body,
      ),
      _OnboardingSlide(
        illustration: const VisitPassIllustration(),
        title: l10n.onboarding3Title,
        body: l10n.onboarding3Body,
      ),
      _OnboardingSlide(
        illustration: const MatchingIllustration(),
        background: c.expertFond,
        title: l10n.onboarding4Title,
        body: l10n.onboarding4Body,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.xxs,
                RealestySpacing.xs,
                RealestySpacing.xxs,
              ),
              child: Row(
                children: [
                  const RealestyLogo(size: 26, showWordmark: true),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onFinished,
                    style: TextButton.styleFrom(
                      foregroundColor: c.texteDiscret,
                      minimumSize: const Size(
                        RealestySpacing.minTouchTarget,
                        RealestySpacing.minTouchTarget,
                      ),
                      textStyle: RealestyTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.onboardingSkip),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.md,
                RealestySpacing.gutter,
                RealestySpacing.xs,
              ),
              child: Column(
                spacing: RealestySpacing.md,
                children: [
                  _Dots(
                    count: OnboardingView.pageCount,
                    current: _page,
                    onSelected: _goTo,
                  ),
                  if (_isLast)
                    OnboardingButton(
                      label: l10n.onboardingStart,
                      accent: true,
                      onPressed: widget.onFinished,
                    )
                  else
                    OnboardingButton(
                      label: l10n.onboardingNext,
                      onPressed: () => _goTo(_page + 1),
                    ),
                  TextButton(
                    onPressed: widget.onFinished,
                    style: TextButton.styleFrom(
                      foregroundColor: c.vertTexte,
                      minimumSize: const Size.fromHeight(
                        RealestySpacing.minTouchTarget,
                      ),
                      textStyle: RealestyTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.onboardingHaveAccount),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const new({
    required this.illustration,
    required this.title,
    required this.body,
    this.background,
  });

  final Widget illustration;
  final String title;
  final String body;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.lg,
        children: [
          Container(
            height: 250,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: background ?? c.vertTeinte,
              borderRadius: BorderRadius.circular(RealestyRadius.sheet),
            ),
            // Scales the illustration down with large text sizes.
            child: FittedBox(fit: BoxFit.scaleDown, child: illustration),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Text(
                title,
                style: RealestyTextStyles.title1.copyWith(
                  height: 1.2,
                  letterSpacing: -0.26,
                  color: c.encre,
                ),
              ),
              Text(
                body,
                style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const new({
    required this.count,
    required this.current,
    required this.onSelected,
  });

  final int count;
  final int current;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          RealestyPressable(
            semanticLabel: l10n.onboardingDotLabel(i + 1),
            selected: i == current,
            onPressed: () => onSelected(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AnimatedContainer(
                duration: RealestyMotion.short,
                curve: RealestyMotion.shortCurve,
                width: i == current ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == current ? c.encre : c.ligne,
                  borderRadius: BorderRadius.circular(RealestyRadius.pill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Onboarding CTA (56 high, trailing chevron): primary ("Suivant") or
/// accent ("Commencer").
class OnboardingButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.accent = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final foreground = accent ? c.encre : c.surface;
    return RealestyPressable(
      semanticLabel: label,
      onPressed: onPressed,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
        decoration: BoxDecoration(
          color: accent ? c.vert : c.encre,
          borderRadius: BorderRadius.circular(RealestyRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: RealestySpacing.xs,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RealestyTextStyles.button.copyWith(color: foreground),
              ),
            ),
            RealestyIcon(
              RealestyIcons.chevronRight,
              size: 18,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}
