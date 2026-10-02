import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_capture.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_processor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The seller's answer to the consent screen of the vision AI.
enum PhotoAnalysisConsent { unknown, given, declined }

/// Photo settings remembered on the device: the RGPD consent to send the
/// photos (and plans) to the vision AI (EPIC-15).
class PhotoPreferences {
  const new({required this._preferences});

  final SharedPreferences _preferences;

  /// Bump the version when the consent text changes materially.
  static const consentKey = 'photo_analysis_consent_v1';

  PhotoAnalysisConsent get consent =>
      switch (_preferences.getString(consentKey)) {
        'given' => PhotoAnalysisConsent.given,
        'declined' => PhotoAnalysisConsent.declined,
        _ => PhotoAnalysisConsent.unknown,
      };

  Future<void> setConsent({required bool given}) =>
      _preferences.setString(consentKey, given ? 'given' : 'declined');
}

/// What the photo features need, provided above the router by `App`
/// (EPIC-15). Anything not given falls back to the device implementation;
/// without [preferences] the vision AI is not offered (its consent cannot
/// be remembered).
class PhotoServices {
  const new({
    this.preferences,
    this.createCamera,
    this.library,
    this.processor,
    this.tilt,
  });

  final PhotoPreferences? preferences;
  final PhotoCamera Function()? createCamera;
  final PhotoLibrary? library;
  final PhotoProcessor? processor;
  final TiltStream? tilt;

  /// Whether the vision AI can be offered.
  bool get analysisAvailable => preferences != null;

  /// Whether the seller accepted the vision AI.
  bool get analysisAccepted =>
      preferences?.consent == PhotoAnalysisConsent.given;

  PhotoCamera newCamera() => createCamera?.call() ?? PluginPhotoCamera();

  PhotoLibrary get photoLibrary => library ?? ImagePickerPhotoLibrary();

  PhotoProcessor get photoProcessor =>
      processor ?? const IsolatePhotoProcessor();

  TiltStream get tiltStream => tilt ?? accelerometerTilt;

  /// The services above [context], or the defaults when none are provided.
  // A lookup, like `Theme.of`.
  // ignore: prefer_constructors_over_static_methods
  static PhotoServices of(BuildContext context) {
    try {
      return context.read<PhotoServices>();
    } on ProviderNotFoundException {
      return const PhotoServices();
    }
  }
}
