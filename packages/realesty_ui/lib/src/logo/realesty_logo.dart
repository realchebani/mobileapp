import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// The Realesty logo (house wireframe with the green accent node),
/// optionally followed by the Michroma "REALESTY" wordmark.
class RealestyLogo extends StatelessWidget {
  const new({
    this.size = 44,
    this.onDark = false,
    this.showWordmark = false,
    this.wordmarkSize,
    this.strokeWidth,
    this.semanticLabel = 'Realesty',
    this.direction = Axis.horizontal,
    super.key,
  });

  /// Width and height of the mark.
  final double size;

  /// White strokes and `lueur` accent, for dark backgrounds.
  final bool onDark;

  /// Shows the "REALESTY" wordmark after the mark.
  final bool showWordmark;

  /// Wordmark font size; defaults to [defaultWordmarkSize].
  final double? wordmarkSize;

  /// Stroke width in the 100×100 viewBox; defaults to
  /// [defaultStrokeWidth] for [size].
  final double? strokeWidth;

  final String semanticLabel;

  /// Lockup direction: [Axis.vertical] stacks the mark above the wordmark
  /// (splash: size 120, wordmark 30, stroke 2.6).
  final Axis direction;

  /// Optical stroke width used by the design for a given mark size
  /// (thicker strokes at small sizes).
  static double defaultStrokeWidth(double size) {
    if (size <= 20) return 5;
    if (size <= 26) return 4.5;
    if (size == 48) return 4;
    if (size >= 120) return 2.6;
    return 3.2;
  }

  /// Wordmark size paired with a mark [size] in the design lockups:
  /// ≤ 26 → 15, ≤ 40 → 20, ≤ 44 → 16, ≥ 72 → 34 (nearest lockup in
  /// between).
  static double defaultWordmarkSize(double size) {
    if (size <= 26) return 15;
    if (size <= 40) return 20;
    if (size < 58) return 16;
    return 34;
  }

  /// Gap between mark and wordmark in a horizontal lockup: 12 up to 44,
  /// 20 from 72 (nearest lockup in between).
  static double horizontalGap(double size) => size < 58 ? 12 : 20;

  /// Gap between mark and wordmark in a vertical (splash) lockup.
  static const double verticalGap = 28;

  /// SVG source of the mark.
  static String svg({
    required Color ink,
    required Color accent,
    required double strokeWidth,
  }) {
    final i = _hex(ink);
    final a = _hex(accent);
    const dots = [
      (10, 42),
      (50, 8),
      (90, 42),
      (90, 92),
      (10, 92),
      (50, 42),
      (30, 66),
      (50, 92),
    ];
    final circles = dots
        .map((d) => '<circle cx="${d.$1}" cy="${d.$2}" r="4.2" fill="$i"/>')
        .join();
    return [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" ',
      'fill="none" stroke="$i" stroke-width="$strokeWidth" ',
      'stroke-linecap="round" stroke-linejoin="round">',
      '<path d="$_outline"/>',
      '<path d="$_frame"/>',
      '<circle cx="70" cy="66" r="15" fill="$a" opacity="0.3" stroke="none"/>',
      circles,
      '<circle cx="70" cy="66" r="6.5" fill="$a" stroke="none"/>',
      '</svg>',
    ].join();
  }

  static const _outline = 'M10 42L50 8L90 42V92H10Z';
  static const _frame =
      'M10 42H90M50 8V42M50 42L30 66M50 42L70 66M30 66H70M30 66L10 92'
      ' M30 66L50 92M70 66L50 92M70 66L90 92M10 42L30 66M90 42L70 66';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    final ink = onDark ? colors.nuitTexte : colors.encre;
    final mark = SvgPicture.string(
      svg(
        ink: ink,
        accent: onDark ? colors.lueur : colors.vert,
        strokeWidth: strokeWidth ?? defaultStrokeWidth(size),
      ),
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
    if (!showWordmark) {
      return Semantics(label: semanticLabel, image: true, child: mark);
    }
    final fontSize = wordmarkSize ?? defaultWordmarkSize(size);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: Flex(
          direction: direction,
          mainAxisSize: MainAxisSize.min,
          spacing: direction == Axis.horizontal
              ? horizontalGap(size)
              : verticalGap,
          children: [
            mark,
            Text(
              'REALESTY',
              style: RealestyTextStyles.wordmark(fontSize).copyWith(color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
