import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays the agent's spoken replies (mp3 or wav bytes) from a temporary
/// file (iOS cannot play from memory), in a `playAndRecord` audio session
/// shared with the recorder.
class VoicePlayer {
  new({
    AudioPlayer Function() createPlayer = AudioPlayer.new,
    Directory? directory,
    DateTime Function()? clock,
  }) : _player = createPlayer(),
       _directory = directory ?? Directory.systemTemp,
       _clock = clock ?? DateTime.now;

  final AudioPlayer _player;
  final Directory _directory;
  final DateTime Function() _clock;
  bool _configured = false;
  Completer<void>? _playing;
  StreamSubscription<void>? _completion;

  static final audioContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
  );

  /// Plays [bytes] and completes when the playback ends or is stopped.
  Future<void> play(Uint8List bytes, {String format = 'mp3'}) async {
    await stop();
    if (!_configured) {
      await _player.setAudioContext(audioContext);
      _configured = true;
    }
    final file = File(
      '${_directory.path}/reply_${_clock().microsecondsSinceEpoch}.$format',
    );
    await file.writeAsBytes(bytes, flush: true);
    final playing = _playing = Completer<void>();
    _completion = _player.onPlayerComplete.listen((_) => _finish(playing));
    try {
      await _player.play(DeviceFileSource(file.path));
      await playing.future;
    } finally {
      await _completion?.cancel();
      _completion = null;
      if (file.existsSync()) file.deleteSync();
    }
  }

  void _finish(Completer<void> playing) {
    if (!playing.isCompleted) playing.complete();
  }

  /// Stops the current reply, if any.
  Future<void> stop() async {
    final playing = _playing;
    _playing = null;
    if (playing == null || playing.isCompleted) return;
    await _player.stop();
    _finish(playing);
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
