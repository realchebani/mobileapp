import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/models/sale_entry.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

void main() {
  Property property(
    String id, {
    PropertyStatus status = PropertyStatus.certified,
    String? lotId,
    int day = 1,
  }) => Property(
    id: id,
    ownerId: 'user-id',
    status: status,
    lotId: lotId,
    createdAt: DateTime(2026, 10, day),
  );

  const together = PropertyLot(id: 'lot', ownerId: 'user-id');
  const separately = PropertyLot(
    id: 'lot',
    ownerId: 'user-id',
    saleMode: LotSaleMode.togetherOrSeparately,
    mainPropertyId: 'b',
  );
  Sale sale({String? propertyId, String? lotId}) => Sale(
    id: 's',
    propertyId: propertyId,
    lotId: lotId,
    formula: SaleFormula.essentiel,
    stage: SaleStage.planChosen,
  );

  group(SaleEntry, () {
    test('a certified property on its own can be sold', () {
      final p = property('a');
      final entry = SaleEntry.of(
        property: p,
        properties: [p],
        lots: const [],
        sales: const [],
      );
      expect(entry.targets, [SaleTarget.forProperty(p)]);
      expect(entry.targets.single.propertyId, 'a');
      expect(entry.targets.single.isLot, isFalse);
      expect(entry.activeSale, isNull);
      expect(entry.lot, isNull);
      expect(entry, SaleEntry(targets: [SaleTarget.forProperty(p)]));
    });

    test('a draft cannot', () {
      final p = property('a', status: PropertyStatus.draft);
      expect(
        SaleEntry.of(
          property: p,
          properties: [p],
          lots: const [],
          sales: const [],
        ).targets,
        isEmpty,
      );
    });

    test('a lot sold together: only the lot, once its main is certified', () {
      final a = property('a', lotId: 'lot');
      final b = property(
        'b',
        lotId: 'lot',
        status: PropertyStatus.draft,
        day: 2,
      );
      final entry = SaleEntry.of(
        property: a,
        properties: [b, a],
        lots: const [together],
        sales: const [],
      );
      final target = entry.targets.single;
      expect(target.isLot, isTrue);
      expect(target.lotId, 'lot');
      expect(target.members, [a, b]);
      expect(target.certifiedMembers, [a]);
      expect(entry.lot, together);
      // Main (oldest) not certified: nothing.
      final draftMain = property(
        'a',
        lotId: 'lot',
        status: PropertyStatus.draft,
      );
      expect(
        SaleEntry.of(
          property: draftMain,
          properties: [draftMain, b],
          lots: const [together],
          sales: const [],
        ).targets,
        isEmpty,
      );
    });

    test('a lot sold together or separately: both', () {
      final a = property('a', lotId: 'lot');
      final b = property('b', lotId: 'lot', day: 2);
      final entry = SaleEntry.of(
        property: a,
        properties: [a, b],
        lots: const [separately],
        sales: const [],
      );
      expect(entry.targets, hasLength(2));
      // b is the chosen main property.
      expect(entry.targets.last.members.first, b);
    });

    test('active sales: own, through the lot; members block the lot', () {
      final a = property('a', lotId: 'lot');
      final b = property('b', lotId: 'lot', day: 2);
      final own = sale(propertyId: 'a');
      expect(
        SaleEntry.of(
          property: a,
          properties: [a, b],
          lots: const [separately],
          sales: [own],
        ).activeSale,
        own,
      );
      final ofLot = sale(lotId: 'lot');
      expect(
        SaleEntry.of(
          property: a,
          properties: [a, b],
          lots: const [separately],
          sales: [ofLot],
        ).activeSale,
        ofLot,
      );
      // b on sale on its own: a can be sold, not the lot.
      final entry = SaleEntry.of(
        property: a,
        properties: [a, b],
        lots: const [separately],
        sales: [sale(propertyId: 'b')],
      );
      expect(entry.targets.single.isLot, isFalse);
    });

    test('lot members: empty lot, no date', () {
      expect(SaleEntry.lotMembers(together, const []), isEmpty);
      expect(
        SaleEntry.lotTarget(together, properties: const [], sales: const []),
        isNull,
      );
      const undated = Property(id: 'x', ownerId: 'u', lotId: 'lot');
      expect(SaleEntry.lotMembers(together, const [undated]), [undated]);
      // Same date: by id, like the database.
      const b = Property(id: 'b', ownerId: 'u', lotId: 'lot');
      const a = Property(id: 'a', ownerId: 'u', lotId: 'lot');
      expect(SaleEntry.lotMembers(together, const [b, a]), [a, b]);
    });

    test('target of an existing sale', () {
      final a = property('a');
      expect(SaleTarget.forSale(sale(propertyId: 'a'), [a]).propertyId, 'a');
      expect(SaleTarget.forSale(sale(lotId: 'lot'), [a]).lotId, 'lot');
    });
  });
}
