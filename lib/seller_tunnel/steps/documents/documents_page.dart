import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_files_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/transparency_score_card.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// V7 · Le Vault documents: the documents of the dossier (photographed or
/// imported), their computed statuses, the transparency score and the
/// submission of the dossier to the expert.
class DocumentsPage extends StatelessWidget {
  const new({this.documentPicker, this.openUrl = launchUrl, super.key});

  /// Defaults to the camera, photo library and files of the device.
  final DocumentPicker? documentPicker;

  /// Opens a document (its signed URL).
  final DocumentUrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        return DocumentsCubit(
          propertyRepository: context.read<PropertyRepository>(),
          documentPicker: documentPicker ?? PlatformDocumentPicker(),
          openUrl: openUrl,
          property: tunnel.property!,
          documents: tunnel.documents,
        );
      },
      child: const DocumentsView(),
    );
  }
}

class DocumentsView extends StatefulWidget {
  const new({super.key});

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  static const SellerTunnelStep _step = SellerTunnelStep.documents;

  /// "Scanner": a photo of a document of [kind] (asked after the photo
  /// when null).
  static Future<void> _scan(BuildContext context, [DocumentKind? kind]) =>
      _add(context, DocumentSource.camera, kind);

  /// "Importer": a file or a photo of the library.
  static Future<void> _import(
    BuildContext context, [
    DocumentKind? kind,
  ]) async {
    final source = await showDocumentSourceSheet(context);
    if (source == null || !context.mounted) return;
    await _add(context, source, kind);
  }

  static Future<void> _add(
    BuildContext context,
    DocumentSource source,
    DocumentKind? kind,
  ) => context.read<DocumentsCubit>().pick(source, kind: kind);

  /// Asks the kind of the picked file, then uploads it.
  static Future<void> _askKind(BuildContext context) async {
    final cubit = context.read<DocumentsCubit>();
    final kind = await showDocumentKindSheet(context);
    if (kind == null) {
      cubit.pendingDiscarded();
    } else {
      await cubit.kindChosen(kind);
    }
  }

  /// Rows of the documents needed to send the dossier, to reveal them.
  final Map<DocumentKind, GlobalKey> _rowKeys = {
    for (final kind in DocumentChecklist.submissionKinds) kind: GlobalKey(),
  };

  /// "Envoyer mon dossier à l’expert": once the previous steps are done
  /// and with the title deed and the identity document (other missing
  /// documents can be asked for later).
  void _submit(DocumentChecklist checklist) {
    final tunnel = context.read<SellerTunnelCubit>();
    final property = tunnel.state.property!;
    if (property.currentStep < _step.number) {
      showRealestySnackBar(
        context,
        context.l10n.documentsIncomplete,
        isError: true,
      );
      context.goToTunnelStep(tunnel.state.resumeStep);
      return;
    }
    final blocking = checklist.blockingKinds;
    if (blocking.isNotEmpty) {
      context.read<DocumentsCubit>().submissionBlocked();
      final target = _rowKeys[blocking.first]!.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: RealestyMotion.page,
          alignment: 0.3,
        );
      }
      return;
    }
    unawaited(
      tunnel.saveAndContinue(_step, {
        PropertyColumns.status: PropertyStatus.submitted,
        // A dossier sent again keeps its first submission date.
        if (property.submittedAt == null)
          PropertyColumns.submittedAt: DateTime.now(),
        PropertyColumns.transparencyScore: checklist.score,
      }),
    );
  }

  /// Message of a [notice] shown as a snackbar; null for the failures of
  /// the files sheet, which shows them itself.
  static String? _noticeMessage(
    AppLocalizations l10n,
    DocumentsNotice notice,
  ) => switch (notice) {
    DocumentsNotice.fileTooLarge => l10n.documentsNoticeTooLarge,
    DocumentsNotice.unsupportedType => l10n.documentsNoticeUnsupportedType,
    DocumentsNotice.accessDenied => l10n.documentsNoticeAccessDenied,
    DocumentsNotice.pickFailed => l10n.documentsNoticePickFailed,
    DocumentsNotice.uploadFailed => l10n.documentsNoticeUploadFailed,
    DocumentsNotice.uploaded => l10n.documentsNoticeUploaded,
    DocumentsNotice.deleted => l10n.documentsNoticeDeleted,
    DocumentsNotice.deleteFailed || DocumentsNotice.openFailed => null,
  };

  static bool _isError(DocumentsNotice notice) =>
      notice != DocumentsNotice.uploaded && notice != DocumentsNotice.deleted;

  /// "votre titre de propriété et votre pièce d’identité".
  static String _documentList(AppLocalizations l10n, List<DocumentKind> kinds) {
    final names = [for (final kind in kinds) l10n.documentKindInSentence(kind)];
    return names.length == 1
        ? names.single
        : l10n.documentsTwoItems(names.first, names.last);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<DocumentsCubit>().state;
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final checklist = state.checklist;
    final canOpen = !tunnelSaving && !state.isBusy;
    final enabled = canOpen && !state.isLocked;
    final nextBest = checklist.nextBestKind;

    return MultiBlocListener(
      listeners: [
        BlocListener<DocumentsCubit, DocumentsState>(
          listenWhen: (previous, current) =>
              previous.documents != current.documents,
          listener: (context, state) => context
              .read<SellerTunnelCubit>()
              .updateChildren(documents: state.documents),
        ),
        BlocListener<DocumentsCubit, DocumentsState>(
          listenWhen: (previous, current) =>
              previous.pending == null && current.pending != null,
          listener: (context, _) => unawaited(_askKind(context)),
        ),
        BlocListener<DocumentsCubit, DocumentsState>(
          listenWhen: (previous, current) =>
              previous.noticeCount != current.noticeCount &&
              _noticeMessage(l10n, current.notice!) != null,
          listener: (context, state) => showRealestySnackBar(
            context,
            _noticeMessage(l10n, state.notice!)!,
            isError: _isError(state.notice!),
          ),
        ),
      ],
      child: TunnelScaffold(
        header: TunnelHeader(
          step: _step,
          onBack: () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          hint: checklist.canSubmit
              ? l10n.documentsActionHint(checklist.optionalMissingCount)
              : l10n.documentsActionHintBlocked(checklist.optionalMissingCount),
          label: l10n.documentsSubmit,
          variant: RealestyButtonVariant.accent,
          trailingIcon: RealestyIcons.chevronRight,
          isLoading: tunnelSaving,
          onPressed: state.isBusy || state.isLocked
              ? null
              : () => _submit(checklist),
        ),
        children: [
          AgentIntro(message: l10n.documentsAgentMessage),
          if (state.isLocked)
            InlineBanner(
              message: l10n.documentsLocked,
              variant: InlineBannerVariant.info,
              icon: RealestyIcons.lock,
            ),
          TransparencyScoreCard(
            score: checklist.score,
            hint: nextBest == null
                ? l10n.documentsScoreComplete
                : l10n.documentsScoreHint(
                    l10n.documentKindInSentence(nextBest),
                  ),
          ),
          if (state.showsSubmissionErrors && !checklist.canSubmit)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.documentsSubmitBlocked(
                  _documentList(l10n, checklist.blockingKinds),
                ),
                style: RealestyTextStyles.fieldError.copyWith(
                  color: context.realestyColors.erreur,
                ),
              ),
            ),
          _DocumentsCard(
            checklist: checklist,
            rowKeys: _rowKeys,
            showsSubmissionErrors: state.showsSubmissionErrors,
            uploading: state.uploading,
            enabled: enabled,
            canOpen: canOpen,
            onScan: (kind) => _scan(context, kind),
            onImport: (kind) => _import(context, kind),
            onOpenFiles: (kind) => showDocumentFilesSheet(context, kind),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: RealestyButton(
                  label: l10n.documentsScan,
                  leadingIcon: RealestyIcons.camera,
                  height: 48,
                  onPressed: enabled ? () => _scan(context) : null,
                ),
              ),
              Expanded(
                child: RealestyButton(
                  label: l10n.documentsImport,
                  leadingIcon: RealestyIcons.upload,
                  variant: RealestyButtonVariant.secondary,
                  height: 48,
                  onPressed: enabled ? () => _import(context) : null,
                ),
              ),
            ],
          ),
          _PrivacyNote(message: l10n.documentsPrivacyNote),
        ],
      ),
    );
  }
}

/// The documents card: one row per kind of document, then the file being
/// uploaded.
class _DocumentsCard extends StatelessWidget {
  const new({
    required this.checklist,
    required this.rowKeys,
    required this.showsSubmissionErrors,
    required this.uploading,
    required this.enabled,
    required this.canOpen,
    required this.onScan,
    required this.onImport,
    required this.onOpenFiles,
  });

  final DocumentChecklist checklist;

  /// Keys of the rows needed to send the dossier.
  final Map<DocumentKind, GlobalKey> rowKeys;

  /// Whether the missing documents needed to send are shown as errors.
  final bool showsSubmissionErrors;
  final PickedDocument? uploading;
  final bool enabled;

  /// Whether the files can be listed and opened (also when locked).
  final bool canOpen;
  final ValueChanged<DocumentKind> onScan;
  final ValueChanged<DocumentKind> onImport;
  final ValueChanged<DocumentKind> onOpenFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final rows = checklist.rows;
    final uploading = this.uploading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, row) in rows.indexed)
            _row(
              context,
              row,
              isLast: index == rows.length - 1 && uploading == null,
            ),
          if (uploading != null)
            RealestyListItem(
              title: uploading.fileName,
              subtitle: l10n.documentsUploading,
              leadingIcon: RealestyIcons.file,
              showDivider: false,
              trailing: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.vertTexte,
                  semanticsLabel: l10n.tunnelLoading,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, DocumentRow row, {required bool isLast}) {
    final l10n = context.l10n;
    final badge = documentStatusBadge(l10n, row.status);
    final needsFile =
        row.status == DocumentRowStatus.missing ||
        row.status == DocumentRowStatus.rejected;
    final kindLabel = l10n.documentKind(row.kind);
    // Diagnostics are reports (PDF) rather than paper to photograph.
    final imports = row.kind == DocumentKind.diagnostics;
    final showsError =
        showsSubmissionErrors && checklist.blockingKinds.contains(row.kind);
    final item = RealestyListItem(
      key: ValueKey(row.kind),
      title: kindLabel,
      subtitle: l10n.documentRowSubtitle(row, checklist.sanitationRule),
      leadingIcon: RealestyIcons.file,
      tone: documentStatusTone(row.status),
      showDivider: !isLast && !showsError,
      onTap: row.documents.isEmpty || !canOpen
          ? null
          : () => onOpenFiles(row.kind),
      trailing: needsFile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                badge,
                _RowAction(
                  label: imports ? l10n.documentsImport : l10n.documentsScan,
                  semanticLabel: imports
                      ? l10n.documentsImportFor(kindLabel)
                      : l10n.documentsScanFor(kindLabel),
                  onPressed: enabled
                      ? () => imports ? onImport(row.kind) : onScan(row.kind)
                      : null,
                ),
              ],
            )
          : badge,
    );
    final key = rowKeys[row.kind];
    if (!showsError) {
      return key == null ? item : KeyedSubtree(key: key, child: item);
    }
    final c = context.realestyColors;
    return Container(
      key: key,
      padding: const EdgeInsets.only(bottom: RealestySpacing.sm),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: c.bordureCarte)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item,
          Text(
            l10n.documentsRequiredForSubmission,
            style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
          ),
        ],
      ),
    );
  }
}

/// Action link of a row ("Scanner"), 13/700 Vert texte, with a 44 px
/// touch target.
class _RowAction extends StatelessWidget {
  const new({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: RealestySpacing.minTouchTarget,
          minHeight: RealestySpacing.minTouchTarget,
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: Alignment.centerRight,
          child: Text(
            label,
            style: RealestyTextStyles.listSubtitle.copyWith(
              fontWeight: FontWeight.w700,
              color: context.realestyColors.vertTexte,
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral note with a lock (Surface 2), about the privacy of the files.
class _PrivacyNote extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(RealestyRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          RealestyIcon(RealestyIcons.lock, size: 18, color: c.encre2),
          Expanded(
            child: Text(
              message,
              style: RealestyTextStyles.banner.copyWith(color: c.encre),
            ),
          ),
        ],
      ),
    );
  }
}
