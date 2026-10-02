import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// Title of a tab root (C1, C2, V13): Sora 24, below the status bar.
class SellerSpaceTitle extends StatelessWidget {
  const new(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: RealestyTextStyles.title1.copyWith(
          fontSize: 24,
          color: context.realestyColors.encre,
        ),
      ),
    );
  }
}

/// White card with the card border (radius 16, padding 16).
class SellerSpaceCard extends StatelessWidget {
  const new({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: padding ?? const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: child,
    );
  }
}

/// Section heading inside a card: Sora 17/600 + optional subtitle.
class CardHeading extends StatelessWidget {
  const new(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: RealestyTextStyles.title2.copyWith(
              fontSize: 17,
              color: c.encre,
            ),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: RealestyTextStyles.listSubtitle.copyWith(
              color: c.texteDiscret,
            ),
          ),
      ],
    );
  }
}
