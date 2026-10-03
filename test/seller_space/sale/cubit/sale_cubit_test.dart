import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../../fixtures.dart';
import '../sale_helpers.dart';

void main() {
  late MockSaleRepository sales;
  late MockPropertyRepository properties;
  late MockValuationRepository valuations;

  const document = PropertyDocument(
    id: 'd',
    propertyId: 'property-id',
    kind: DocumentKind.identityDocument,
    storagePath: 'p',
  );

  setUpAll(() {
    registerFallbackValue(SaleFormula.essentiel);
    registerFallbackValue(SaleRequestKind.diagnostics);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    sales = MockSaleRepository();
    properties = MockPropertyRepository();
    valuations = MockValuationRepository();
    when(() => sales.getSale('sale-id')).thenAnswer((_) async => testSale);
    when(() => sales.getMandate('sale-id')).thenAnswer((_) async => null);
    when(() => sales.getRequests('sale-id')).thenAnswer((_) async => []);
    when(() => sales.getIdentityVerifications('property-id'))
        .thenAnswer((_) async => {'owner-1': null});
    when(() => valuations.getLatestValuation('property-id'))
        .thenAnswer((_) async => testValuation);
    when(() => properties.getOwners('property-id'))
        .thenAnswer((_) async => testOwners);
    when(() => properties.getDocuments('property-id'))
        .thenAnswer((_) async => [document]);
  });

  SaleCubit build() => SaleCubit(
    saleRepository: sales,
    propertyRepository: properties,
    valuationRepository: valuations,
    saleId: 'sale-id',
    ownerId: 'user-id',
    generateId: () => 'new-id',
    userAgent: 'ios',
    appVersion: '1.0',
  );

  Future<SaleCubit> loaded({
    List<Property> props = const [certifiedProperty],
    List<PropertyLot> lots = const [],
  }) async {
    final cubit = build();
    await cubit.load(properties: props, lots: lots);
    return cubit;
  }

  group(SaleCubit, () {
    test('loads the sale and its context', () async {
      final cubit = await loaded();
      final state = cubit.state;
      expect(state.status, SaleLoadStatus.ready);
      expect(state.sale, testSale);
      expect(state.members, [certifiedProperty]);
      expect(state.mainProperty, certifiedProperty);
      expect(state.certifiedValue, 525000);
      expect(state.certifiedLow, 505000);
      expect(state.certifiedHigh, 545000);
      expect(state.basePrice, 525000);
      expect(state.owners, testOwners);
      expect(state.hasIdentityDocument, isTrue);
      expect(state.hasDiagnostics, isFalse);
      expect(state.signerFor('user-id'), testOwners.first);
      expect(state.signerFor('other'), testOwners.first);
      expect(state.isVerified(testOwners.first), isFalse);
      await cubit.close();
    });

    test('a lot sale: members of the lot, no valuation', () async {
      when(() => sales.getSale('sale-id')).thenAnswer(
        (_) async => const Sale(
          id: 'sale-id',
          lotId: 'lot',
          formula: SaleFormula.premium,
          stage: SaleStage.planChosen,
        ),
      );
      const member = Property(
        id: 'property-id',
        ownerId: 'user-id',
        lotId: 'lot',
      );
      final cubit = await loaded(
        props: [member],
        lots: const [PropertyLot(id: 'lot', ownerId: 'user-id')],
      );
      expect(cubit.state.members, [member]);
      expect(cubit.state.valuations, isEmpty);
      expect(cubit.state.certifiedValue, isNull);
      expect(cubit.state.basePrice, isNull);
      await cubit.close();
    });

    test('a sale without members (unknown lot)', () async {
      when(() => sales.getSale('sale-id')).thenAnswer(
        (_) async => const Sale(
          id: 'sale-id',
          lotId: 'gone',
          formula: SaleFormula.premium,
          stage: SaleStage.planChosen,
        ),
      );
      final cubit = await loaded();
      expect(cubit.state.members, isEmpty);
      expect(cubit.state.owners, isEmpty);
      expect(cubit.state.mainProperty, isNull);
      await cubit.close();
    });

    test('not found, failure, failure after a load keeps the sale', () async {
      when(() => sales.getSale('sale-id')).thenAnswer((_) async => null);
      var cubit = await loaded();
      expect(cubit.state.status, SaleLoadStatus.notFound);
      await cubit.close();
      when(() => sales.getSale('sale-id')).thenThrow(Exception());
      cubit = await loaded();
      expect(cubit.state.status, SaleLoadStatus.failure);
      await cubit.close();
      when(() => sales.getSale('sale-id')).thenAnswer((_) async => testSale);
      cubit = await loaded();
      when(() => sales.getSale('sale-id')).thenThrow(Exception());
      await cubit.refresh();
      expect(cubit.state.sale, testSale);
      await cubit.close();
    });

    test('a closed cubit ignores late answers', () async {
      final gate = Completer<Sale?>();
      when(() => sales.getSale('sale-id')).thenAnswer((_) => gate.future);
      var cubit = build();
      var load = cubit.load(properties: const [], lots: const []);
      await cubit.close();
      gate.complete(testSale);
      await load;
      final second = Completer<Sale?>();
      when(() => sales.getSale('sale-id')).thenAnswer((_) => second.future);
      cubit = build();
      load = cubit.load(properties: const [], lots: const []);
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      second.completeError(Exception());
      await load;
      final third = Completer<List<SaleRequest>>();
      when(() => sales.getSale('sale-id')).thenAnswer((_) async => testSale);
      when(() => sales.getRequests('sale-id')).thenAnswer((_) => third.future);
      cubit = build();
      load = cubit.load(properties: const [], lots: const []);
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      third.complete([]);
      await load;
    });

    test('signMandate signs with the drawn signature and renders', () async {
      when(
        () => sales.signTestMandate(
          ownerId: any(named: 'ownerId'),
          saleId: any(named: 'saleId'),
          mandateId: any(named: 'mandateId'),
          signaturePng: any(named: 'signaturePng'),
          accepted: any(named: 'accepted'),
          userAgent: any(named: 'userAgent'),
          appVersion: any(named: 'appVersion'),
        ),
      ).thenAnswer((_) async => 'new-id');
      when(() => sales.renderMandate('new-id')).thenThrow(Exception());
      final cubit = await loaded();
      await cubit.signMandate(signaturePng: Uint8List(1), accepted: true);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.busy, isNull);
      verify(
        () => sales.signTestMandate(
          ownerId: 'user-id',
          saleId: 'sale-id',
          mandateId: 'new-id',
          signaturePng: any(named: 'signaturePng'),
          accepted: true,
          userAgent: 'ios',
          appVersion: '1.0',
        ),
      ).called(1);
      await Future<void>.delayed(Duration.zero);
      verify(() => sales.renderMandate('new-id')).called(1);
      await cubit.close();
    });

    test('a failed action keeps its failure; unknown errors too', () async {
      when(() => sales.publish('sale-id'))
          .thenThrow(const SaleFailure(SaleFailureReason.mandateNotSigned));
      final cubit = await loaded();
      await cubit.publish();
      expect(cubit.state.failure?.reason, SaleFailureReason.mandateNotSigned);
      when(() => sales.unpublish('sale-id')).thenThrow(Exception());
      await cubit.unpublish();
      expect(cubit.state.failure?.reason, SaleFailureReason.unknown);
      await cubit.close();
    });

    test('a running action ignores another one', () async {
      final gate = Completer<void>();
      when(() => sales.publish('sale-id')).thenAnswer((_) => gate.future);
      final cubit = await loaded();
      final first = cubit.publish();
      await cubit.withdraw();
      verifyNever(() => sales.withdraw(any(), reason: any(named: 'reason')));
      gate.complete();
      await first;
      await cubit.close();
    });

    test('formula, requests, listing, withdraw', () async {
      when(
        () => sales.chooseFormula(
          saleId: any(named: 'saleId'),
          formula: any(named: 'formula'),
          propertyId: any(named: 'propertyId'),
          lotId: any(named: 'lotId'),
        ),
      ).thenAnswer((_) async => 'sale-id');
      const request = SaleRequest(
        id: 'r',
        saleId: 'sale-id',
        kind: SaleRequestKind.diagnostics,
      );
      when(
        () => sales.requestService(
          requestId: any(named: 'requestId'),
          saleId: any(named: 'saleId'),
          kind: any(named: 'kind'),
          diagnostics: any(named: 'diagnostics'),
          preferredSlots: any(named: 'preferredSlots'),
        ),
      ).thenAnswer((_) async => request);
      when(() => sales.cancelRequest('r')).thenAnswer((_) async {});
      when(() => sales.updateSale('sale-id', any()))
          .thenAnswer((_) async => testSale);
      when(() => sales.withdraw('sale-id', reason: 'r'))
          .thenAnswer((_) async {});
      final cubit = await loaded();
      await cubit.changeFormula(SaleFormula.premium);
      verify(
        () => sales.chooseFormula(
          saleId: 'sale-id',
          formula: SaleFormula.premium,
          propertyId: 'property-id',
        ),
      ).called(1);
      await cubit.requestService(
        SaleRequestKind.diagnostics,
        diagnostics: [Diagnostic.dpe],
      );
      verify(
        () => sales.requestService(
          requestId: 'new-id',
          saleId: 'sale-id',
          kind: SaleRequestKind.diagnostics,
          diagnostics: [Diagnostic.dpe],
        ),
      ).called(1);
      await cubit.cancelRequest(request);
      await cubit.updateListing({'listing_title': 'T'});
      await cubit.withdraw(reason: 'r');
      verify(() => sales.withdraw('sale-id', reason: 'r')).called(1);
      expect(cubit.state.failure, isNull);
      await cubit.close();
    });

    test('openMandate renders when needed and signs the URL', () async {
      when(() => sales.renderMandate('mandate-id'))
          .thenAnswer((_) async => 'path.pdf');
      when(() => sales.mandateUrl(any())).thenAnswer((_) async => 'https://u');
      final cubit = await loaded();
      await cubit.openMandate();
      verifyNever(() => sales.mandateUrl(any()));
      when(() => sales.getMandate('sale-id')).thenAnswer(
        (_) async => Mandate(
          id: 'mandate-id',
          saleId: 'sale-id',
          formula: SaleFormula.essentiel,
          signedAt: DateTime(2026),
        ),
      );
      await cubit.refresh();
      await cubit.openMandate();
      expect(cubit.state.mandateUrl, 'https://u');
      verify(() => sales.mandateUrl('path.pdf')).called(1);
      when(() => sales.getMandate('sale-id'))
          .thenAnswer((_) async => testMandate);
      await cubit.refresh();
      await cubit.openMandate();
      verify(() => sales.mandateUrl(testMandate.documentPath!)).called(1);
      await cubit.close();
    });

    test('state helpers', () {
      final state = saleState(
        requests: const [
          SaleRequest(
            id: 'a',
            saleId: 's',
            kind: SaleRequestKind.shootingPhotoVideo,
          ),
          SaleRequest(
            id: 'b',
            saleId: 's',
            kind: SaleRequestKind.shootingPhoto,
            status: SaleRequestStatus.cancelled,
          ),
        ],
        verified: true,
        documents: const {DocumentKind.diagnostics},
        mandate: testMandate,
      );
      expect(state.openShooting?.id, 'a');
      expect(state.openRequest(SaleRequestKind.diagnostics), isNull);
      expect(state.isVerified(testOwners.first), isTrue);
      expect(state.hasDiagnostics, isTrue);
      expect(state.hasIdentityDocument, isFalse);
      expect(state.copyWith(clearMandate: true).mandate, isNull);
      expect(state.copyWith(busy: SaleAction.sign).busy, SaleAction.sign);
      expect(state.props, hasLength(12));
    });
  });
}
