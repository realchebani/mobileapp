import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_pressable.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// 44×26 pill switch: Vert texte when on, Ligne when off, white knob.
class RealestySwitch extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;

  /// Called with the new value; null disables the switch.
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return RealestyPressable(
      semanticLabel: semanticLabel,
      checked: value,
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      child: SizedBox(
        width: RealestySpacing.minTouchTarget,
        height: RealestySpacing.minTouchTarget,
        child: Center(
          child: AnimatedContainer(
            duration: RealestyMotion.short,
            curve: RealestyMotion.shortCurve,
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? c.vertTexte : c.ligne,
              borderRadius: BorderRadius.circular(RealestyRadius.pill),
            ),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: RealestyShadows.level1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with a title, an optional subtitle and badge, and a
/// [RealestySwitch] (V11 / V11a photo preferences).
class SwitchRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.badge,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Shown after the title (e.g. a "Bientôt" badge).
  final Widget? badge;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final subtitle = this.subtitle;
    return Row(
      spacing: RealestySpacing.sm,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Wrap(
                spacing: RealestySpacing.xs,
                runSpacing: RealestySpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  ?badge,
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
            ],
          ),
        ),
        RealestySwitch(
          value: value,
          onChanged: onChanged,
          semanticLabel: title,
        ),
      ],
    );
  }
}
