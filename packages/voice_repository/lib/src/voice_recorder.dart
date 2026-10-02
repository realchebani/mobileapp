import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:record/record.dart';

/// An utterance recorded by [VoiceRecorder] (AAC in an `m4a` file, read
/// in memory; the file is deleted).
final class RecordedAudio extends Equatable {
  const new({required this.bytes, required this.duration, this.format = 'm4a'});

  final Uint8List bytes;
  final Duration duration;
  final String format;

  @override
  List<Object?> get props => [bytes, duration, format];
}

/// Microphone recording for the voice agent: AAC-LC 16 kHz mono 32 kbps
/// (≈ 4 KB/s), input level for the UI and the end-of-speech detection.
class VoiceRecorder {
  new({
    AudioRecorder Function() createRecorder = AudioRecorder.new,
    Directory? directory,
    DateTime Function()? clock,
    this._levelInterval = const Duration(milliseconds: 80),
  }) : _recorder = createRecorder(),
       _directory = directory ?? Directory.systemTemp,
       _clock = clock ?? DateTime.now;

  final AudioRecorder _recorder;
  final Directory _directory;
  final DateTime Function() _clock;
  final Duration _levelInterval;

  /// AAC-LC (the default encoder) in an m4a container.
  static const config = RecordConfig(
    sampleRate: 16000,
    numChannels: 1,
    bitRate: 32000,
  );

  DateTime? _startedAt;
  String? _path;

  /// Whether the microphone may be used (asks the first time).
  Future<bool> requestPermission() => _recorder.hasPermission();

  /// Whether the microphone may be used, without asking.
  Future<bool> hasPermission() => _recorder.hasPermission(request: false);

  /// Input level in dBFS (−160…0), every 80 ms while recording.
  Stream<double> levels() => _recorder
      .onAmplitudeChanged(_levelInterval)
      .map((amplitude) => amplitude.current);

  /// Starts a new recording (stops any previous one).
  Future<void> start() async {
    await cancel();
    final path =
        '${_directory.path}/voice_${_clock().microsecondsSinceEpoch}.m4a';
    await _recorder.start(config, path: path);
    _path = path;
    _startedAt = _clock();
  }

  /// Stops and returns the recording, or null when nothing was recorded.
  /// The temporary file is deleted.
  Future<RecordedAudio?> stop() async {
    final startedAt = _startedAt;
    final expected = _path;
    _startedAt = null;
    _path = null;
    final path = await _recorder.stop() ?? expected;
    if (path == null) return null;
    final file = File(path);
    try {
      if (startedAt == null || !file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return RecordedAudio(
        bytes: bytes,
        duration: _clock().difference(startedAt),
      );
    } finally {
      // Never left on the device, whatever happened.
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Stops without keeping anything.
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    _startedAt = null;
    if (path == null) return;
    await _recorder.cancel();
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
