/// Detects the end of an utterance from the input levels (dBFS): speech
/// was heard, then the level stayed under [silenceDb] for [silence]; or
/// the turn reached [maxDuration].
class SpeechEndDetector {
  new({
    this.speechDb = -35,
    this.silenceDb = -45,
    this.silence = const Duration(milliseconds: 1200),
    this.maxDuration = const Duration(seconds: 60),
  });

  final double speechDb;
  final double silenceDb;
  final Duration silence;
  final Duration maxDuration;

  bool _heardSpeech = false;
  Duration? _silentSince;

  /// Whether speech was heard since the last [reset].
  bool get heardSpeech => _heardSpeech;

  /// Adds the level measured [elapsed] after the start; returns whether
  /// the utterance is over.
  bool add(double db, Duration elapsed) {
    if (elapsed >= maxDuration) return true;
    if (db >= speechDb) {
      _heardSpeech = true;
      _silentSince = null;
      return false;
    }
    if (!_heardSpeech) return false;
    if (db >= silenceDb) {
      _silentSince = null;
      return false;
    }
    final since = _silentSince ??= elapsed;
    return elapsed - since >= silence;
  }

  void reset() {
    _heardSpeech = false;
    _silentSince = null;
  }
}

/// A dBFS level as 0…1 for the orb and waveform (−60 dB → 0, 0 dB → 1).
double normalizedLevel(double db) => ((db + 60) / 60).clamp(0.0, 1.0);
