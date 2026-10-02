import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  late PropertyRepository repository;

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.getProperty(any())).thenAnswer(
      (invocation) async => Property(
        id: invocation.positionalArguments.first as String,
        ownerId: 'u',
      ),
    );
    when(() => repository.getOwners(any())).thenAnswer((_) async => []);
    when(() => repository.getParcels(any())).thenAnswer((_) async => []);
    when(() => repository.getPreviousEstimates(any()))
        .thenAnswer((_) async => []);
    when(() => repository.getRooms(any())).thenAnswer((_) async => []);
    when(() => repository.getLifestyleItems(any())).thenAnswer((_) async => []);
    when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
  });

  group(SellerTunnelCubits, () {
    test('creates one loaded cubit per property and reports changes', () async {
      final changed = <Property>[];
      final cubits = SellerTunnelCubits(
        propertyRepository: repository,
        onPropertyChanged: changed.add,
      );
      final a = cubits.of('a');
      expect(cubits.of('a'), same(a));
      final b = cubits.of('b');
      expect(b, isNot(same(a)));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(a.state.property?.id, 'a');
      expect(changed.map((p) => p.id), containsAll(['a', 'b']));
      await cubits.forget('a');
      expect(a.isClosed, isTrue);
      expect(cubits.of('a'), isNot(same(a)));
      await cubits.close();
      expect(b.isClosed, isTrue);
    });

    test('works without a change callback', () async {
      final cubits = SellerTunnelCubits(propertyRepository: repository);
      final a = cubits.of('a');
      await cubits.close();
      expect(a.isClosed, isTrue);
    });
  });

  test('records the error of a property that cannot be found', () async {
    when(() => repository.getProperty(any()))
        .thenAnswer((_) async => throw const PropertyNotFoundFailure('x'));
    final cubit = SellerTunnelCubit(
      propertyRepository: repository,
      propertyId: 'x',
    );
    await cubit.load();
    expect(
      cubit.state,
      const SellerTunnelState(
        status: SellerTunnelStatus.failure,
        notFound: true,
      ),
    );
    await cubit.close();
  });
}
