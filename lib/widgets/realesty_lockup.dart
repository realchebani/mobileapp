import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// Horizontal logo lockup used at the top of the login screens (mark 44,
/// wordmark 16), left-aligned.
class RealestyLockup extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: AlignmentDirectional.centerStart,
      child: RealestyLogo(showWordmark: true),
    );
  }
}
