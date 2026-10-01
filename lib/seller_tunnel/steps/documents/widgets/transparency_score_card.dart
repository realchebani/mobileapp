import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// "Score de transparence" card: a progress ring with the score and a hint
/// (the next most useful document).
class TransparencyScoreCard extends StatelessWidget {
  const new({required this.score, required this.hint, super.key});

  /// 0–100.
  final int score;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Row(
        spacing: 14,
        children: [
          Semantics(
            label: l10n.documentsScoreSemantics(score),
            excludeSemantics: true,
            child: ScoreRing(score: score),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: RealestySpacing.xxs,
              children: [
                Text(
                  l10n.documentsScoreTitle,
                  style: RealestyTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.encre,
                  ),
                ),
                Text(
                  hint,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
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

/// Progress ring of the design system (64, stroke 7, arc from the top)
/// with the score in its center.
class ScoreRing extends StatelessWidget {
  const new({required this.score, super.key});

  /// 0–100.
  final int score;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: score.clamp(0, 100) / 100,
          track: c.bordureCarte,
          arc: c.vert,
        ),
        child: Center(
          child: Text(
            '$score',
            style: RealestyTextStyles.title2.copyWith(
              fontSize: 16,
              color: c.encre,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const new({required this.progress, required this.track, required this.arc});

  final double progress;
  final Color track;
  final Color arc;

  static const double _stroke = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint
          ..color = arc
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}
