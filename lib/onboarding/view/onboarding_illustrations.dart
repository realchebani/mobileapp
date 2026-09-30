import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// Page 1: agency fees vs Realesty fees for a 525 000 € house.
class SavingsIllustration extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.bubble),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14141A17),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 14,
        children: [
          Text(
            l10n.onboarding1CardCaption,
            style: RealestyTextStyles.bodySmall.copyWith(
              fontSize: 12,
              color: c.texteDiscret,
            ),
          ),
          _FeeBar(
            label: l10n.onboarding1AgencyLabel,
            amount: l10n.onboarding1AgencyAmount,
            fraction: 1,
            color: c.ligne,
          ),
          _FeeBar(
            label: l10n.onboarding1RealestyLabel,
            amount: l10n.onboarding1RealestyAmount,
            fraction: 0.2,
            color: c.vert,
          ),
          RealestyBadge(
            label: l10n.onboarding1Savings,
            variant: RealestyBadgeVariant.certified,
            icon: RealestyIcons.trending,
          ),
        ],
      ),
    );
  }
}

class _FeeBar extends StatelessWidget {
  const new({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String amount;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final style = RealestyTextStyles.label.copyWith(
      fontWeight: FontWeight.w700,
      color: c.encre2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(amount, style: style),
          ],
        ),
        Container(
          height: 22,
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Page 2: the agent orb with the voice / scan / upload chips.
class ExpertFileIllustration extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 14,
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.encre,
            boxShadow: [
              BoxShadow(
                color: c.vert.withValues(alpha: 0.25),
                spreadRadius: 12,
              ),
            ],
          ),
          child: const RealestyLogo(size: 48, onDark: true),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: RealestySpacing.xs,
          runSpacing: RealestySpacing.xs,
          children: [
            RealestyBadge(
              label: l10n.onboarding2Speak,
              icon: RealestyIcons.mic,
            ),
            RealestyBadge(
              label: l10n.onboarding2Scan,
              icon: RealestyIcons.scan,
            ),
            RealestyBadge(
              label: l10n.onboarding2Upload,
              icon: RealestyIcons.upload,
            ),
          ],
        ),
        RealestyBadge(
          label: l10n.onboarding2Certified,
          variant: RealestyBadgeVariant.passVisite,
        ),
      ],
    );
  }
}

/// Page 3: the buyer's "Pass Visite" card.
class VisitPassIllustration extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    Widget line(String text) => Row(
      spacing: RealestySpacing.xs,
      children: [
        RealestyIcon(RealestyIcons.check, size: 16, color: c.lueur),
        Expanded(
          child: Text(
            text,
            style: RealestyTextStyles.label.copyWith(
              fontWeight: FontWeight.w400,
              color: c.surface,
            ),
          ),
        ),
      ],
    );
    return Container(
      width: 220,
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.encre,
        borderRadius: BorderRadius.circular(RealestyRadius.bubble),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40141A17),
            offset: Offset(0, 10),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.onboarding3PassTitle,
                  style: RealestyTextStyles.title2.copyWith(
                    fontSize: 16,
                    color: c.surface,
                  ),
                ),
              ),
              RealestyIcon(RealestyIcons.shield, size: 22, color: c.lueur),
            ],
          ),
          line(l10n.onboarding3Identity),
          line(l10n.onboarding3Financing),
          line(l10n.onboarding3Project),
        ],
      ),
    );
  }
}

/// Page 4: a property with its compatibility score and matched criteria.
///
/// The property photo is a neutral placeholder until real images exist.
class MatchingIllustration extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 14,
      children: [
        SizedBox(
          width: 230,
          height: 130,
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  image: true,
                  label: l10n.onboarding4ImageLabel,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.imagePlaceholder,
                      borderRadius: BorderRadius.circular(RealestyRadius.card),
                    ),
                    child: RealestyIcon(
                      RealestyIcons.home,
                      size: 40,
                      color: c.texteDiscret,
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 10,
                top: 10,
                child: RealestyBadge(
                  label: l10n.onboarding4Compatibility,
                  variant: RealestyBadgeVariant.compatibility,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            RealestyBadge(
              label: l10n.onboarding4Garage,
              variant: RealestyBadgeVariant.certified,
            ),
            RealestyBadge(
              label: l10n.onboarding4School,
              variant: RealestyBadgeVariant.certified,
            ),
          ],
        ),
      ],
    );
  }
}
