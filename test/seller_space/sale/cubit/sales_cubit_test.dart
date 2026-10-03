import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/cubit/sales_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';
import '../sale_helpers.dart';

void main() {
  late MockSaleRepository repository;

  setUp(() => repository = MockSaleRepository());

  group(SalesCubit, () {
    blocTest<SalesCubit, SalesState>(
      'loads the sales',
      setUp: () =>
          when(() => repository.listSales('user-id'))
              .thenAnswer((_) async => [testSale]),
      build: () => SalesCubit(repository: repository, ownerId: 'user-id'),
      act: (cubit) => cubit.load(),
      expect: () => const [
        SalesState(status: SalesStatus.loading),
        SalesState(status: SalesStatus.success, sales: [testSale]),
      ],
    );

    blocTest<SalesCubit, SalesState>(
      'keeps the list when a reload fails',
      setUp: () =>
          when(() => repository.listSales('user-id')).thenThrow(Exception()),
      build: () => SalesCubit(repository: repository, ownerId: 'user-id'),
      seed: () =>
          const SalesState(status: SalesStatus.success, sales: [testSale]),
      act: (cubit) => cubit.load(),
      expect: () => const [
        SalesState(status: SalesStatus.loading, sales: [testSale]),
        SalesState(status: SalesStatus.failure, sales: [testSale]),
      ],
      errors: () => [isA<Exception>()],
    );

    test('a closed cubit ignores late answers', () async {
      when(() => repository.listSales('user-id')).thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        return [testSale];
      });
      final cubit = SalesCubit(repository: repository, ownerId: 'user-id');
      final load = cubit.load();
      await cubit.close();
      await load;
      when(() => repository.listSales('user-id')).thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        throw Exception();
      });
      final other = SalesCubit(repository: repository, ownerId: 'user-id');
      final failing = other.load();
      await other.close();
      await failing;
    });
  });
}
