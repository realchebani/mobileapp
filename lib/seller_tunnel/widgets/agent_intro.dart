import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// The agent question at the top of a tunnel step (spec 0.2): avatar and
/// "Agent Realesty" bubble.
class AgentIntro extends StatelessWidget {
  const new({required this.message, this.onDark = false, super.key});

  final String message;

  /// Night variant (voice/camera screens).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return AgentBubble(
      senderName: context.l10n.agentName,
      message: message,
      onDark: onDark,
    );
  }
}
