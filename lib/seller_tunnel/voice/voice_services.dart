import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:voice_repository/voice_repository.dart';

/// How a voice-first step opens (EPIC-16): with its voice sheet, or on the
/// form (« Écrire plutôt »).
enum VoiceInputMode { voice, text }

/// Voice settings remembered on the device: the RGPD consent to send the
/// voice to the AI providers, whether the agent's voice is muted, the
/// input mode (EPIC-16) and what keeps the sheet from opening by itself
/// (quota of the day used up, network failure, microphone refused).
class VoicePreferences {
  const new({required this._preferences});

  final SharedPreferences _preferences;

  /// Bump the version when the consent text changes materially (v4,
  /// EPIC-16: no names, the thread kept for the expert, contacts masked).
  static const consentKey = 'voice_consent_v4';
  static const mutedKey = 'voice_agent_muted';
  static const inputModeKey = 'voice_input_mode';
  static const quotaDayKey = 'voice_quota_day';
  static const offlineAtKey = 'voice_offline_at';
  static const micDeniedKey = 'voice_mic_denied';

  /// One preference for the device (Q3 a); voice by default.
  VoiceInputMode get inputMode =>
      _preferences.getString(inputModeKey) == VoiceInputMode.text.name
      ? VoiceInputMode.text
      : VoiceInputMode.voice;

  Future<void> setInputMode(VoiceInputMode mode) =>
      _preferences.setString(inputModeKey, mode.name);

  static String _day(DateTime now) {
    final utc = now.toUtc();
    return '${utc.year}-${utc.month}-${utc.day}';
  }

  /// The daily quota was refused today (until midnight UTC).
  bool quotaReached(DateTime now) =>
      _preferences.getString(quotaDayKey) == _day(now);

  Future<void> markQuotaReached(DateTime now) =>
      _preferences.setString(quotaDayKey, _day(now));

  /// A voice session failed on the network less than [pause] ago.
  bool recentlyOffline(DateTime now, Duration pause) {
    final at = _preferences.getInt(offlineAtKey);
    return at != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(at)) < pause;
  }

  Future<void> markOffline(DateTime now) =>
      _preferences.setInt(offlineAtKey, now.millisecondsSinceEpoch);

  /// The microphone was refused (iOS permission) at the last attempt.
  bool get micDenied => _preferences.getBool(micDeniedKey) ?? false;

  Future<void> setMicDenied({required bool denied}) =>
      _preferences.setBool(micDeniedKey, denied);

  bool get consentGiven => _preferences.getBool(consentKey) ?? false;

  Future<void> giveConsent() => _preferences.setBool(consentKey, true);

  bool get agentMuted => _preferences.getBool(mutedKey) ?? false;

  Future<void> setAgentMuted({required bool muted}) =>
      _preferences.setBool(mutedKey, muted);
}

/// What the voice features need, provided above the router by `App`.
///
/// Voice is available only when the flavor enables it (`VOICE_ENABLED` in
/// `config/<flavor>.json`) and every service is given; otherwise the
/// microphone stays hidden and the tunnel is screen-only.
class VoiceServices {
  const new({
    this.enabled = false,
    this.agentRepository,
    this.createRecorder,
    this.createPlayer,
    this.preferences,
    this.openUrl = launchUrl,
  });

  /// Whether the flavor enables voice (`VOICE_ENABLED`).
  static const flagEnabled = bool.fromEnvironment('VOICE_ENABLED');

  final bool enabled;
  final AgentRepository? agentRepository;
  final VoiceRecorder Function()? createRecorder;
  final VoicePlayer Function()? createPlayer;
  final VoicePreferences? preferences;

  /// Opens a URL (the iOS settings after a refused microphone).
  final Future<bool> Function(Uri url) openUrl;

  /// Opens the app's page of the iOS Settings (microphone access).
  Future<void> openSettings() async {
    await openUrl(Uri.parse('app-settings:'));
  }

  bool get isAvailable =>
      enabled &&
      agentRepository != null &&
      createRecorder != null &&
      createPlayer != null &&
      preferences != null;

  /// The services above [context], or disabled ones when none are
  /// provided.
  // A lookup, like `Theme.of`.
  // ignore: prefer_constructors_over_static_methods
  static VoiceServices of(BuildContext context) {
    try {
      return context.read<VoiceServices>();
    } on ProviderNotFoundException {
      return const VoiceServices();
    }
  }
}
