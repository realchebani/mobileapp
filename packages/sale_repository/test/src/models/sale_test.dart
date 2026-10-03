import 'package:sale_repository/sale_repository.dart';
import 'package:test/test.dart';

void main() {
  group('SaleFormula', () {
    test('rates, commission and helpers', () {
      expect(SaleFormula.essentiel.feePercent, 1);
      expect(SaleFormula.expert.feePercent, 3);
      expect(SaleFormula.essentiel.commissionOn(525000), 5250);
      expect(SaleFormula.expert.commissionOn(525000), 15750);
      expect(SaleFormula.premium.commissionOn(123456), 1230);
      expect(SaleFormula.premium.selfPublished, isTrue);
      expect(SaleFormula.expert.selfPublished, isFalse);
      expect(SaleFormula.parse('premium'), SaleFormula.premium);
      expect(SaleFormula.parse('x'), isNull);
    });
  });

  test('SaleStage', () {
    expect(SaleStage.parse('published'), SaleStage.published);
    expect(SaleStage.parse('?'), SaleStage.planChosen);
    expect(SaleStage.withdrawn.isActive, isFalse);
    expect(SaleStage.published.isActive, isTrue);
  });

  test('Sale.fromJson reads every column', () {
    final sale = Sale.fromJson(const {
      'id': 's',
      'owner_id': 'o',
      'property_id': null,
      'lot_id': 'l',
      'formula': 'expert',
      'stage': 'mandate_signed',
      'asking_price_eur': 525000,
      'listing_title': 'T',
      'listing_description': 'D',
      'description_source': 'seller',
      'ai_retouch_wanted': true,
      'home_staging_wanted': true,
      'photos_imported_at': '2026-10-03T08:00:00Z',
      'is_test': true,
      'formula_chosen_at': '2026-10-03T08:00:00Z',
      'mandate_signed_at': '2026-10-03T09:00:00Z',
      'published_at': null,
      'withdrawn_at': null,
      'created_at': '2026-10-03T08:00:00Z',
    });
    expect(sale.isLot, isTrue);
    expect(sale.isSigned, isTrue);
    expect(sale.formula, SaleFormula.expert);
    expect(sale.descriptionSource, DescriptionSource.seller);
    expect(sale.aiRetouchWanted, isTrue);
    expect(sale.photosImportedAt, DateTime.utc(2026, 10, 3, 8));
    expect(sale.props, hasLength(19));
    final minimal = Sale.fromJson(const {
      'id': 's',
      'formula': '?',
      'stage': 'plan_chosen',
      'is_test': false,
    });
    expect(minimal.formula, SaleFormula.essentiel);
    expect(minimal.isTest, isFalse);
    expect(minimal.isLot, isFalse);
    expect(minimal.isSigned, isFalse);
    expect(
      const Sale(
        id: 's',
        formula: SaleFormula.essentiel,
        stage: SaleStage.published,
      ).isSigned,
      isTrue,
    );
  });

  test('Mandate.fromJson', () {
    final mandate = Mandate.fromJson(const {
      'id': 'm',
      'sale_id': 's',
      'formula': 'expert',
      'status': 'terminated',
      'terms_version': 'test-2026-10',
      'presentation_price_eur': 525000,
      'fee_rate': 3.0,
      'duration_months': 3,
      'is_test': true,
      'document_path': 'p.pdf',
      'signed_at': '2026-10-03T08:00:00Z',
      'terminated_at': '2026-10-04T08:00:00Z',
    });
    expect(mandate.status, MandateStatus.terminated);
    expect(mandate.feeRate, 3);
    expect(mandate.props, hasLength(12));
    final other = Mandate.fromJson(const {
      'id': 'm',
      'sale_id': 's',
      'formula': '?',
      'status': '?',
      'is_test': false,
      'signed_at': '2026-10-03T08:00:00Z',
    });
    expect(other.formula, SaleFormula.essentiel);
    expect(other.status, MandateStatus.signed);
    expect(other.isTest, isFalse);
  });

  test('SaleRequest.fromJson', () {
    final request = SaleRequest.fromJson(const {
      'id': 'r',
      'sale_id': 's',
      'kind': 'diagnostics',
      'status': 'scheduled',
      'diagnostics': ['dpe', 'erp', 'unknown'],
      'preferred_slots': ['2026-10-05T08:00:00Z'],
      'scheduled_at': '2026-10-05T08:00:00Z',
      'price_eur_ttc': 250,
      'created_at': '2026-10-03T08:00:00Z',
    });
    expect(request.diagnostics, [Diagnostic.dpe, Diagnostic.risks]);
    expect(request.preferredSlots.single, DateTime.utc(2026, 10, 5, 8));
    expect(request.status.isOpen, isTrue);
    expect(request.props, hasLength(9));
    final other = SaleRequest.fromJson(const {
      'id': 'r',
      'sale_id': 's',
      'kind': '?',
      'status': '?',
    });
    expect(other.kind, SaleRequestKind.premiumSetup);
    expect(other.status, SaleRequestStatus.requested);
    expect(other.diagnostics, isEmpty);
    expect(SaleRequestStatus.done.isOpen, isFalse);
    expect(SaleRequestKind.shootingPhoto.isShooting, isTrue);
    expect(SaleRequestKind.diagnostics.isShooting, isFalse);
    expect(SaleRequestKind.premiumSetup.priceEurTtc, 299);
  });

  test('ListingPhoto json round trip', () {
    const photo = ListingPhoto(
      id: 'p',
      saleId: 's',
      storagePath: 'o/s/p.jpg',
      propertyId: 'b',
      roomId: 'r',
      sourceRoomPhotoId: 'rp',
      width: 2048,
      height: 1536,
      sizeBytes: 1000,
      sortOrder: 2,
      caption: 'Séjour',
    );
    expect(ListingPhoto.fromJson(photo.toJson()), photo);
    expect(
      ListingPhoto.fromJson(const {
        'id': 'p',
        'sale_id': 's',
        'storage_path': 'x',
      }).sortOrder,
      0,
    );
  });
}
