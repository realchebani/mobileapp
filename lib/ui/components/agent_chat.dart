import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/logo/realesty_logo.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Round avatar of the Realesty agent: dark circle with the white logo.
class AgentAvatar extends StatelessWidget {
  const new({this.size = 36, this.onDark = false, super.key});

  final double size;

  /// Night variant (Nuit 3 background).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onDark ? c.nuit3 : c.encre,
      ),
      child: ExcludeSemantics(
        child: RealestyLogo(size: size * 20 / 36, onDark: true),
      ),
    );
  }
}

/// Message from the agent: avatar, "Agent Realesty" sender line with a
/// sparkle, and a white bubble with a 4px top-left tail.
class AgentBubble extends StatelessWidget {
  const new({
    required this.message,
    this.senderName = 'Agent Realesty',
    this.onDark = false,
    super.key,
  });

  final String message;
  final String senderName;

  /// Night variant for voice/camera screens.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          AgentAvatar(onDark: onDark),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: RealestySpacing.xxs),
                  child: Row(
                    spacing: 6,
                    children: [
                      Text(
                        senderName,
                        style: RealestyTextStyles.badge.copyWith(
                          color: onDark ? c.nuitTexteDiscret : c.texteDiscret,
                        ),
                      ),
                      RealestyIcon(
                        RealestyIcons.spark,
                        size: 12,
                        color: onDark ? c.lueur : c.vertTexte,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: onDark ? c.nuit2 : c.surface,
                    border: Border.all(
                      color: onDark ? c.nuitBordure : c.bordureCarte,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(RealestyRadius.bubbleTail),
                      topRight: Radius.circular(RealestyRadius.bubble),
                      bottomRight: Radius.circular(RealestyRadius.bubble),
                      bottomLeft: Radius.circular(RealestyRadius.bubble),
                    ),
                  ),
                  child: Text(
                    message,
                    style: RealestyTextStyles.bubble.copyWith(
                      color: onDark ? c.nuitTexte : c.encre,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Message from the user: right-aligned dark bubble (max 78% width) with a
/// 4px top-right tail.
class UserBubble extends StatelessWidget {
  const new({required this.message, this.onDark = false, super.key});

  final String message;

  /// Night variant (Lueur bubble, encre text).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.78),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: onDark ? c.lueur : c.encre,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(RealestyRadius.bubble),
                topRight: Radius.circular(RealestyRadius.bubbleTail),
                bottomRight: Radius.circular(RealestyRadius.bubble),
                bottomLeft: Radius.circular(RealestyRadius.bubble),
              ),
            ),
            child: Text(
              message,
              style: RealestyTextStyles.bubble.copyWith(
                color: onDark ? c.encre : c.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
