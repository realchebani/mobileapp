import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:voice_repository/voice_repository.dart';

/// Voice settings remembered on the device: the RGPD consent to send the
/// voice to the AI providers, and whether the agent's voice is muted.
class VoicePreferences {
  const new({required this._preferences});

  final SharedPreferences _preferences;

  /// Bump the version when the consent text changes materially.
  static const consentKey = 'voice_consent_v1';
  static const mutedKey = 'voice_agent_muted';

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
