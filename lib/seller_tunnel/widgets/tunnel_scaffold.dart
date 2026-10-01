import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// Layout of a tunnel step: [header] at the top, [children] in a
/// scrollable column (gap [spacing], padding 8/20/24) and [actionBar]
/// sticky at the bottom, above the keyboard.
class TunnelScaffold extends StatelessWidget {
  const new({
    required this.children,
    this.header,
    this.actionBar,
    this.spacing = RealestySpacing.md,
    super.key,
  });

  /// Usually a `TunnelHeader` (none on V8).
  final Widget? header;

  final List<Widget> children;

  /// Usually an `AgentActionBar`.
  final Widget? actionBar;

  /// Vertical gap between [children].
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.realestyColors.ivoire,
      body: Column(
        children: [
          ?header,
          Expanded(
            child: SafeArea(
              top: header == null,
              bottom: actionBar == null,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xs,
                  RealestySpacing.gutter,
                  RealestySpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: spacing,
                  children: children,
                ),
              ),
            ),
          ),
          ?actionBar,
        ],
      ),
    );
  }
}
