import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';

/// A report card: heading (+ subtitle) and its content, 12 apart.
class ReportCard extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SellerSpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          CardHeading(title, subtitle: subtitle),
          ...children,
        ],
      ),
    );
  }
}

/// Key figure tile ("Prix conseillé", "Délai estimé").
class ReportStatTile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.hint,
    this.highlighted = false,
    super.key,
  });

  final String label;
  final String value;
  final String? hint;

  /// Vert teinte background (the advised price).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final hint = this.hint;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? c.vertTeinte : c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: highlighted ? null : Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            label.toUpperCase(),
            style: RealestyTextStyles.caption.copyWith(
              color: highlighted ? c.vertTexte : c.texteDiscret,
            ),
          ),
          Text(
            value,
            style: RealestyTextStyles.cardPrice.copyWith(
              fontSize: 22,
              height: 1.1,
              color: c.encre,
              // Sora has no "≈" ("≈ 8 sem.").
              fontFamilyFallback: const [RealestyFonts.hankenGrotesk],
            ),
          ),
          if (hint != null)
            Text(
              hint,
              style: RealestyTextStyles.listSubtitle.copyWith(
                fontSize: 12,
                color: highlighted ? c.encre2 : c.texteDiscret,
              ),
            ),
        ],
      ),
    );
  }
}

/// Paragraph of report text (14, Encre 2).
class ReportParagraph extends StatelessWidget {
  const new(this.text, {this.small = false, super.key});

  final String text;

  /// 12 Texte discret (notes, sources, legal mention).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Text(
      text,
      style: RealestyTextStyles.bodySmall.copyWith(
        fontSize: small ? 12 : 14,
        height: 1.5,
        color: small ? c.texteDiscret : c.encre2,
      ),
    );
  }
}

/// Two-line row: bold title + small subtitle on the left, bold amount +
/// small caption on the right (DVF sales).
class ReportSaleRow extends StatelessWidget {
  const new({
    required this.title,
    required this.amount,
    this.subtitle,
    this.caption,
    this.struck = false,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String amount;
  final String? caption;

  /// Excluded line: faded and struck through.
  final bool struck;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final subtitle = this.subtitle;
    final caption = this.caption;
    final small = RealestyTextStyles.listSubtitle.copyWith(
      fontSize: 12,
      color: c.texteDiscret,
    );
    final bold = RealestyTextStyles.bodySmall.copyWith(
      fontWeight: FontWeight.w700,
      color: c.encre,
    );
    return Opacity(
      opacity: struck ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.bordureCarte)),
        ),
        child: MergeSemantics(
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: bold.copyWith(
                        decoration: struck ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (subtitle != null) Text(subtitle, style: small),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amount, style: bold),
                  if (caption != null) Text(caption, style: small),
                ],
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
