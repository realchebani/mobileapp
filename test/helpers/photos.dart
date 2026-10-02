import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';
import 'package:property_repository/property_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A camera showing a grey box and taking [picture].
class FakePhotoCamera implements PhotoCamera {
  new({this.picture, this.initializeError, this.takeError});

  final Uint8List? picture;
  final Object? initializeError;
  final Object? takeError;
  bool disposed = false;
  int taken = 0;

  @override
  Future<void> initialize() async {
    if (initializeError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  double get aspectRatio => 3 / 4;

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF808080));

  @override
  Future<Uint8List> takePicture() async {
    if (takeError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    taken++;
    return picture ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// A photo library giving [photos] (or throwing [error]).
class FakePhotoLibrary implements PhotoLibrary {
  new({this.photos = const [], this.error});

  final List<Uint8List> photos;
  final Object? error;
  final List<int> limits = [];

  @override
  Future<List<Uint8List>> pick({required int limit}) async {
    limits.add(limit);
    if (error case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return photos;
  }
}

/// A processor returning the bytes as they are, with [issues] (or
/// throwing [error]); [gate] holds the result until completed.
class FakePhotoProcessor implements PhotoProcessor {
  new({this.issues = const [], this.error, this.gate});

  final List<PhotoQualityIssue> issues;
  final Object? error;
  final Completer<void>? gate;
  final List<double?> tilts = [];

  @override
  Future<ProcessedPhoto> process(Uint8List bytes, {double? tiltDegrees}) async {
    tilts.add(tiltDegrees);
    await gate?.future;
    if (error case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return ProcessedPhoto(
      bytes: bytes,
      width: 4,
      height: 3,
      quality: PhotoQuality(brightness: 120, sharpness: 80, issues: issues),
    );
  }

  @override
  Future<Uint8List> stripMetadata(Uint8List bytes) async =>
      stripImageMetadata(bytes);
}

/// A processed photo of [bytes].
ProcessedPhoto processedPhoto([
  List<int> bytes = const [1, 2, 3],
  List<PhotoQualityIssue> issues = const [],
]) => ProcessedPhoto(
  bytes: Uint8List.fromList(bytes),
  width: 4,
  height: 3,
  quality: PhotoQuality(issues: issues),
);

/// Photo services backed by fakes, with the vision AI [consent].
Future<PhotoServices> testPhotoServices({
  PhotoAnalysisConsent consent = PhotoAnalysisConsent.unknown,
  PhotoCamera? camera,
  PhotoLibrary? library,
  PhotoProcessor? processor,
  TiltStream? tilt,
  bool withPreferences = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (consent != PhotoAnalysisConsent.unknown)
      PhotoPreferences.consentKey: consent.name,
  });
  final preferences = await SharedPreferences.getInstance();
  return PhotoServices(
    preferences: withPreferences
        ? PhotoPreferences(preferences: preferences)
        : null,
    createCamera: () => camera ?? FakePhotoCamera(),
    library: library ?? FakePhotoLibrary(),
    processor: processor ?? FakePhotoProcessor(),
    tilt: tilt ?? Stream<double>.empty,
  );
}

/// A stored photo of the room `r1` of `property-id`.
RoomPhoto testRoomPhoto(
  String id, {
  int sortOrder = 0,
  RoomPhotoAnalysis? analysis,
  PhotoQuality? quality,
  String roomId = 'r1',
}) => RoomPhoto(
  id: id,
  propertyId: 'property-id',
  roomId: roomId,
  storagePath: 'user-id/property-id/photos/$roomId/$id.jpg',
  width: 4,
  height: 3,
  sortOrder: sortOrder,
  analysis: analysis,
  quality: quality,
);
