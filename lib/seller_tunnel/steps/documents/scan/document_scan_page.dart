import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/cubit/document_scan_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Opens a scanning session for a document of [kind] (full screen, not
/// designed) with the [DocumentPicker] and the [ScanPdfBuilder] of
/// [context]; returns the PDF of the pages, or null when abandoned.
Future<PickedDocument?> showDocumentScan(
  BuildContext context, {
  required DocumentKind kind,
}) {
  final documentPicker = context.read<DocumentPicker>();
  final pdfBuilder = context.read<ScanPdfBuilder>();
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<PickedDocument>(
      fullscreenDialog: true,
      builder: (context) => DocumentScanPage(
        kind: kind,
        documentPicker: documentPicker,
        pdfBuilder: pdfBuilder,
      ),
    ),
  );
}

/// A multi-page scan of a document of [kind]: the scanner opens at once,
/// then the pages can be reviewed, reordered, deleted and completed before
/// they are combined into one PDF.
class DocumentScanPage extends StatelessWidget {
  const new({
    required this.kind,
    required this.documentPicker,
    required this.pdfBuilder,
    super.key,
  });

  final DocumentKind kind;
  final DocumentPicker documentPicker;
  final ScanPdfBuilder pdfBuilder;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = DocumentScanCubit(
          documentPicker: documentPicker,
          pdfBuilder: pdfBuilder,
        );
        // Once the view listens to the session (its first notice).
        unawaited(Future.microtask(cubit.addPages));
        return cubit;
      },
      child: DocumentScanView(kind: kind),
    );
  }
}

class DocumentScanView extends StatelessWidget {
  const new({required this.kind, super.key});

  final DocumentKind kind;

  /// "Titre de propriété - scan du 2026-10-01 18h42.pdf".
  static String fileName(
    AppLocalizations l10n,
    DocumentKind kind,
    DateTime now,
  ) {
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}h${two(now.minute)}';
    return l10n.documentsScanFileName(l10n.documentKind(kind), date);
  }

  static String _noticeMessage(
    AppLocalizations l10n,
    DocumentScanNotice notice,
  ) => switch (notice) {
    DocumentScanNotice.accessDenied => l10n.documentsNoticeAccessDenied,
    DocumentScanNotice.captureFailed => l10n.documentsScanNoticeFailed,
    DocumentScanNotice.truncated => l10n.documentsScanNoticeTruncated(
      DocumentScanCubit.maxPages,
    ),
    DocumentScanNotice.tooLarge => l10n.documentsScanNoticeTooLarge,
    DocumentScanNotice.buildFailed => l10n.documentsScanNoticeBuildFailed,
  };

  /// Asks before dropping the scanned pages.
  static Future<void> _confirmDiscard(BuildContext context) async {
    final count = context.read<DocumentScanCubit>().state.pages.length;
    final discard = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) => _DiscardSheet(pageCount: count),
    );
    if ((discard ?? false) && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<DocumentScanCubit>().state;
    final cubit = context.read<DocumentScanCubit>();
    final pages = state.pages;
    final canEdit = !state.isBusy;

    return MultiBlocListener(
      listeners: [
        // The first scan was cancelled: nothing to review.
        BlocListener<DocumentScanCubit, DocumentScanState>(
          listenWhen: (previous, current) =>
              previous.captures == 0 &&
              current.captures == 1 &&
              current.pages.isEmpty &&
              current.noticeCount == previous.noticeCount,
          listener: (context, _) => Navigator.of(context).pop(),
        ),
        BlocListener<DocumentScanCubit, DocumentScanState>(
          listenWhen: (previous, current) =>
              current.status == DocumentScanStatus.done &&
              previous.status != DocumentScanStatus.done,
          listener: (context, state) => Navigator.of(context).pop(state.result),
        ),
        BlocListener<DocumentScanCubit, DocumentScanState>(
          listenWhen: (previous, current) =>
              previous.noticeCount != current.noticeCount,
          listener: (context, state) => showRealestySnackBar(
            context,
            _noticeMessage(l10n, state.notice!),
            isError: state.notice != DocumentScanNotice.truncated,
          ),
        ),
      ],
      child: PopScope(
        canPop: pages.isEmpty && canEdit,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && canEdit) unawaited(_confirmDiscard(context));
        },
        child: Scaffold(
          backgroundColor: c.ivoire,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RealestySpacing.gutter,
                    RealestySpacing.xs,
                    RealestySpacing.gutter,
                    RealestySpacing.sm,
                  ),
                  child: Row(
                    spacing: RealestySpacing.sm,
                    children: [
                      RealestyIconButton(
                        icon: RealestyIcons.close,
                        semanticLabel: l10n.tunnelClose,
                        onPressed: canEdit
                            ? () => Navigator.of(context).maybePop()
                            : null,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.documentsScanCaption,
                              style: RealestyTextStyles.caption.copyWith(
                                color: c.texteDiscret,
                              ),
                            ),
                            Semantics(
                              header: true,
                              child: Text(
                                l10n.documentKind(kind),
                                style: RealestyTextStyles.title2.copyWith(
                                  color: c.encre,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: RealestyBadge(
                          label: l10n.documentsScanPageCount(pages.length),
                          variant: pages.isEmpty
                              ? RealestyBadgeVariant.neutral
                              : RealestyBadgeVariant.certified,
                          showIcon: false,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: pages.isEmpty
                      ? _EmptyPages(isCapturing: !canEdit)
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            RealestySpacing.gutter,
                            0,
                            RealestySpacing.gutter,
                            RealestySpacing.xl,
                          ),
                          header: Padding(
                            padding: const EdgeInsets.only(
                              bottom: RealestySpacing.xs,
                            ),
                            child: Text(
                              pages.length > 1
                                  ? l10n.documentsScanReorderHint
                                  : l10n.documentsScanSinglePageHint,
                              style: RealestyTextStyles.bodySmall.copyWith(
                                color: c.texteDiscret,
                              ),
                            ),
                          ),
                          itemCount: pages.length,
                          onReorderItem: cubit.movePage,
                          itemBuilder: (context, index) => _PageRow(
                            key: ValueKey(pages[index].id),
                            page: pages[index],
                            number: index + 1,
                            onDelete: canEdit
                                ? () => cubit.removePage(pages[index].id)
                                : null,
                          ),
                        ),
                ),
                _ScanActionBar(
                  canAdd: canEdit && !state.isFull,
                  isFull: state.isFull,
                  isBuilding: state.status == DocumentScanStatus.building,
                  pageCount: pages.length,
                  onAdd: cubit.addPages,
                  onFinish: canEdit && pages.isNotEmpty
                      ? () => cubit.finish(fileName(l10n, kind, DateTime.now()))
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// No page yet: the scanner is open, or the last scan failed.
class _EmptyPages extends StatelessWidget {
  const new({required this.isCapturing});

  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.all(RealestySpacing.gutter),
      child: Center(
        child: isCapturing
            ? CircularProgressIndicator(
                color: c.vertTexte,
                semanticsLabel: context.l10n.tunnelLoading,
              )
            : Text(
                context.l10n.documentsScanEmpty,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.body.copyWith(color: c.encre2),
              ),
      ),
    );
  }
}

/// A page: its thumbnail, its number and a delete button (long press to
/// move it).
class _PageRow extends StatelessWidget {
  const new({
    required this.page,
    required this.number,
    required this.onDelete,
    super.key,
  });

  final ScannedPage page;
  final int number;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.xs),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.field),
          border: Border.all(color: c.bordureCarte),
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RealestyRadius.tag),
              child: Container(
                width: 56,
                height: 76,
                color: c.surface2,
                child: Image.memory(
                  page.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 168,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => Center(
                    child: RealestyIcon(
                      RealestyIcons.file,
                      color: c.texteDiscret,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                l10n.documentsScanPage(number),
                style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
              ),
            ),
            RealestyIconButton(
              icon: RealestyIcons.trash,
              semanticLabel: l10n.documentsScanDeletePage(number),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ajouter une page" and "Terminer", sticky at the bottom.
class _ScanActionBar extends StatelessWidget {
  const new({
    required this.canAdd,
    required this.isFull,
    required this.isBuilding,
    required this.pageCount,
    required this.onAdd,
    required this.onFinish,
  });

  final bool canAdd;
  final bool isFull;
  final bool isBuilding;
  final int pageCount;
  final VoidCallback onAdd;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ivoire,
        border: Border(top: BorderSide(color: c.bordureCarte)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: RealestySpacing.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.sm,
            RealestySpacing.gutter,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              if (isBuilding)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.documentsScanBuildingPages(pageCount),
                    textAlign: TextAlign.center,
                    style: RealestyTextStyles.caption.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                )
              else if (isFull)
                Text(
                  l10n.documentsScanMaxPages(DocumentScanCubit.maxPages),
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              RealestyButton(
                label: l10n.documentsScanAddPage,
                leadingIcon: RealestyIcons.plus,
                variant: RealestyButtonVariant.secondary,
                height: 48,
                onPressed: canAdd ? onAdd : null,
              ),
              RealestyButton(
                label: l10n.documentsScanFinish,
                leadingIcon: RealestyIcons.check,
                isLoading: isBuilding,
                loadingSemanticLabel: l10n.documentsScanBuilding,
                onPressed: onFinish,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Abandonner ce scan ?": pops true to drop the pages.
class _DiscardSheet extends StatelessWidget {
  const new({required this.pageCount});

  final int pageCount;

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
        spacing: RealestySpacing.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.documentsScanDiscardTitle,
              style: RealestyTextStyles.title2,
            ),
          ),
          Text(
            l10n.documentsScanDiscardMessage(pageCount),
            style: RealestyTextStyles.body.copyWith(color: c.encre2),
          ),
          const SizedBox(height: RealestySpacing.xxs),
          RealestyButton(
            label: l10n.documentsScanDiscard,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          RealestyButton(
            label: l10n.documentsScanContinue,
            variant: RealestyButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
