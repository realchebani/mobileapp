import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';

/// A titled card of the account screens (C2, V19).
class AccountSection extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.only(top: RealestySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: RealestyTextStyles.caption.copyWith(color: c.texteDiscret),
            ),
          ),
          SellerSpaceCard(
            padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
