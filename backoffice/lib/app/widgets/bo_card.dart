import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// A white card of the back-office, with an optional title and action.
class BoCard extends StatelessWidget {
  const new({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(RealestySpacing.lg),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    style: RealestyTextStyles.title2.copyWith(color: c.encre),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: RealestySpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// A centered message with an optional action (empty, error, gate pages).
class BoMessage extends StatelessWidget {
  const new({
    required this.title,
    this.body,
    this.action,
    this.icon = RealestyIcons.infoCircle,
    super.key,
  });

  final String title;
  final String? body;
  final Widget? action;
  final RealestyIcons icon;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(RealestySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RealestyIcon(icon, size: 32, color: c.texteDiscret),
              const SizedBox(height: RealestySpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.title2.copyWith(color: c.encre),
              ),
              if (body != null) ...[
                const SizedBox(height: RealestySpacing.xs),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: RealestySpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small colored label (status, flags).
class BoChip extends StatelessWidget {
  const new(this.label, {this.color, this.background, super.key});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RealestySpacing.xs,
        vertical: RealestySpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: background ?? c.surface2,
        borderRadius: BorderRadius.circular(RealestyRadius.tag),
      ),
      child: Text(
        label,
        style: RealestyTextStyles.label.copyWith(color: color ?? c.encre2),
      ),
    );
  }
}
