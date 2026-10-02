import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/cubit/voice_conversation_cubit.dart';
import 'package:mobileapp/ui/ui.dart';

/// The Night orb of the voice screens (V4 mockup: rings 170 / 132 / 95,
/// Lueur core 64 with a glow). The halo follows the input [level] while
/// listening and breathes while the agent thinks or speaks.
class ListeningOrb extends StatelessWidget {
  const new({
    required this.phase,
    required this.level,
    this.size = 170,
    super.key,
  });

  final VoicePhase phase;

  /// Input level 0…1.
  final double level;

  /// Outer diameter (170 on V4, 95 on the V6 sheet).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final active = switch (phase) {
      VoicePhase.listening => 0.6 + 0.4 * level,
      VoicePhase.transcribing ||
      VoicePhase.thinking ||
      VoicePhase.speaking => 0.8,
      VoicePhase.idle || VoicePhase.paused || VoicePhase.done => 0.4,
    };
    final scale = size / 170;
    final icon = switch (phase) {
      VoicePhase.paused || VoicePhase.idle => RealestyIcons.mic,
      VoicePhase.done => RealestyIcons.check,
      VoicePhase.speaking => RealestyIcons.chat,
      VoicePhase.listening ||
      VoicePhase.transcribing ||
      VoicePhase.thinking => RealestyIcons.mic,
    };
    Widget ring(double diameter, Color fill, Color? border, Widget child) =>
        AnimatedContainer(
          duration: RealestyMotion.short,
          width: diameter * scale,
          height: diameter * scale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: border == null ? null : Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: child,
        );
    return ExcludeSemantics(
      child: ring(
        170,
        Colors.transparent,
        c.lueur.withValues(alpha: 0.18 * active),
        ring(
          132 + 8 * level,
          c.lueur.withValues(alpha: 0.07 * active),
          c.lueur.withValues(alpha: 0.22 * active),
          ring(
            95 + 6 * level,
            c.lueur.withValues(alpha: 0.16 * active),
            null,
            Container(
              width: 64 * scale,
              height: 64 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.lueur,
                boxShadow: [
                  BoxShadow(
                    color: c.lueur.withValues(alpha: 0.45 * active),
                    blurRadius: 40 * scale,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: RealestyIcon(icon, size: 24 * scale, color: c.encre),
            ),
          ),
        ),
      ),
    );
  }
}

/// 34 Lueur bars (3 px, 4–28 px high) of the recent input levels.
class VoiceWaveform extends StatelessWidget {
  const new({required this.levels, super.key});

  /// 0…1, oldest first.
  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    const count = VoiceConversationState.levelCount;
    final padded = [
      for (var i = levels.length; i < count; i++) 0.0,
      ...levels.take(count),
    ];
    return ExcludeSemantics(
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            for (final level in padded)
              Container(
                width: 3,
                height: 4 + 24 * level,
                decoration: BoxDecoration(
                  color: c.lueur,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The status line under the orb ("L’agent vous écoute…").
String voicePhaseLabel(AppLocalizations l10n, VoicePhase phase) =>
    switch (phase) {
      VoicePhase.listening => l10n.voiceListening,
      VoicePhase.transcribing => l10n.voiceTranscribing,
      VoicePhase.thinking => l10n.voiceThinking,
      VoicePhase.speaking => l10n.voiceSpeaking,
      VoicePhase.paused => l10n.voicePaused,
      VoicePhase.done => l10n.voiceDone,
      VoicePhase.idle => '',
    };

/// The message of a [VoiceError].
String voiceErrorLabel(AppLocalizations l10n, VoiceError error) =>
    switch (error) {
      VoiceError.permissionDenied => l10n.voicePermissionDenied,
      VoiceError.empty => l10n.voiceErrorEmpty,
      VoiceError.network => l10n.voiceErrorNetwork,
      VoiceError.quota => l10n.voiceErrorQuota,
      VoiceError.locked => l10n.voiceErrorLocked,
      VoiceError.tooLong => l10n.voiceErrorTooLong,
      VoiceError.save => l10n.voiceErrorSave,
    };

/// A Night pill: an understood answer (Lueur, check icon) or a pending one
/// (Nuit 3, "Assainissement ?").
class FactPill extends StatelessWidget {
  const new({
    required this.label,
    this.pending = false,
    this.onPressed,
    super.key,
  });

  final String label;
  final bool pending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final foreground = pending ? c.nuitTexte : c.encre;
    return Semantics(
      button: onPressed != null,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: pending ? c.nuit3 : c.lueur,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              if (!pending)
                RealestyIcon(RealestyIcons.check, size: 12, color: foreground),
              Text(
                label,
                style: RealestyTextStyles.badge.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round Night button (V4 bottom bar).
class NightRoundButton extends StatelessWidget {
  const new({
    required this.semanticLabel,
    required this.child,
    required this.onPressed,
    this.size = 56,
    this.accent = false,
    super.key,
  });

  final String semanticLabel;
  final Widget child;
  final VoidCallback? onPressed;
  final double size;

  /// Lueur fill with a halo (pause / resume).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent ? c.lueur : c.nuit2,
            border: accent ? null : Border.all(color: c.nuitBordure),
            boxShadow: accent
                ? [
                    BoxShadow(
                      color: c.lueur.withValues(alpha: 0.18),
                      spreadRadius: 8,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Two bars (pause glyph), [color] on Lueur.
class PauseGlyph extends StatelessWidget {
  const new({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (var i = 0; i < 2; i++)
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
