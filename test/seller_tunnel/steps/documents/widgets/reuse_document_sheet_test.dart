import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/reuse_document_sheet.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

void main() {
  testWidgets('tells when the documents could not be loaded', (tester) async {
    await tester.pumpApp(
      ReuseDocumentSheet(
        kind: DocumentKind.titleDeed,
        properties: const [testProperty],
        load: (_) async => throw const PropertyLoadFailure(),
      ),
    );
    await tester.pump();
    expect(
      find.text('Les documents de vos autres biens n’ont pas pu être chargés.'),
      findsOneWidget,
    );
  });

  testWidgets('names a document without file name by its kind', (tester) async {
    await tester.pumpApp(
      ReuseDocumentSheet(
        kind: DocumentKind.titleDeed,
        properties: const [testProperty],
        load: (_) async => const [
          PropertyDocument(
            id: 'd',
            propertyId: 'property-id',
            kind: DocumentKind.titleDeed,
            storagePath: 'x',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.text('Titre de propriété'), findsOneWidget);
  });
}
