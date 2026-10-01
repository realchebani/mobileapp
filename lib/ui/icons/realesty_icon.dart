import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';

/// Realesty icon set: 24×24 grid, 1.8 stroke, round caps and joins.
///
/// Recommended sizes: 22 (tab bar), 20 (buttons, lists), 18 (fields),
/// 16 (chips), 14 (badges), 12.
enum RealestyIcons {
  bell('bell'),
  briefcase('briefcase'),
  building('building'),
  calendar('calendar'),
  camera('camera'),
  car('car'),
  chat('chat'),
  check('check'),
  chevronDown('chevron-down'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  clock('clock'),
  close('close'),
  cube('cube'),
  euro('euro'),
  eye('eye'),
  file('file'),
  heart('heart'),
  home('home'),
  infoCircle('info-circle'),
  keyboard('keyboard'),
  land('land'),
  lock('lock'),
  mail('mail'),
  map('map'),
  mic('mic'),
  minus('minus'),
  pen('pen'),
  phone('phone'),
  pin('pin'),
  plan('plan'),
  plus('plus'),
  scan('scan'),
  school('school'),
  search('search'),
  share('share'),
  shield('shield'),
  spark('spark'),
  star('star'),
  swap('swap'),
  target('target'),
  tree('tree'),
  trending('trending'),
  truck('truck'),
  upload('upload'),
  user('user'),
  users('users'),
  vault('vault');

  new(this.fileName);

  /// File name (without extension) in `assets/icons`.
  final String fileName;

  /// Asset path of the SVG.
  String get assetPath => 'assets/icons/$fileName.svg';
}

/// Renders a [RealestyIcons] glyph tinted with [color].
class RealestyIcon extends StatelessWidget {
  const new(
    this.icon, {
    this.size = 20,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final RealestyIcons icon;

  /// Width and height in logical pixels.
  final double size;

  /// Tint; defaults to the ambient [IconTheme] color, then `encre`.
  final Color? color;

  /// Accessibility label. Decorative icons (the default) are excluded from
  /// the semantics tree.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tint =
        color ?? IconTheme.of(context).color ?? context.realestyColors.encre;
    return SvgPicture.asset(
      icon.assetPath,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
