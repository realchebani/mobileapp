import 'package:material_ui/material_ui.dart';

/// Spacing scale (4 → 40) and page gutter.
abstract final class RealestySpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  /// Horizontal page margin (20).
  static const double gutter = 20;

  /// Minimum touch target (44).
  static const double minTouchTarget = 44;
}

/// Corner radii ("generous corners").
abstract final class RealestyRadius {
  /// Bubble tail corner.
  static const double bubbleTail = 4;

  /// Segmented progress segment.
  static const double progress = 2;

  /// Provenance tag.
  static const double tag = 6;

  /// Segmented control thumb.
  static const double segment = 10;

  /// Text fields, banners, icon tiles, snackbars.
  static const double field = 12;

  /// Buttons, segmented track.
  static const double button = 14;

  /// Cards.
  static const double card = 16;

  /// Property cards and chat bubbles.
  static const double bubble = 18;

  /// Bottom sheets and modals.
  static const double sheet = 24;

  /// Pills (badges, chips, circles).
  static const double pill = 999;
}

/// Border widths.
abstract final class RealestyBorders {
  /// Cards, fields, dividers.
  static const double thin = 1;

  /// Buttons, chips, stepper buttons, checkbox, focused/error fields.
  static const double medium = 1.5;

  /// Stepper nodes.
  static const double thick = 2;
}

/// Elevations ("rare shadows"). Level 0 is a 1px `bordureCarte` border.
abstract final class RealestyShadows {
  /// Level 1 — selected segment, small raised elements.
  static const level1 = [
    BoxShadow(color: Color(0x1F141A17), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Level 2 — bottom sheets and modals. CSS `0 12px 40px`: a CSS blur of
  /// 40 is a Gaussian sigma of 20, i.e. a Flutter blurRadius of ≈ 34.
  static const level2 = [
    BoxShadow(color: Color(0x2E141A17), offset: Offset(0, 12), blurRadius: 34),
  ];
}

/// Motion tokens.
abstract final class RealestyMotion {
  /// State changes (pressed, selected, focus…).
  static const Duration short = Duration(milliseconds: 200);

  /// Curve for [short].
  static const Curve shortCurve = Curves.easeOut;

  /// Page and onboarding transitions.
  static const Duration page = Duration(milliseconds: 350);

  /// Curve for [page].
  static const Curve pageCurve = Curves.ease;
}
