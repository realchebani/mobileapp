import 'package:geo_repository/geo_repository.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Why the position of the device could not be obtained.
enum DeviceLocationError {
  /// Location services are turned off.
  serviceDisabled,

  /// The user refused access to the position.
  permissionDenied,

  /// Any other error (no fix, timeout…).
  unavailable,
}

/// {@template device_location_exception}
/// Thrown by [DeviceLocator.currentPosition].
/// {@endtemplate}
class DeviceLocationException implements Exception {
  /// {@macro device_location_exception}
  const new(this.reason, [this.error]);

  final DeviceLocationError reason;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => 'DeviceLocationException($reason, $error)';
}

/// {@template device_locator}
/// The GPS position of the device ("Me géolocaliser"), asking for the
/// "when in use" permission if needed.
///
/// Uses the geolocator platform implementations (iOS / Android) directly:
/// the `geolocator` app-facing package would also pull its Linux
/// implementation, whose dependencies are MPL-licensed.
/// {@endtemplate}
class DeviceLocator {
  /// {@macro device_locator}
  new({GeolocatorPlatform? platform})
    : _platform = platform ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _platform;

  /// Delay after which getting a position fails.
  static const timeLimit = Duration(seconds: 15);

  /// The current position of the device.
  ///
  /// Throws a [DeviceLocationException].
  Future<GeoPoint> currentPosition() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        throw const DeviceLocationException(
          DeviceLocationError.serviceDisabled,
        );
      }
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const DeviceLocationException(
          DeviceLocationError.permissionDenied,
        );
      }
      final position = await _platform.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: timeLimit),
      );
      return GeoPoint(position.latitude, position.longitude);
    } on DeviceLocationException {
      rethrow;
    } on LocationServiceDisabledException catch (error) {
      throw DeviceLocationException(DeviceLocationError.serviceDisabled, error);
    } on PermissionDeniedException catch (error) {
      throw DeviceLocationException(
        DeviceLocationError.permissionDenied,
        error,
      );
    } on Object catch (error) {
      throw DeviceLocationException(DeviceLocationError.unavailable, error);
    }
  }
}
