import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/photo_services.dart';
import 'package:mobileapp/ui/ui.dart';

/// Whether the vision AI may analyse the seller's photos and plans: the
/// consent is asked with [PhotoConsentPage] on the first use (EPIC-15).
///
/// A refusal is remembered: the screen is shown again only when [ask] is
/// true (the seller tapped "Activer les suggestions de l’IA").
Future<bool> ensurePhotoAnalysisConsent(
  BuildContext context, {
  bool ask = false,
}) async {
  final preferences = PhotoServices.of(context).preferences;
  if (preferences == null) return false;
  switch (preferences.consent) {
    case PhotoAnalysisConsent.given:
      return true;
    case PhotoAnalysisConsent.declined when !ask:
      return false;
    case PhotoAnalysisConsent.declined:
    case PhotoAnalysisConsent.unknown:
      break;
  }
  final accepted = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const PhotoConsentPage(),
    ),
  );
  // Dismissed without an answer: asked again next time.
  if (accepted == null) return false;
  await preferences.setConsent(given: accepted);
  return accepted;
}

/// Information and explicit consent before the first analysis of a photo
/// or a plan by the vision AI (RGPD): who sees the images, nothing kept,
/// never a measurement, no automatic blurring. Pops `true` when accepted,
/// `false` when declined.
class PhotoConsentPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    Widget section(RealestyIcons icon, String? title, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RealestySpacing.sm,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.vertTeinte,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: RealestyIcon(icon, color: c.vertTexte),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              if (title != null)
                Text(
                  title,
                  style: RealestyTextStyles.label.copyWith(color: c.encre),
                ),
              Text(
                text,
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: c.ivoire,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xl,
                  RealestySpacing.gutter,
                  RealestySpacing.md,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: c.nuit,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: RealestyIcon(
                        RealestyIcons.camera,
                        size: 26,
                        color: c.lueur,
                      ),
                    ),
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.photosConsentTitle,
                      style: RealestyTextStyles.title1.copyWith(color: c.encre),
                    ),
                  ),
                  const SizedBox(height: RealestySpacing.xs),
                  Text(
                    l10n.photosConsentIntro,
                    style: RealestyTextStyles.body.copyWith(color: c.encre2),
                  ),
                  const SizedBox(height: RealestySpacing.lg),
                  section(
                    RealestyIcons.users,
                    l10n.photosConsentProvidersTitle,
                    l10n.photosConsentProviders,
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  section(
                    RealestyIcons.spark,
                    l10n.photosConsentNoFiguresTitle,
                    l10n.photosConsentNoFigures,
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  section(RealestyIcons.eye, null, l10n.photosConsentPeople),
                  const SizedBox(height: RealestySpacing.md),
                  section(RealestyIcons.lock, null, l10n.photosConsentKept),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.sm,
                RealestySpacing.gutter,
                RealestySpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: RealestySpacing.xs,
                children: [
                  RealestyButton(
                    label: l10n.photosConsentAccept,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  RealestyButton(
                    label: l10n.photosConsentDecline,
                    variant: RealestyButtonVariant.text,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
