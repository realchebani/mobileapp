import 'package:mobileapp/seller_tunnel/voice/voice_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks.dart';

/// Available voice services backed by mocks, with the consent given
/// unless [consentGiven] is false. Stub [recorder] / [player] as needed.
Future<VoiceServices> testVoiceServices({
  MockAgentRepository? agentRepository,
  MockVoiceRecorder? recorder,
  MockVoicePlayer? player,
  bool consentGiven = true,
  bool muted = false,
  List<Uri>? openedUrls,
}) async {
  SharedPreferences.setMockInitialValues({
    VoicePreferences.consentKey: consentGiven,
    VoicePreferences.mutedKey: muted,
  });
  final preferences = await SharedPreferences.getInstance();
  return VoiceServices(
    enabled: true,
    agentRepository: agentRepository ?? MockAgentRepository(),
    createRecorder: () => recorder ?? MockVoiceRecorder(),
    createPlayer: () => player ?? MockVoicePlayer(),
    preferences: VoicePreferences(preferences: preferences),
    openUrl: (url) async {
      openedUrls?.add(url);
      return true;
    },
  );
}
