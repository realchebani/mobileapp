import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

void main() {
  test('spacing scale', () {
    expect(
      [
        RealestySpacing.xxs,
        RealestySpacing.xs,
        RealestySpacing.sm,
        RealestySpacing.md,
        RealestySpacing.lg,
        RealestySpacing.xl,
        RealestySpacing.xxl,
        RealestySpacing.xxxl,
      ],
      [4, 8, 12, 16, 20, 24, 32, 40],
    );
    expect(RealestySpacing.gutter, 20);
    expect(RealestySpacing.minTouchTarget, 44);
  });

  test('radii', () {
    expect(RealestyRadius.tag, 6);
    expect(RealestyRadius.field, 12);
    expect(RealestyRadius.button, 14);
    expect(RealestyRadius.card, 16);
    expect(RealestyRadius.bubble, 18);
    expect(RealestyRadius.sheet, 24);
  });

  test('shadows', () {
    expect(RealestyShadows.level1.single.offset, const Offset(0, 1));
    expect(RealestyShadows.level1.single.blurRadius, 2);
    expect(RealestyShadows.level2.single.offset, const Offset(0, 12));
    expect(RealestyShadows.level2.single.blurRadius, 34);
  });

  test('motion', () {
    expect(RealestyMotion.short, const Duration(milliseconds: 200));
    expect(RealestyMotion.page, const Duration(milliseconds: 350));
    expect(RealestyMotion.shortCurve, Curves.easeOut);
    expect(RealestyMotion.pageCurve, Curves.ease);
    expect(RealestyBorders.medium, 1.5);
  });
}
