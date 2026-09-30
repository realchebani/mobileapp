import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Variants of [InlineBanner].
enum InlineBannerVariant {
  /// Attention colors (e.g. "Estimation indicative…").
  warning,

  /// Expert / info blue colors.
  info,
}

/// Inline message block with a leading info icon.
class InlineBanner extends StatelessWidget {
  const new({
    required this.message,
    this.variant = InlineBannerVariant.warning,
    this.icon = RealestyIcons.infoCircle,
    super.key,
  });

  final String message;
  final InlineBannerVariant variant;
  final RealestyIcons icon;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final (Color background, Color iconColor) = switch (variant) {
      InlineBannerVariant.warning => (c.attentionFond, c.attention),
      InlineBannerVariant.info => (c.expertFond, c.expert),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RealestyRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          RealestyIcon(icon, size: 18, color: iconColor),
          Expanded(
            child: Text(
              message,
              style: RealestyTextStyles.banner.copyWith(color: c.encre),
            ),
          ),
        ],
      ),
    );
  }
}
