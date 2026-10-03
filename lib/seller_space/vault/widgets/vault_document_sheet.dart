import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_actions.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_entry_row.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Opens the detail of the document [documentId] (V18 sheet).
Future<void> showVaultDocumentSheet(BuildContext context, String documentId) {
  final cubit = context.read<VaultCubit>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.realestyColors.ivoire,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: VaultDocumentSheet(documentId: documentId),
    ),
  );
}

/// Detail of a document: what it is, the expert's request, who may see it,
/// and the actions the rules allow (open, download, rename, replace,
/// delete).
class VaultDocumentSheet extends StatefulWidget {
  const new({required this.documentId, super.key});

  final String documentId;

  @override
  State<VaultDocumentSheet> createState() => _VaultDocumentSheetState();
}

class _VaultDocumentSheetState extends State<VaultDocumentSheet> {
  bool _confirmingDelete = false;

  Future<void> _rename(PropertyDocument document, String current) async {
    final cubit = context.read<VaultCubit>();
    final title = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => VaultRenameSheet(initialTitle: current),
    );
    if (title != null) await cubit.rename(document, title);
  }

  Future<void> _delete(PropertyDocument document) async {
    final navigator = Navigator.of(context);
    await context.read<VaultCubit>().delete(document);
    if (mounted &&
        context.read<VaultCubit>().state.documentById(document.id) == null) {
      navigator.pop();
    }
  }

  Future<void> _replace(PropertyDocument document) async {
    final navigator = Navigator.of(context);
    await replaceVaultDocument(context, document);
    if (!mounted) return;
    final current = context.read<VaultCubit>().state.documentById(document.id);
    if (current == null || current.replacedBy != null) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<VaultCubit>().state;
    final document = state.documentById(widget.documentId);
    final property = document == null
        ? null
        : state.propertyById(document.propertyId);
    if (document == null || property == null) return const SizedBox.shrink();
    final entry = VaultDocumentEntry(property: property, document: document);
    final cubit = context.read<VaultCubit>();
    final busy = state.busyDocumentIds.contains(document.id) || state.busy;
    final title = l10n.vaultDocumentTitle(
      document,
      owner: vaultOwnerOf(state, document),
    );
    final reason = document.rejectedReason;
    final extracted = [
      for (final MapEntry(:key, :value)
          in (document.extracted ?? const <String, dynamic>{}).entries)
        if (value is String || value is num) (key, '$value'),
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.xs,
          RealestySpacing.gutter,
          RealestySpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.md,
          children: [
            Row(
              spacing: RealestySpacing.sm,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(RealestyRadius.field),
                  ),
                  child: RealestyIcon(
                    document.mimeType == 'application/pdf'
                        ? RealestyIcons.file
                        : RealestyIcons.camera,
                    color: c.encre,
                  ),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.pen,
                  semanticLabel: l10n.vaultRename,
                  onPressed: busy
                      ? null
                      : () => _rename(document, document.title ?? title),
                ),
              ],
            ),
            Wrap(
              spacing: RealestySpacing.xs,
              runSpacing: RealestySpacing.xs,
              children: [
                l10n.vaultStatusBadge(entry.status),
                if (document.addedAfterSubmission)
                  RealestyBadge(label: l10n.vaultAddedAfterSending),
              ],
            ),
            SellerSpaceCardLite(
              children: [
                KeyValueRow(
                  label: l10n.vaultDetailKind,
                  value: l10n.vaultKind(document.kind),
                ),
                if (document.sizeBytes case final size?)
                  KeyValueRow(
                    label: l10n.vaultDetailSize,
                    value: l10n.documentSize(size),
                  ),
                if (document.uploadedAt case final date?)
                  KeyValueRow(
                    label: l10n.vaultDetailDate,
                    value: documentDate(date),
                    divider: false,
                  ),
              ],
            ),
            if (entry.status == VaultDocumentStatus.toReplace)
              InlineBanner(
                message: reason == null
                    ? l10n.vaultRejectedNoReason
                    : l10n.vaultRejected(reason),
              ),
            if (extracted.isNotEmpty) ...[
              Text(
                l10n.vaultExtractedTitle,
                style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
              ),
              SellerSpaceCardLite(
                children: [
                  for (final (index, (key, value)) in extracted.indexed)
                    KeyValueRow(
                      label: key,
                      value: value,
                      divider: index < extracted.length - 1,
                      trailing: const ProvenanceTag(ProvenanceKind.document),
                    ),
                ],
              ),
            ],
            Text(
              l10n.vaultSharingTitle,
              style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
            ),
            if (entry.canShare) ...[
              SellerSpaceCardLite(
                children: [
                  VaultSwitchRow(
                    title: l10n.vaultSharingBuyers,
                    subtitle: l10n.vaultSharingBuyersSubtitle,
                    value: document.visibility.contains(
                      DocumentVisibility.buyers,
                    ),
                    onChanged: busy
                        ? null
                        : (on) => cubit.setVisibility(document, {
                            ...document.visibility.where(
                              (v) => v != DocumentVisibility.buyers,
                            ),
                            if (on) DocumentVisibility.buyers,
                          }),
                  ),
                  VaultSwitchRow(
                    title: l10n.vaultSharingNotary,
                    subtitle: l10n.vaultSharingNotarySubtitle,
                    value: document.visibility.contains(
                      DocumentVisibility.notary,
                    ),
                    showDivider: false,
                    onChanged: busy
                        ? null
                        : (on) => cubit.setVisibility(document, {
                            ...document.visibility.where(
                              (v) => v != DocumentVisibility.notary,
                            ),
                            if (on) DocumentVisibility.notary,
                          }),
                  ),
                ],
              ),
              Text(
                l10n.vaultSharingLater,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ] else
              Row(
                spacing: RealestySpacing.xs,
                children: [
                  RealestyIcon(RealestyIcons.lock, size: 16, color: c.encre2),
                  Expanded(
                    child: Text(
                      l10n.vaultSharingPrivate,
                      style: RealestyTextStyles.body.copyWith(color: c.encre2),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: RealestySpacing.xs),
            RealestyButton(
              label: l10n.vaultOpen,
              leadingIcon: RealestyIcons.eye,
              onPressed: busy ? null : () => cubit.open(document),
            ),
            RealestyButton(
              label: l10n.vaultDownload,
              leadingIcon: RealestyIcons.download,
              variant: RealestyButtonVariant.secondary,
              onPressed: busy ? null : () => cubit.share(document),
            ),
            if (entry.canReplace)
              RealestyButton(
                label: l10n.vaultReplace,
                leadingIcon: RealestyIcons.swap,
                variant: RealestyButtonVariant.secondary,
                onPressed: busy ? null : () => _replace(document),
              ),
            if (entry.canDelete && !_confirmingDelete)
              RealestyButton(
                label: l10n.vaultDelete,
                leadingIcon: RealestyIcons.trash,
                variant: RealestyButtonVariant.text,
                onPressed: busy
                    ? null
                    : () => setState(() => _confirmingDelete = true),
              ),
            if (entry.canDelete && _confirmingDelete) ...[
              InlineBanner(message: l10n.vaultDeleteConfirm),
              Row(
                spacing: RealestySpacing.sm,
                children: [
                  Expanded(
                    child: RealestyButton(
                      label: l10n.vaultDeleteCancel,
                      variant: RealestyButtonVariant.secondary,
                      onPressed: () =>
                          setState(() => _confirmingDelete = false),
                    ),
                  ),
                  Expanded(
                    child: RealestyButton(
                      label: l10n.vaultDeleteConfirmButton,
                      variant: RealestyButtonVariant.accent,
                      isLoading: busy,
                      onPressed: busy ? null : () => _delete(document),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// White card around a list of rows (key-values, switches).
class SellerSpaceCardLite extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(children: children),
    );
  }
}

/// A row with a title, a subtitle and a switch.
class VaultSwitchRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final subtitle = this.subtitle;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RealestySpacing.sm),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: c.bordureCarte))
              : null,
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: c.vert,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Renommer": the title of a document; pops with it.
class VaultRenameSheet extends StatefulWidget {
  const new({required this.initialTitle, super.key});

  final String initialTitle;

  @override
  State<VaultRenameSheet> createState() => _VaultRenameSheetState();
}

class _VaultRenameSheetState extends State<VaultRenameSheet> {
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        RealestySpacing.gutter,
        RealestySpacing.xs,
        RealestySpacing.gutter,
        RealestySpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.md,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.vaultRename, style: RealestyTextStyles.title2),
          ),
          RealestyTextField(
            label: l10n.vaultRenameLabel,
            controller: _controller,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          RealestyButton(
            label: l10n.vaultRenameSave,
            onPressed: () => Navigator.of(context).pop(_controller.text),
          ),
        ],
      ),
    );
  }
}
