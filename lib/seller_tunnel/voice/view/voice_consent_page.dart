import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mobileapp/ui/ui.dart';

/// Whether voice can be used now: available for this flavor, and the
/// seller gave the RGPD consent (asked with [VoiceConsentPage] on the
/// first use). The microphone permission is asked afterwards by the
/// recorder.
Future<bool> ensureVoiceConsent(BuildContext context) async {
  final services = VoiceServices.of(context);
  final preferences = services.preferences;
  if (!services.isAvailable || preferences == null) return false;
  if (preferences.consentGiven) return true;
  final accepted = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const VoiceConsentPage(),
    ),
  );
  if (accepted != true) return false;
  await preferences.giveConsent();
  return true;
}

/// Information and explicit consent before the first use of the
/// microphone (RGPD): who processes the audio, nothing kept, screen mode
/// always available. Pops `true` when accepted.
class VoiceConsentPage extends StatelessWidget {
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
                        RealestyIcons.mic,
                        size: 26,
                        color: c.lueur,
                      ),
                    ),
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.voiceConsentTitle,
                      style: RealestyTextStyles.title1.copyWith(color: c.encre),
                    ),
                  ),
                  const SizedBox(height: RealestySpacing.xs),
                  Text(
                    l10n.voiceConsentIntro,
                    style: RealestyTextStyles.body.copyWith(color: c.encre2),
                  ),
                  const SizedBox(height: RealestySpacing.lg),
                  section(
                    RealestyIcons.users,
                    l10n.voiceConsentProvidersTitle,
                    l10n.voiceConsentProviders,
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  section(
                    RealestyIcons.shield,
                    l10n.voiceConsentRetentionTitle,
                    l10n.voiceConsentRetention,
                  ),
                  const SizedBox(height: RealestySpacing.md),
                  section(RealestyIcons.lock, null, l10n.voiceConsentIdentity),
                  const SizedBox(height: RealestySpacing.md),
                  section(
                    RealestyIcons.keyboard,
                    null,
                    l10n.voiceConsentScreen,
                  ),
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
                    label: l10n.voiceConsentAccept,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  RealestyButton(
                    label: l10n.voiceConsentDecline,
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
