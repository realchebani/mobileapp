import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/models/document_checklist.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/document_scan_page.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_files_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/reuse_document_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/transparency_score_card.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// V7 · Le Vault documents: the documents of the dossier (scanned or
/// imported, row by row), their computed statuses, the transparency score
/// and the submission of the dossier to the expert.
class DocumentsPage extends StatelessWidget {
  const new({
    this.documentPicker,
    this.scanPdfBuilder,
    this.openUrl = launchUrl,
    super.key,
  });

  /// Defaults to the document scanner, photo library and files of the
  /// device.
  final DocumentPicker? documentPicker;

  /// Combines the scanned pages into a PDF; defaults to
  /// [IsolateScanPdfBuilder].
  final ScanPdfBuilder? scanPdfBuilder;

  /// Opens a document (its signed URL).
  final DocumentUrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DocumentPicker>(
          create: (_) => documentPicker ?? PlatformDocumentPicker(),
        ),
        RepositoryProvider<ScanPdfBuilder>(
          create: (_) => scanPdfBuilder ?? const IsolateScanPdfBuilder(),
        ),
      ],
      child: BlocProvider(
        create: (context) {
          final tunnel = context.read<SellerTunnelCubit>().state;
          return DocumentsCubit(
            propertyRepository: context.read<PropertyRepository>(),
            documentPicker: context.read<DocumentPicker>(),
            openUrl: openUrl,
            property: tunnel.property!,
            documents: tunnel.documents,
          );
        },
        child: const DocumentsView(),
      ),
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

  /// "Scanner": a multi-page scan of a document of [kind], uploaded as
  /// one PDF.
  static Future<void> _scan(BuildContext context, DocumentKind kind) async {
    final cubit = context.read<DocumentsCubit>();
    final scan = await showDocumentScan(context, kind: kind);
    if (scan != null) await cubit.addScan(scan, kind: kind);
  }

  /// "Importer": a file or a photo of the library, or a document of the
  /// same kind of another property of the seller, as a document of [kind].
  static Future<void> _import(BuildContext context, DocumentKind kind) async {
    final others =
        (context.read<SellerPropertiesCubit?>()?.state.properties.length ?? 0) >
        1;
    final source = await showDocumentSourceSheet(
      context,
      otherProperties: others,
    );
    if (source == null || !context.mounted) return;
    final cubit = context.read<DocumentsCubit>();
    switch (source) {
      case DocumentImportSource.files:
        await cubit.pick(DocumentSource.files, kind: kind);
      case DocumentImportSource.photos:
        await cubit.pick(DocumentSource.photos, kind: kind);
      case DocumentImportSource.otherProperty:
        final document = await showReuseDocumentSheet(context, kind: kind);
        if (document != null) await cubit.reuse(document);
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
    if (context.read<DocumentsCubit>().state.failedUploads.isNotEmpty) {
      // Sending now would lose these files.
      showRealestySnackBar(
        context,
        context.l10n.documentsSubmitFailedUploads,
        isError: true,
      );
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
    unawaited(_send(tunnel, property, checklist));
  }

  /// Sends the dossier, then asks the backend for the non-certified
  /// estimate (EPIC-05) without waiting for it: V8 shows its progress and
  /// offers to retry when it fails.
  Future<void> _send(
    SellerTunnelCubit tunnel,
    Property property,
    DocumentChecklist checklist,
  ) async {
    final repository = context.read<PropertyRepository>();
    await tunnel.saveAndContinue(_step, {
      // Answers hidden by a change of type are cleared now (owner decision
      // Q9: kept while the dossier is a draft).
      ...tunnel.state.profile.clearedFrom(property),
      PropertyColumns.status: PropertyStatus.submitted,
      // A dossier sent again keeps its first submission date.
      if (property.submittedAt == null)
        PropertyColumns.submittedAt: DateTime.now(),
      PropertyColumns.transparencyScore: checklist.score,
    });
    if (tunnel.state.saveStatus != SellerTunnelSaveStatus.success) return;
    unawaited(
      repository
          .requestEstimate(property.id)
          .then<void>(
            (_) {},
            // V8 requests it again when no attempt was recorded.
            onError: (Object _) {},
          ),
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
    DocumentsNotice.reuseFailed => l10n.documentsNoticeReuseFailed,
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
          hint: state.isLocked
              ? null
              : checklist.canSubmit
              ? l10n.documentsActionHint(checklist.optionalMissingCount)
              : l10n.documentsActionHintBlocked(checklist.optionalMissingCount),
          // The full label does not fit with large text.
          label: MediaQuery.textScalerOf(context).scale(1) > 1.15
              ? l10n.documentsSubmitShort
              : l10n.documentsSubmit,
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
            failedUploads: state.failedUploads,
            enabled: enabled,
            isLocked: state.isLocked,
            canOpen: canOpen,
            onScan: (kind) => _scan(context, kind),
            onImport: (kind) => _import(context, kind),
            onOpenFiles: (kind) => showDocumentFilesSheet(context, kind),
            onRetry: context.read<DocumentsCubit>().retryUpload,
            onDiscard: context.read<DocumentsCubit>().discardFailedUpload,
          ),
          _PrivacyNote(
            message: state.isLocked
                ? l10n.documentsPrivacyNoteLocked
                : l10n.documentsPrivacyNote,
          ),
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
    required this.failedUploads,
    required this.enabled,
    required this.isLocked,
    required this.canOpen,
    required this.onScan,
    required this.onImport,
    required this.onOpenFiles,
    required this.onRetry,
    required this.onDiscard,
  });

  final DocumentChecklist checklist;

  /// Keys of the rows needed to send the dossier.
  final Map<DocumentKind, GlobalKey> rowKeys;

  /// Whether the missing documents needed to send are shown as errors.
  final bool showsSubmissionErrors;
  final PickedDocument? uploading;

  /// Files whose upload failed ("Réessayer" / "Retirer").
  final List<FailedUpload> failedUploads;
  final bool enabled;

  /// Whether the dossier is read-only (no "Scanner"/"Importer" links).
  final bool isLocked;

  /// Whether the files can be listed and opened (also when locked).
  final bool canOpen;
  final ValueChanged<DocumentKind> onScan;
  final ValueChanged<DocumentKind> onImport;
  final ValueChanged<DocumentKind> onOpenFiles;
  final ValueChanged<FailedUpload> onRetry;
  final ValueChanged<FailedUpload> onDiscard;

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
              isLast:
                  index == rows.length - 1 &&
                  uploading == null &&
                  failedUploads.isEmpty,
            ),
          for (final (index, failed) in failedUploads.indexed)
            RealestyListItem(
              key: ObjectKey(failed),
              title: failed.file.fileName,
              subtitle: l10n.documentsUploadFailedRow(
                l10n.documentKind(failed.kind),
              ),
              leadingIcon: RealestyIcons.file,
              tone: RealestyListTileTone.error,
              showDivider:
                  index < failedUploads.length - 1 || uploading != null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RowAction(
                    label: l10n.documentsRetry,
                    icon: RealestyIcons.upload,
                    semanticLabel: l10n.documentsRetryFile(
                      failed.file.fileName,
                    ),
                    onPressed: enabled ? () => onRetry(failed) : null,
                  ),
                  RealestyIconButton(
                    icon: RealestyIcons.close,
                    semanticLabel: l10n.documentsDiscardFile(
                      failed.file.fileName,
                    ),
                    onPressed: enabled ? () => onDiscard(failed) : null,
                  ),
                ],
              ),
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
    final c = context.realestyColors;
    final kindLabel = l10n.documentKind(row.kind);
    final showsError =
        showsSubmissionErrors && checklist.blockingKinds.contains(row.kind);
    final hasActions =
        !isLocked && row.status != DocumentRowStatus.notConcerned;
    final item = RealestyListItem(
      key: ValueKey(row.kind),
      title: kindLabel,
      subtitle: l10n.documentRowSubtitle(row, checklist.sanitationRule),
      leadingIcon: RealestyIcons.file,
      tone: documentStatusTone(row.status),
      showDivider: !isLast && !showsError && !hasActions,
      onTap: row.documents.isEmpty || !canOpen
          ? null
          : () => onOpenFiles(row.kind),
      trailing: documentStatusBadge(l10n, row.status),
    );
    final key = rowKeys[row.kind];
    if (!showsError && !hasActions) {
      return key == null ? item : KeyedSubtree(key: key, child: item);
    }
    return Container(
      key: key,
      padding: hasActions
          ? null
          : const EdgeInsets.only(bottom: RealestySpacing.sm),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: c.bordureCarte)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item,
          if (showsError)
            Padding(
              padding: const EdgeInsets.only(left: _actionsIndent),
              child: Text(
                l10n.documentsRequiredForSubmission,
                style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
              ),
            ),
          if (hasActions)
            Padding(
              padding: const EdgeInsets.only(left: _actionsIndent - 10),
              // Side by side; one under the other with very large text.
              child: Wrap(
                children: [
                  _RowAction(
                    label: l10n.documentsScan,
                    icon: RealestyIcons.scan,
                    semanticLabel: l10n.documentsScanFor(kindLabel),
                    onPressed: enabled ? () => onScan(row.kind) : null,
                  ),
                  _RowAction(
                    label: l10n.documentsImport,
                    icon: RealestyIcons.upload,
                    semanticLabel: l10n.documentsImportFor(kindLabel),
                    onPressed: enabled ? () => onImport(row.kind) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Left inset of the lines under a row, aligned with its title (tile 40
  /// + gap 12).
  static const double _actionsIndent = 40 + RealestySpacing.sm;
}

/// Action link of a row ("Scanner", "Importer"): icon and 13/700 Vert
/// texte label, with a 44 px touch target.
class _RowAction extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final RealestyIcons icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = context.realestyColors.vertTexte;
    return RealestyPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: RealestySpacing.minTouchTarget,
          minHeight: RealestySpacing.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              RealestyIcon(icon, size: 16, color: color),
              Text(
                label,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
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
