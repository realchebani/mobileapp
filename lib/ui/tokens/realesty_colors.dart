import 'package:material_ui/material_ui.dart';

/// Realesty color tokens, exposed as a [ThemeExtension] so widgets can read
/// them with `context.realestyColors`.
///
/// Token names follow the French names used in the design system
/// ("DS-Fondations").
@immutable
class RealestyColors extends ThemeExtension<RealestyColors> {
  const new({
    required this.encre,
    required this.encre2,
    required this.texteDiscret,
    required this.placeholder,
    required this.ligne,
    required this.bordureCarte,
    required this.ivoire,
    required this.surface,
    required this.surface2,
    required this.imagePlaceholder,
    required this.vert,
    required this.vertTexte,
    required this.vertTeinte,
    required this.vertLienPresse,
    required this.nuit,
    required this.nuit2,
    required this.nuit3,
    required this.lueur,
    required this.nuitBordure,
    required this.nuitTexteDiscret,
    required this.nuitTexte,
    required this.essentiel,
    required this.essentielFond,
    required this.premium,
    required this.premiumFond,
    required this.expert,
    required this.expertFond,
    required this.attention,
    required this.attentionFond,
    required this.erreur,
    required this.erreurFond,
  });

  /// The single Realesty palette (there is no dark mode: the night colors
  /// are only used by the voice and camera screens).
  static const light = RealestyColors(
    encre: Color(0xFF141A17),
    encre2: Color(0xFF39413B),
    texteDiscret: Color(0xFF5B635D),
    placeholder: Color(0xFF6B726C),
    ligne: Color(0xFFD3D0C4),
    bordureCarte: Color(0xFFE3E1D8),
    ivoire: Color(0xFFF6F5EF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEEDE5),
    imagePlaceholder: Color(0xFFDCD8CA),
    vert: Color(0xFF6CC43A),
    vertTexte: Color(0xFF2E7D14),
    vertTeinte: Color(0xFFE7F4DE),
    vertLienPresse: Color(0xFF1F5A0C),
    nuit: Color(0xFF0F1713),
    nuit2: Color(0xFF18221D),
    nuit3: Color(0xFF26322B),
    lueur: Color(0xFF8BE05A),
    nuitBordure: Color(0xFF2F3B34),
    nuitTexteDiscret: Color(0xFFA9B5AD),
    nuitTexte: Color(0xFFFFFFFF),
    essentiel: Color(0xFF2E7D14),
    essentielFond: Color(0xFFE7F4DE),
    premium: Color(0xFF855F0E),
    premiumFond: Color(0xFFF6ECD4),
    expert: Color(0xFF1E4E9C),
    expertFond: Color(0xFFE3ECF9),
    attention: Color(0xFF8F5400),
    attentionFond: Color(0xFFFBEBD3),
    erreur: Color(0xFFB42318),
    erreurFond: Color(0xFFFCE9E7),
  );

  // Neutrals.

  /// Encre — main text, primary button background.
  final Color encre;

  /// Encre 2 — secondary text, field labels.
  final Color encre2;

  /// Texte discret — subtitles, captions.
  final Color texteDiscret;

  /// Placeholder — field placeholder text.
  final Color placeholder;

  /// Ligne — field borders, dividers, inactive progress segments.
  final Color ligne;

  /// Bordure carte — card borders, list dividers, progress tracks.
  final Color bordureCarte;

  /// Ivoire — screen background.
  final Color ivoire;

  /// Surface — cards, fields, sheets.
  final Color surface;

  /// Surface 2 — segmented track, icon tiles, "Déclaré" tag.
  final Color surface2;

  /// Image placeholder — background while an image loads.
  final Color imagePlaceholder;

  // Brand.

  /// Vert Realesty — mic button, accent CTA, progress fill.
  final Color vert;

  /// Vert texte — validated text/icons, links, switch on, completed steps.
  final Color vertTexte;

  /// Vert teinte — selection background, certified badge.
  final Color vertTeinte;

  /// Vert lien pressé — pressed link.
  final Color vertLienPresse;

  // Night (voice / camera screens only, not a dark mode).

  /// Nuit — night screen background.
  final Color nuit;

  /// Nuit 2 — night agent bubble, dark icon button.
  final Color nuit2;

  /// Nuit 3 — night agent avatar, raised night surfaces.
  final Color nuit3;

  /// Lueur — night accent (logo accent, user bubble on night).
  final Color lueur;

  /// Bordure bulle nuit — night bubble border.
  final Color nuitBordure;

  /// Texte discret nuit — muted text on night backgrounds.
  final Color nuitTexteDiscret;

  /// Texte nuit — text on night backgrounds.
  final Color nuitTexte;

  // Plans & states (foreground / background pairs).

  /// Essentiel — plan "Essentiel" text/icon.
  final Color essentiel;

  /// Essentiel fond — plan "Essentiel" background.
  final Color essentielFond;

  /// Premium — plan "Premium" text/icon.
  final Color premium;

  /// Premium fond — plan "Premium" background.
  final Color premiumFond;

  /// Expert & info — plan "Expert" and informational text/icon.
  final Color expert;

  /// Expert & info fond — plan "Expert" and informational background.
  final Color expertFond;

  /// Attention — warning text/icon ("À compléter", "Estimé IA").
  final Color attention;

  /// Attention fond — warning background.
  final Color attentionFond;

  /// Erreur — error text/icon/border ("Manquant").
  final Color erreur;

  /// Erreur fond — error background.
  final Color erreurFond;

  @override
  RealestyColors copyWith({
    Color? encre,
    Color? encre2,
    Color? texteDiscret,
    Color? placeholder,
    Color? ligne,
    Color? bordureCarte,
    Color? ivoire,
    Color? surface,
    Color? surface2,
    Color? imagePlaceholder,
    Color? vert,
    Color? vertTexte,
    Color? vertTeinte,
    Color? vertLienPresse,
    Color? nuit,
    Color? nuit2,
    Color? nuit3,
    Color? lueur,
    Color? nuitBordure,
    Color? nuitTexteDiscret,
    Color? nuitTexte,
    Color? essentiel,
    Color? essentielFond,
    Color? premium,
    Color? premiumFond,
    Color? expert,
    Color? expertFond,
    Color? attention,
    Color? attentionFond,
    Color? erreur,
    Color? erreurFond,
  }) {
    return RealestyColors(
      encre: encre ?? this.encre,
      encre2: encre2 ?? this.encre2,
      texteDiscret: texteDiscret ?? this.texteDiscret,
      placeholder: placeholder ?? this.placeholder,
      ligne: ligne ?? this.ligne,
      bordureCarte: bordureCarte ?? this.bordureCarte,
      ivoire: ivoire ?? this.ivoire,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      imagePlaceholder: imagePlaceholder ?? this.imagePlaceholder,
      vert: vert ?? this.vert,
      vertTexte: vertTexte ?? this.vertTexte,
      vertTeinte: vertTeinte ?? this.vertTeinte,
      vertLienPresse: vertLienPresse ?? this.vertLienPresse,
      nuit: nuit ?? this.nuit,
      nuit2: nuit2 ?? this.nuit2,
      nuit3: nuit3 ?? this.nuit3,
      lueur: lueur ?? this.lueur,
      nuitBordure: nuitBordure ?? this.nuitBordure,
      nuitTexteDiscret: nuitTexteDiscret ?? this.nuitTexteDiscret,
      nuitTexte: nuitTexte ?? this.nuitTexte,
      essentiel: essentiel ?? this.essentiel,
      essentielFond: essentielFond ?? this.essentielFond,
      premium: premium ?? this.premium,
      premiumFond: premiumFond ?? this.premiumFond,
      expert: expert ?? this.expert,
      expertFond: expertFond ?? this.expertFond,
      attention: attention ?? this.attention,
      attentionFond: attentionFond ?? this.attentionFond,
      erreur: erreur ?? this.erreur,
      erreurFond: erreurFond ?? this.erreurFond,
    );
  }

  @override
  RealestyColors lerp(covariant RealestyColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RealestyColors(
      encre: l(encre, other.encre),
      encre2: l(encre2, other.encre2),
      texteDiscret: l(texteDiscret, other.texteDiscret),
      placeholder: l(placeholder, other.placeholder),
      ligne: l(ligne, other.ligne),
      bordureCarte: l(bordureCarte, other.bordureCarte),
      ivoire: l(ivoire, other.ivoire),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      imagePlaceholder: l(imagePlaceholder, other.imagePlaceholder),
      vert: l(vert, other.vert),
      vertTexte: l(vertTexte, other.vertTexte),
      vertTeinte: l(vertTeinte, other.vertTeinte),
      vertLienPresse: l(vertLienPresse, other.vertLienPresse),
      nuit: l(nuit, other.nuit),
      nuit2: l(nuit2, other.nuit2),
      nuit3: l(nuit3, other.nuit3),
      lueur: l(lueur, other.lueur),
      nuitBordure: l(nuitBordure, other.nuitBordure),
      nuitTexteDiscret: l(nuitTexteDiscret, other.nuitTexteDiscret),
      nuitTexte: l(nuitTexte, other.nuitTexte),
      essentiel: l(essentiel, other.essentiel),
      essentielFond: l(essentielFond, other.essentielFond),
      premium: l(premium, other.premium),
      premiumFond: l(premiumFond, other.premiumFond),
      expert: l(expert, other.expert),
      expertFond: l(expertFond, other.expertFond),
      attention: l(attention, other.attention),
      attentionFond: l(attentionFond, other.attentionFond),
      erreur: l(erreur, other.erreur),
      erreurFond: l(erreurFond, other.erreurFond),
    );
  }
}

/// Access to the Realesty tokens from a [BuildContext].
extension RealestyColorsX on BuildContext {
  /// The [RealestyColors] of the ambient theme, falling back to
  /// [RealestyColors.light] when the theme does not register the extension.
  RealestyColors get realestyColors =>
      Theme.of(this).extension<RealestyColors>() ?? RealestyColors.light;
}
