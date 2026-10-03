import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// « Exemples de bonnes photos » (V11, photos of the listing): reference
/// photos bundled with the app (compressed, without metadata) and the
/// framing tips of the photo shoot.
class PhotoExamples extends StatelessWidget {
  const new({super.key});

  /// Bundled examples (owner's reference photos, no person on them).
  static const assets = [
    'assets/sale_examples/salon.jpg',
    'assets/sale_examples/cuisine.jpg',
    'assets/sale_examples/chambre1.jpg',
    'assets/sale_examples/salon2.jpg',
    'assets/sale_examples/terrasse.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        Text(
          l10n.photoExamplesTitle,
          style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: assets.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: RealestySpacing.xs),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(RealestyRadius.field),
              child: Image.asset(
                assets[index],
                width: 112,
                height: 84,
                fit: BoxFit.cover,
                semanticLabel: l10n.photoExamplesCaption,
              ),
            ),
          ),
        ),
        Text(
          l10n.photoExamplesTips,
          style: RealestyTextStyles.listSubtitle.copyWith(
            color: c.texteDiscret,
          ),
        ),
      ],
    );
  }
}
