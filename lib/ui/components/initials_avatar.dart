import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/typography/realesty_fonts.dart';

/// Circle with initials (expert, buyer, account): Surface 2 on light
/// screens, Nuit 3 with white text on dark cards.
class InitialsAvatar extends StatelessWidget {
  const new(this.initials, {this.size = 36, this.onDark = false, super.key});

  /// Up to three letters (e.g. "JM").
  final String initials;
  final double size;
  final bool onDark;

  /// Initials of [name] ("Julien M." → "JM"); "?" when empty.
  static String of(String name) {
    final letters = [
      for (final word in name.trim().split(RegExp(r'[\s\-]+')))
        if (word.isNotEmpty) word.characters.first.toUpperCase(),
    ];
    return letters.isEmpty ? '?' : letters.take(2).join();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onDark ? c.nuit3 : c.surface2,
        ),
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: RealestyFonts.sora,
            fontSize: size / 3,
            fontWeight: FontWeight.w600,
            color: onDark ? c.nuitTexte : c.encre,
          ),
        ),
      ),
    );
  }
}
