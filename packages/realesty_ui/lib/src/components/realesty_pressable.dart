import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';

/// Shared tap behavior for Realesty controls: opacity 0.85 while pressed,
/// 0.4 when disabled ([onPressed] is null), 200 ms ease-out transitions,
/// and merged button semantics.
class RealestyPressable extends StatefulWidget {
  const new({
    required this.child,
    this.onPressed,
    this.showDisabled = true,
    this.semanticLabel,
    this.selected,
    this.checked,
    this.isButton = true,
    super.key,
  });

  final Widget child;

  /// Tap callback. When null the control is disabled.
  final VoidCallback? onPressed;

  /// Whether a null [onPressed] dims the child (false for loading buttons,
  /// which are not tappable but keep full opacity).
  final bool showDisabled;

  /// Replaces the label derived from the child's text.
  final String? semanticLabel;

  /// Selection state announced to assistive technologies.
  final bool? selected;

  /// Checked state announced to assistive technologies.
  final bool? checked;

  /// Whether to flag the node as a button.
  final bool isButton;

  static const pressedOpacity = 0.85;
  static const disabledOpacity = 0.4;

  @override
  State<RealestyPressable> createState() => _RealestyPressableState();
}

class _RealestyPressableState extends State<RealestyPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final opacity = !enabled
        ? (widget.showDisabled ? RealestyPressable.disabledOpacity : 1.0)
        : (_pressed ? RealestyPressable.pressedOpacity : 1.0);
    return MergeSemantics(
      child: Semantics(
        button: widget.isButton,
        enabled: enabled,
        selected: widget.selected,
        checked: widget.checked,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: widget.onPressed,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: RealestyMotion.short,
            curve: RealestyMotion.shortCurve,
            child: widget.semanticLabel == null
                ? widget.child
                : ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
    );
  }
}
