import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Depuis un autre bien" (V7, EPIC-13): the documents of [kind] of the
/// seller's other properties (e.g. a title deed covering the house and the
/// garage); returns the one chosen, or null.
Future<PropertyDocument?> showReuseDocumentSheet(
  BuildContext context, {
  required DocumentKind kind,
}) {
  final repository = context.read<PropertyRepository>();
  final currentId = context.read<SellerTunnelCubit>().state.property!.id;
  final others = [
    for (final property
        in context.read<SellerPropertiesCubit>().state.properties)
      if (property.id != currentId) property,
  ];
  return showModalBottomSheet<PropertyDocument>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => ReuseDocumentSheet(
      kind: kind,
      properties: others,
      load: repository.getDocuments,
    ),
  );
}

/// Content of [showReuseDocumentSheet].
class ReuseDocumentSheet extends StatefulWidget {
  const new({
    required this.kind,
    required this.properties,
    required this.load,
    super.key,
  });

  final DocumentKind kind;

  /// The other properties of the seller.
  final List<Property> properties;

  /// Loads the documents of a property.
  final Future<List<PropertyDocument>> Function(String propertyId) load;

  @override
  State<ReuseDocumentSheet> createState() => _ReuseDocumentSheetState();
}

class _ReuseDocumentSheetState extends State<ReuseDocumentSheet> {
  late final Future<List<(Property, PropertyDocument)>> _documents = _fetch();

  Future<List<(Property, PropertyDocument)>> _fetch() async {
    final lists = await [
      for (final property in widget.properties) widget.load(property.id),
    ].wait;
    return [
      for (final (index, property) in widget.properties.indexed)
        for (final document in lists[index])
          if (document.kind == widget.kind &&
              document.status != DocumentStatus.rejected)
            (property, document),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RealestySpacing.gutter,
        0,
        RealestySpacing.gutter,
        RealestySpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
            child: Semantics(
              header: true,
              child: Text(
                l10n.documentsReuseTitle,
                style: RealestyTextStyles.title2,
              ),
            ),
          ),
          Flexible(
            child: FutureBuilder(
              future: _documents,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return InlineBanner(message: l10n.documentsReuseLoadError);
                }
                final documents = snapshot.data;
                if (documents == null) {
                  return Padding(
                    padding: const EdgeInsets.all(RealestySpacing.lg),
                    child: Center(
                      child: CircularProgressIndicator(color: c.vertTexte),
                    ),
                  );
                }
                if (documents.isEmpty) {
                  return Text(
                    l10n.documentsReuseEmpty,
                    style: RealestyTextStyles.body.copyWith(
                      color: c.texteDiscret,
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (index, (property, document))
                        in documents.indexed)
                      RealestyListItem(
                        title:
                            document.fileName ??
                            l10n.documentKind(document.kind),
                        subtitle: propertyShortLabel(l10n, property),
                        leadingIcon: RealestyIcons.file,
                        showDivider: index < documents.length - 1,
                        onTap: () => Navigator.of(context).pop(document),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
