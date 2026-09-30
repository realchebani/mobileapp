import 'package:material_ui/material_ui.dart';

/// Fills the viewport with [child] (typically a [Column] with a [Spacer]
/// pushing actions to the bottom), and scrolls when [child] is taller than
/// the viewport (small screens, large text).
class FillScrollView extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    );
  }
}
