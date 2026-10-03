import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_button.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// The strokes drawn on a [SignaturePad] (positions in the pad's logical
/// pixels).
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  /// The strokes, oldest first.
  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  /// Whether nothing (or only dots) was drawn.
  bool get isEmpty => !_strokes.any((stroke) => stroke.length > 1);

  void _start(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void _extend(Offset point) {
    _strokes.lastOrNull?.add(point);
    notifyListeners();
  }

  /// Removes every stroke.
  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// The signature as a PNG (black strokes on a transparent background),
  /// at [pixelRatio] times the pad's size; null when [isEmpty].
  Future<Uint8List?> toPng({double pixelRatio = 2}) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    paintStrokes(canvas, _strokes, const Color(0xFF141A17));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_size.width * pixelRatio).ceil(),
      (_size.height * pixelRatio).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  /// Paints [strokes] on [canvas] with [color].
  static void paintStrokes(
    Canvas canvas,
    List<List<Offset>> strokes,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}

/// Signature area (V11c): a white card of [height] where the user signs
/// with a finger, the [hint] while empty and a "clear" text button.
class SignaturePad extends StatefulWidget {
  const new({
    required this.controller,
    required this.hint,
    required this.clearLabel,
    required this.semanticLabel,
    this.height = 130,
    this.enabled = true,
    this.hasError = false,
    super.key,
  });

  final SignaturePadController controller;
  final String hint;
  final String clearLabel;
  final String semanticLabel;
  final double height;
  final bool enabled;

  /// Shows an Erreur border.
  final bool hasError;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SignaturePad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final controller = widget.controller;
    return Semantics(
      label: widget.semanticLabel,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.card),
          border: Border.all(
            color: widget.hasError ? c.erreur : c.ligne,
            width: RealestyBorders.medium,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            controller._size = constraints.biggest;
            return Stack(
              children: [
                Positioned.fill(
                  // Wins the gesture arena as soon as the finger is down,
                  // so that a sheet or a list never scrolls while signing.
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      if (widget.enabled)
                        _ImmediatePanRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _ImmediatePanRecognizer
                            >(
                              _ImmediatePanRecognizer.new,
                              (recognizer) => recognizer
                                ..dragStartBehavior = DragStartBehavior.down
                                ..onStart = (details) {
                                  controller._start(details.localPosition);
                                }
                                ..onUpdate = (details) {
                                  controller._extend(details.localPosition);
                                },
                            ),
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(
                        strokes: controller.strokes,
                        color: c.encre,
                      ),
                    ),
                  ),
                ),
                if (controller.isEmpty)
                  IgnorePointer(
                    child: Center(
                      child: Text(
                        widget.hint,
                        style: RealestyTextStyles.bodySmall.copyWith(
                          color: c.placeholder,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: RealestySpacing.xxs,
                  bottom: 0,
                  child: RealestyButton(
                    label: widget.clearLabel,
                    variant: RealestyButtonVariant.text,
                    height: RealestySpacing.minTouchTarget,
                    expand: false,
                    onPressed: widget.enabled && controller.strokes.isNotEmpty
                        ? controller.clear
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A pan recognizer that claims the pointer at once.
class _ImmediatePanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _SignaturePainter extends CustomPainter {
  const new({required this.strokes, required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      SignaturePadController.paintStrokes(canvas, strokes, color);

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}
