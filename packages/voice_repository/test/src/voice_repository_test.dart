import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:voice_repository/voice_repository.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder;

class _MockAudioPlayer extends Mock implements AudioPlayer;

void main() {
  setUpAll(() {
    registerFallbackValue(const RecordConfig());
    registerFallbackValue(DeviceFileSource(''));
    registerFallbackValue(AudioContext());
    registerFallbackValue(Duration.zero);
  });

  late Directory directory;
  var now = DateTime(2026, 10, 1, 10);
  DateTime clock() => now;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('voice_test');
    now = DateTime(2026, 10, 1, 10);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  group('VoiceRecorder', () {
    late _MockAudioRecorder recorder;
    late VoiceRecorder voice;
    late String recordedPath;

    setUp(() {
      recorder = _MockAudioRecorder();
      voice = VoiceRecorder(
        createRecorder: () => recorder,
        directory: directory,
        clock: clock,
      );
      when(() => recorder.start(any(), path: any(named: 'path')))
          .thenAnswer((invocation) async {
            recordedPath = invocation.namedArguments[#path] as String;
          });
      when(() => recorder.cancel()).thenAnswer((_) async {});
      when(() => recorder.dispose()).thenAnswer((_) async {});
    });

    test('permission', () async {
      when(() => recorder.hasPermission()).thenAnswer((_) async => true);
      when(() => recorder.hasPermission(request: false))
          .thenAnswer((_) async => false);
      expect(await voice.requestPermission(), isTrue);
      expect(await voice.hasPermission(), isFalse);
    });

    test('levels', () async {
      when(() => recorder.onAmplitudeChanged(any()))
          .thenAnswer((_) => Stream.value(Amplitude(current: -20, max: -10)));
      expect(await voice.levels().first, -20);
    });

    test('records, reads and deletes the file', () async {
      await voice.start();
      verify(
        () => recorder.start(VoiceRecorder.config, path: any(named: 'path')),
      ).called(1);
      File(recordedPath).writeAsBytesSync([1, 2, 3]);
      now = now.add(const Duration(seconds: 3));
      when(() => recorder.stop()).thenAnswer((_) async => recordedPath);
      final audio = await voice.stop();
      expect(
        audio,
        RecordedAudio(
          bytes: Uint8List.fromList([1, 2, 3]),
          duration: const Duration(seconds: 3),
        ),
      );
      expect(File(recordedPath).existsSync(), isFalse);
    });

    test(
      'stop deletes the file even when the plugin returns no path',
      () async {
        await voice.start();
        File(recordedPath).writeAsBytesSync([1]);
        when(() => recorder.stop()).thenAnswer((_) async => null);
        expect(await voice.stop(), isNotNull);
        expect(File(recordedPath).existsSync(), isFalse);
      },
    );

    test('stop without a recording', () async {
      when(() => recorder.stop()).thenAnswer((_) async => null);
      expect(await voice.stop(), isNull);
      when(() => recorder.stop()).thenAnswer((_) async => '/nope.m4a');
      expect(await voice.stop(), isNull);
      await voice.start();
      expect(await voice.stop(), isNull); // missing file
      await voice.start();
      File(recordedPath).writeAsBytesSync([]);
      when(() => recorder.stop()).thenAnswer((_) async => recordedPath);
      expect(await voice.stop(), isNull); // empty file
      expect(File(recordedPath).existsSync(), isFalse);
    });

    test('cancel deletes the file; dispose', () async {
      await voice.cancel();
      verifyNever(() => recorder.cancel());
      await voice.start();
      File(recordedPath).writeAsBytesSync([1]);
      await voice.start(); // cancels the previous recording
      expect(directory.listSync(), isEmpty);
      await voice.dispose();
      verify(() => recorder.cancel()).called(2);
      verify(() => recorder.dispose()).called(1);
      final other = VoiceRecorder(createRecorder: () => recorder);
      await other.cancel();
    });
  });

  group('VoicePlayer', () {
    late _MockAudioPlayer player;
    late StreamController<void> completions;
    late VoicePlayer voice;

    setUp(() {
      player = _MockAudioPlayer();
      completions = StreamController<void>.broadcast();
      voice = VoicePlayer(
        createPlayer: () => player,
        directory: directory,
        clock: clock,
      );
      when(() => player.setAudioContext(any())).thenAnswer((_) async {});
      when(() => player.onPlayerComplete).thenAnswer((_) => completions.stream);
      when(() => player.stop()).thenAnswer((_) async {});
      when(() => player.dispose()).thenAnswer((_) async {});
    });

    tearDown(() => completions.close());

    test('plays until the end and deletes the file', () async {
      when(() => player.play(any())).thenAnswer((invocation) async {
        final source = invocation.positionalArguments.first as DeviceFileSource;
        expect(File(source.path).readAsBytesSync(), [1, 2]);
        expect(source.path, endsWith('.wav'));
        Timer.run(() => completions.add(null));
      });
      await voice.play(Uint8List.fromList([1, 2]), format: 'wav');
      expect(directory.listSync(), isEmpty);
      when(() => player.play(any())).thenAnswer((_) async {
        Timer.run(() => completions.add(null));
      });
      await voice.play(Uint8List.fromList([3]));
      verify(() => player.setAudioContext(VoicePlayer.audioContext)).called(1);
    });

    test('stop ends the playback; dispose', () async {
      await voice.stop();
      verifyNever(() => player.stop());
      final started = Completer<void>();
      when(() => player.play(any())).thenAnswer((_) async {
        started.complete();
      });
      final playing = voice.play(Uint8List.fromList([1]));
      await started.future;
      await voice.stop();
      await playing;
      verify(() => player.stop()).called(1);
      await voice.dispose();
      verify(() => player.dispose()).called(1);
      expect(VoicePlayer(createPlayer: () => player), isNotNull);
    });

    test('a failing playback still deletes the file', () async {
      when(() => player.play(any())).thenThrow(Exception('no audio'));
      await expectLater(voice.play(Uint8List.fromList([1])), throwsException);
      expect(directory.listSync(), isEmpty);
    });
  });

  group('SpeechEndDetector', () {
    Duration ms(int value) => Duration(milliseconds: value);

    test('ends after speech then silence', () {
      final detector = SpeechEndDetector();
      expect(detector.add(-60, ms(0)), isFalse); // silence before speech
      expect(detector.heardSpeech, isFalse);
      expect(detector.add(-20, ms(100)), isFalse);
      expect(detector.heardSpeech, isTrue);
      expect(detector.add(-40, ms(200)), isFalse); // quiet, not silent
      expect(detector.add(-50, ms(300)), isFalse);
      expect(detector.add(-50, ms(1000)), isFalse);
      expect(detector.add(-50, ms(1500)), isTrue);
      detector.reset();
      expect(detector.heardSpeech, isFalse);
      expect(detector.add(-60, ms(70000)), isTrue); // max duration
    });

    test('normalizedLevel', () {
      expect(normalizedLevel(-80), 0);
      expect(normalizedLevel(-30), 0.5);
      expect(normalizedLevel(5), 1);
    });
  });
}
