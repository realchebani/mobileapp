import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_space/vault/models/vault_rubric.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/document_scan_page.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/reuse_document_sheet.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// How a document is added.
enum VaultSource {
  /// The document scanner (several pages → one PDF).
  scan,

  /// A PDF or image of the files.
  files,

  /// An image of the photo library.
  photos,

  /// A copy of a document of another property of the seller.
  otherProperty,
}

/// Shows [options] in a titled sheet; returns the chosen value.
Future<T?> showVaultOptions<T>(
  BuildContext context, {
  required String title,
  required List<DocumentOption<T>> options,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => DocumentOptionSheet<T>(title: title, options: options),
);

/// "Ajouter un document" of the vault: the property (in a lot), the kind
/// (within [rubric] when given), the owner of an identity document, then
/// the source; [preset] skips the choices (a missing document's
/// "Scanner").
Future<void> addVaultDocument(
  BuildContext context, {
  VaultRubric? rubric,
  VaultAddTarget? preset,
  VaultSource? source,
}) async {
  final l10n = context.l10n;
  final cubit = context.read<VaultCubit>();
  var target = preset;
  if (target == null) {
    final properties = cubit.state.properties;
    if (properties.isEmpty) return;
    final property = properties.length == 1
        ? properties.single
        : await showVaultOptions<Property>(
            context,
            title: l10n.vaultAddPropertyTitle,
            options: [
              for (final property in properties)
                DocumentOption(
                  value: property,
                  title: propertyShortLabel(l10n, property),
                  icon: propertyTypeIcon(property.propertyType),
                ),
            ],
          );
    if (property == null || !context.mounted) return;
    final kinds = [
      for (final r in VaultRubric.values)
        if (rubric == null || r == rubric) ...r.kinds,
    ];
    final kind = kinds.length == 1
        ? kinds.single
        : await showVaultOptions<DocumentKind>(
            context,
            title: l10n.vaultAddKindTitle,
            options: [
              for (final kind in kinds)
                DocumentOption(
                  value: kind,
                  title: l10n.vaultKind(kind),
                  subtitle: l10n.vaultRubric(VaultRubric.of(kind)),
                  icon: VaultLabels.rubricIcon(VaultRubric.of(kind)),
                ),
            ],
          );
    if (kind == null || !context.mounted) return;
    String? ownerRef;
    final owners = cubit.state.owners[property.id] ?? const [];
    if (kind == DocumentKind.identityDocument && owners.length > 1) {
      final owner = await showVaultOptions<PropertyOwner>(
        context,
        title: l10n.vaultAddOwnerTitle,
        options: [
          for (final owner in owners)
            DocumentOption(
              value: owner,
              title: '${owner.firstName} ${owner.lastName}'.trim(),
              icon: RealestyIcons.user,
            ),
        ],
      );
      if (owner == null || !context.mounted) return;
      ownerRef = owner.id;
    } else if (kind == DocumentKind.identityDocument && owners.length == 1) {
      ownerRef = owners.single.id;
    }
    target = VaultAddTarget(
      propertyId: property.id,
      kind: kind,
      ownerRef: ownerRef,
    );
  }
  final others = [
    for (final property
        in context.read<SellerPropertiesCubit?>()?.state.properties ??
            const <Property>[])
      if (property.id != target.propertyId) property,
  ];
  final chosen =
      source ??
      await showVaultOptions<VaultSource>(
        context,
        title: l10n.vaultAddSourceTitle,
        options: [
          DocumentOption(
            value: VaultSource.scan,
            title: l10n.documentsScan,
            subtitle: l10n.vaultSourceScanSubtitle,
            icon: RealestyIcons.scan,
          ),
          DocumentOption(
            value: VaultSource.files,
            title: l10n.documentsSourceFiles,
            subtitle: l10n.documentsSourceFilesSubtitle,
            icon: RealestyIcons.file,
          ),
          DocumentOption(
            value: VaultSource.photos,
            title: l10n.documentsSourcePhotos,
            subtitle: l10n.documentsSourcePhotosSubtitle,
            icon: RealestyIcons.camera,
          ),
          if (others.isNotEmpty)
            DocumentOption(
              value: VaultSource.otherProperty,
              title: l10n.documentsReuseOption,
              subtitle: l10n.documentsReuseOptionSubtitle,
              icon: RealestyIcons.swap,
            ),
        ],
      );
  if (chosen == null || !context.mounted) return;
  if (chosen == VaultSource.otherProperty) {
    final repository = context.read<PropertyRepository>();
    final kind = target.kind;
    final document = await showModalBottomSheet<PropertyDocument>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ReuseDocumentSheet(
        kind: kind,
        properties: others,
        load: repository.getDocuments,
      ),
    );
    if (document != null) await cubit.reuse(target, document);
    return;
  }
  await _addFrom(context, chosen, target);
}

/// "Remplacer" [document] (rejected, or an addition not verified yet): a
/// new file of the same kind and owner.
Future<void> replaceVaultDocument(
  BuildContext context,
  PropertyDocument document,
) async {
  final l10n = context.l10n;
  final source = await showVaultOptions<VaultSource>(
    context,
    title: l10n.vaultReplaceTitle,
    options: [
      DocumentOption(
        value: VaultSource.scan,
        title: l10n.documentsScan,
        subtitle: l10n.vaultSourceScanSubtitle,
        icon: RealestyIcons.scan,
      ),
      DocumentOption(
        value: VaultSource.files,
        title: l10n.documentsSourceFiles,
        subtitle: l10n.documentsSourceFilesSubtitle,
        icon: RealestyIcons.file,
      ),
      DocumentOption(
        value: VaultSource.photos,
        title: l10n.documentsSourcePhotos,
        subtitle: l10n.documentsSourcePhotosSubtitle,
        icon: RealestyIcons.camera,
      ),
    ],
  );
  if (source == null || !context.mounted) return;
  await _addFrom(
    context,
    source,
    VaultAddTarget(
      propertyId: document.propertyId,
      kind: document.kind,
      ownerRef: document.ownerRef,
    ),
    replacing: document,
  );
}

/// Adds a document to [target] from [source] (a scan, the files or the
/// photo library).
Future<void> _addFrom(
  BuildContext context,
  VaultSource source,
  VaultAddTarget target, {
  PropertyDocument? replacing,
}) async {
  final cubit = context.read<VaultCubit>();
  switch (source) {
    case VaultSource.scan:
      final scan = await showDocumentScan(context, kind: target.kind);
      if (scan != null) await cubit.add(target, scan, replacing: replacing);
    case VaultSource.files:
      await cubit.pickAndAdd(
        target,
        DocumentSource.files,
        replacing: replacing,
      );
    case VaultSource.photos || VaultSource.otherProperty:
      await cubit.pickAndAdd(
        target,
        DocumentSource.photos,
        replacing: replacing,
      );
  }
}
