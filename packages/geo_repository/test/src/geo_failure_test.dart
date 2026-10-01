import 'package:geo_repository/geo_repository.dart';
import 'package:test/test.dart';

void main() {
  test('failures describe their cause', () {
    expect(
      const GeoNetworkFailure('offline').toString(),
      'GeoNetworkFailure(offline)',
    );
    expect(const GeoNotFoundFailure().toString(), 'GeoNotFoundFailure(null)');
    expect(const GeoUnknownFailure('bad').toString(), 'GeoUnknownFailure(bad)');
    expect(const GeoUnknownFailure('bad').error, 'bad');
  });
}
