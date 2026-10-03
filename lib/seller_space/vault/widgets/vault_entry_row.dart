import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_actions.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_document_sheet.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// The owner [document] belongs to (identity documents), among [state]'s.
PropertyOwner? vaultOwnerOf(VaultState state, PropertyDocument document) {
  final ref = document.ownerRef;
  if (ref == null) return null;
  for (final owner
      in state.owners[document.propertyId] ?? const <PropertyOwner>[]) {
    if (owner.id == ref) return owner;
  }
  return null;
}

/// A row of the vault: a document (opens its detail), a missing required
/// document ("Scanner") or the certified valuation.
class VaultEntryRow extends StatelessWidget {
  const new({
    required this.entry,
    this.showProperty = false,
    this.showDivider = true,
    super.key,
  });

  final VaultEntry entry;

  /// Prefixes the title with the property (lot view, search).
  final bool showProperty;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<VaultCubit>().state;
    String titled(String title) => showProperty
        ? l10n.vaultPropertyPrefix(
            propertyShortLabel(l10n, entry.property),
            title,
          )
        : title;
    switch (entry) {
      case final VaultDocumentEntry entry:
        final document = entry.document;
        final busy = state.busyDocumentIds.contains(document.id);
        final details = l10n.vaultDocumentDetails(document);
        return RealestyListItem(
          title: titled(
            l10n.vaultDocumentTitle(
              document,
              owner: vaultOwnerOf(state, document),
            ),
          ),
          subtitle: [
            if (details.isNotEmpty) details,
            if (document.addedAfterSubmission) l10n.vaultAddedAfterSending,
            if (entry.canShare) l10n.vaultVisibility(document.visibility),
          ].join('\n'),
          leadingIcon: document.mimeType == 'application/pdf'
              ? RealestyIcons.file
              : RealestyIcons.camera,
          tone: switch (entry.status) {
            VaultDocumentStatus.toReplace => RealestyListTileTone.error,
            VaultDocumentStatus.verified ||
            VaultDocumentStatus.analyzed => RealestyListTileTone.success,
            VaultDocumentStatus.received ||
            VaultDocumentStatus.analyzing => RealestyListTileTone.neutral,
          },
          trailing: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : l10n.vaultStatusBadge(entry.status),
          showDivider: showDivider,
          onTap: () => showVaultDocumentSheet(context, document.id),
        );
      case final VaultMissingEntry entry:
        final owner = entry.owner;
        final kind = l10n.vaultKind(entry.kind);
        final name = owner == null
            ? ''
            : '${owner.firstName} ${owner.lastName}'.trim();
        return RealestyListItem(
          title: titled(
            name.isEmpty ? kind : l10n.vaultOwnerDocument(kind, name),
          ),
          subtitle:
              '${l10n.documentsBadgeMissing} · ${l10n.vaultMissingSubtitle}',
          leadingIcon: RealestyIcons.warning,
          tone: RealestyListTileTone.error,
          showDivider: showDivider,
          trailing: SizedBox(
            width: 112,
            child: RealestyButton(
              label: l10n.documentsScan,
              leadingIcon: RealestyIcons.scan,
              height: 36,
              variant: RealestyButtonVariant.secondary,
              onPressed: state.busy
                  ? null
                  : () => addVaultDocument(
                      context,
                      preset: VaultAddTarget(
                        propertyId: entry.property.id,
                        kind: entry.kind,
                        ownerRef: owner?.id,
                      ),
                      source: VaultSource.scan,
                    ),
            ),
          ),
        );
      case final VaultValuationEntry entry:
        final valuation = entry.valuation;
        final busy = state.busyDocumentIds.contains(valuation.id);
        return RealestyListItem(
          title: titled(l10n.vaultValuationTitle),
          subtitle: l10n.vaultValuationSubtitle(
            documentDate(valuation.certifiedAt),
            valuation.expertDisplayName,
          ),
          leadingIcon: RealestyIcons.shield,
          tone: RealestyListTileTone.success,
          showDivider: showDivider,
          trailing: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : l10n.vaultStatusBadge(VaultDocumentStatus.verified),
          onTap: valuation.reportStoragePath == null
              ? () => context.go(AppRoutes.sellerReport(entry.property.id))
              : () => context.read<VaultCubit>().openReport(valuation),
        );
    }
  }
}
