import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:mobileapp/ui/ui.dart';

/// Sticky bottom bar of a tunnel step (spec 0.3): optional hint line, the
/// microphone and the main action.
///
/// The microphone shows when the step handles it ([onMicPressed]) and
/// voice is available ([VoiceServices.isAvailable]: `VOICE_ENABLED` flag of
/// the flavor); otherwise the tunnel stays screen-only.
class AgentActionBar extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.hint,
    this.isLoading = false,
    this.variant = RealestyButtonVariant.primary,
    this.trailingIcon,
    this.showMic,
    this.onMicPressed,
    super.key,
  });

  /// Main action label ("Continuer"…).
  final String label;

  /// Main action; null disables it.
  final VoidCallback? onPressed;

  /// Hint above the actions. The voice hint ("Répondez à la voix ou à
  /// l’écran", `l10n.tunnelHintVoiceOrScreen`) is hidden while the
  /// microphone is.
  final String? hint;

  /// Shows a spinner in the main action and blocks taps.
  final bool isLoading;

  /// Primary (default) or accent (V7 "Envoyer mon dossier").
  final RealestyButtonVariant variant;

  /// Optional icon after the main action label.
  final RealestyIcons? trailingIcon;

  /// Forces the microphone on or off; by default it shows when
  /// [onMicPressed] is set and voice is available.
  final bool? showMic;

  final VoidCallback? onMicPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final showMic =
        this.showMic ??
        (onMicPressed != null && VoiceServices.of(context).isAvailable);
    final hint = showMic || this.hint != l10n.tunnelHintVoiceOrScreen
        ? this.hint
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ivoire,
        border: Border(top: BorderSide(color: c.bordureCarte)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: RealestySpacing.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.sm,
            RealestySpacing.gutter,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              if (hint != null)
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.badge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: c.texteDiscret,
                  ),
                ),
              Row(
                spacing: 14,
                children: [
                  if (showMic)
                    RealestyMicButton(
                      semanticLabel: l10n.tunnelMicLabel,
                      onPressed: onMicPressed,
                    ),
                  Expanded(
                    child: RealestyButton(
                      label: label,
                      variant: variant,
                      trailingIcon: trailingIcon,
                      isLoading: isLoading,
                      loadingSemanticLabel: l10n.tunnelLoading,
                      onPressed: onPressed,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
