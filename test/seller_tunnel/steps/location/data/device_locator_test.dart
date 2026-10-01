import 'package:flutter_test/flutter_test.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mocktail/mocktail.dart';

class _MockGeolocatorPlatform extends Mock implements GeolocatorPlatform;

void main() {
  late GeolocatorPlatform platform;
  late DeviceLocator locator;

  final position = Position(
    latitude: 45.7,
    longitude: 4.7,
    timestamp: DateTime(2026),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Matcher failsWith(DeviceLocationError reason) => throwsA(
    isA<DeviceLocationException>().having((e) => e.reason, 'reason', reason),
  );

  setUp(() {
    platform = _MockGeolocatorPlatform();
    locator = DeviceLocator(platform: platform);
    when(platform.isLocationServiceEnabled).thenAnswer((_) async => true);
    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.whileInUse);
    when(
      () => platform.getCurrentPosition(
        locationSettings: any(named: 'locationSettings'),
      ),
    ).thenAnswer((_) async => position);
  });

  test('uses the plugin platform by default', () {
    expect(DeviceLocator(), isA<DeviceLocator>());
  });

  test('returns the position of the device', () async {
    expect(await locator.currentPosition(), const GeoPoint(45.7, 4.7));
    verifyNever(platform.requestPermission);
  });

  test('asks for the permission when not decided yet', () async {
    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.denied);
    when(platform.requestPermission)
        .thenAnswer((_) async => LocationPermission.always);
    expect(await locator.currentPosition(), const GeoPoint(45.7, 4.7));
  });

  test('fails when location services are off', () {
    when(platform.isLocationServiceEnabled).thenAnswer((_) async => false);
    expect(
      locator.currentPosition(),
      failsWith(DeviceLocationError.serviceDisabled),
    );
  });

  test('fails when the permission is refused', () {
    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.deniedForever);
    expect(
      locator.currentPosition(),
      failsWith(DeviceLocationError.permissionDenied),
    );
  });

  test('maps the plugin errors', () async {
    Future<void> expectError(Object error, DeviceLocationError reason) async {
      when(
        () => platform.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenThrow(error);
      await expectLater(locator.currentPosition(), failsWith(reason));
    }

    await expectError(
      const LocationServiceDisabledException(),
      DeviceLocationError.serviceDisabled,
    );
    await expectError(
      const PermissionDeniedException('denied'),
      DeviceLocationError.permissionDenied,
    );
    await expectError(StateError('timeout'), DeviceLocationError.unavailable);
  });

  test('DeviceLocationException describes its cause', () {
    expect(
      const DeviceLocationException(
        DeviceLocationError.unavailable,
        'x',
      ).toString(),
      'DeviceLocationException(DeviceLocationError.unavailable, x)',
    );
  });
}
