import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_defaults.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';

/// Why a voice-first step does not open its voice sheet by itself
/// (EPIC-16, plan §2.1): the form shows, with its microphone.
enum VoiceFirstSkip {
  /// Voice is off for the flavor, or a service is missing.
  unavailable,

  /// No voice on this step for this type of property (V1, V7…).
  noVoice,

  /// The dossier was sent.
  locked,

  /// The seller chose « Écrire plutôt » on this device.
  textMode,

  /// The step was already validated and has nothing to confirm.
  validated,

  /// The daily quota was refused today.
  quota,

  /// The last voice session failed on the network a moment ago.
  offline,

  /// The microphone was refused (iOS permission).
  micDenied,
}

/// Opens the voice sheet of a step by itself when voice is the input mode
/// (EPIC-16, Q1 a / Q2 a): once, after the first frame of the step.
abstract final class VoiceFirstLauncher {
  /// Why the sheet must not open by itself, or null when it may.
  static VoiceFirstSkip? skipReason({
    required VoiceServices services,
    required bool hasVoice,
    required bool locked,
    required bool validated,
    required bool hasPending,
    required DateTime now,
  }) {
    final preferences = services.preferences;
    if (!VoiceDefaults.voiceFirst ||
        !services.isAvailable ||
        preferences == null) {
      return VoiceFirstSkip.unavailable;
    }
    if (!hasVoice) return VoiceFirstSkip.noVoice;
    if (locked) return VoiceFirstSkip.locked;
    if (preferences.inputMode == VoiceInputMode.text) {
      return VoiceFirstSkip.textMode;
    }
    if (validated && !hasPending) return VoiceFirstSkip.validated;
    if (preferences.quotaReached(now)) return VoiceFirstSkip.quota;
    if (preferences.recentlyOffline(now, VoiceDefaults.offlinePause)) {
      return VoiceFirstSkip.offline;
    }
    if (preferences.micDenied) return VoiceFirstSkip.micDenied;
    return null;
  }

  /// The « Micro désactivé » banner shows once per app session.
  static bool _micBannerShown = false;

  @visibleForTesting
  static void resetSession() => _micBannerShown = false;

  /// After the first frame of the step under [context]: calls [open] (the
  /// step's sheet) unless [skipReason] says otherwise; a refused
  /// microphone shows a banner once per session.
  static void schedule(
    BuildContext context, {
    required bool hasVoice,
    required bool locked,
    required bool validated,
    required bool hasPending,
    required Future<void> Function() open,
    DateTime Function() clock = DateTime.now,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final services = VoiceServices.of(context);
      final reason = skipReason(
        services: services,
        hasVoice: hasVoice,
        locked: locked,
        validated: validated,
        hasPending: hasPending,
        now: clock(),
      );
      if (reason == null) {
        unawaited(open());
        return;
      }
      if (reason != VoiceFirstSkip.micDenied || _micBannerShown) return;
      _micBannerShown = true;
      final l10n = context.l10n;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(l10n.voiceFirstMicDisabled),
          persist: false,
          action: SnackBarAction(
            label: l10n.voiceOpenSettings,
            onPressed: () => unawaited(services.openSettings()),
          ),
        ),
      );
    });
  }
}
