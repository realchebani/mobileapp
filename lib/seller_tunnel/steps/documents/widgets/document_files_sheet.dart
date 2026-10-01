import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Lists the files of [kind] to open or delete them (not designed: a
/// sheet). Closes itself once the last file is deleted.
Future<void> showDocumentFilesSheet(BuildContext context, DocumentKind kind) {
  final cubit = context.read<DocumentsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => BlocProvider.value(
      value: cubit,
      child: DocumentFilesSheet(kind: kind),
    ),
  );
}

/// Content of [showDocumentFilesSheet].
class DocumentFilesSheet extends StatefulWidget {
  const new({required this.kind, super.key});

  final DocumentKind kind;

  @override
  State<DocumentFilesSheet> createState() => _DocumentFilesSheetState();
}

class _DocumentFilesSheetState extends State<DocumentFilesSheet> {
  /// The file whose deletion is being confirmed.
  PropertyDocument? _confirming;

  /// Failure of the last action, shown in the sheet (a snackbar would be
  /// hidden behind it).
  String? _error;

  List<PropertyDocument> _filesOf(DocumentsState state) => [
    for (final document in state.documents)
      if (document.kind == widget.kind) document,
  ];

  Future<void> _delete(PropertyDocument document) async {
    setState(() {
      _confirming = null;
      _error = null;
    });
    await context.read<DocumentsCubit>().delete(document);
  }

  Future<void> _open(PropertyDocument document) async {
    setState(() => _error = null);
    await context.read<DocumentsCubit>().open(document);
  }

  void _onNotice(BuildContext context, DocumentsState state) {
    final l10n = context.l10n;
    final error = switch (state.notice) {
      DocumentsNotice.openFailed => l10n.documentsNoticeOpenFailed,
      DocumentsNotice.deleteFailed => l10n.documentsNoticeDeleteFailed,
      _ => null,
    };
    if (error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<DocumentsCubit>().state;
    final files = _filesOf(state);
    final confirming = _confirming;
    final error = _error;
    return MultiBlocListener(
      listeners: [
        BlocListener<DocumentsCubit, DocumentsState>(
          listenWhen: (previous, current) =>
              _filesOf(previous).isNotEmpty && _filesOf(current).isEmpty,
          listener: (context, _) => Navigator.of(context).pop(),
        ),
        BlocListener<DocumentsCubit, DocumentsState>(
          listenWhen: (previous, current) =>
              previous.noticeCount != current.noticeCount,
          listener: _onNotice,
        ),
      ],
      child: Padding(
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
                  confirming == null
                      ? l10n.documentKind(widget.kind)
                      : l10n.documentsDeleteTitle,
                  style: RealestyTextStyles.title2,
                ),
              ),
            ),
            if (error != null && confirming == null)
              Padding(
                padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
                child: InlineBanner(message: error),
              ),
            if (confirming != null)
              _DeleteConfirmation(
                document: confirming,
                onConfirm: () => _delete(confirming),
                onCancel: () => setState(() => _confirming = null),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (index, document) in files.indexed)
                      _FileRow(
                        document: document,
                        isBusy: state.busyDocumentIds.contains(document.id),
                        canDelete: !state.isBusy && !state.isLocked,
                        onOpen: () => _open(document),
                        showDivider: index < files.length - 1,
                        onDelete: () => setState(() => _confirming = document),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const new({
    required this.document,
    required this.isBusy,
    required this.canDelete,
    required this.showDivider,
    required this.onOpen,
    required this.onDelete,
  });

  final PropertyDocument document;
  final bool isBusy;
  final bool canDelete;
  final bool showDivider;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final uploadedAt = document.uploadedAt;
    final size = document.sizeBytes;
    final subtitle = [
      if (uploadedAt != null) l10n.documentsFileAdded(documentDate(uploadedAt)),
      if (size != null) l10n.documentSize(size),
    ].join(' · ');
    final name = document.fileName ?? l10n.documentKind(document.kind);
    return RealestyListItem(
      title: name,
      subtitle: subtitle.isEmpty ? null : subtitle,
      leadingIcon: RealestyIcons.file,
      showDivider: showDivider,
      trailing: isBusy
          ? SizedBox.square(
              dimension: RealestySpacing.minTouchTarget,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.vertTexte,
                    semanticsLabel: l10n.tunnelLoading,
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: RealestySpacing.xs,
              children: [
                RealestyIconButton(
                  icon: RealestyIcons.eye,
                  semanticLabel: l10n.documentsOpenFile(name),
                  onPressed: onOpen,
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.documentsDeleteFile(name),
                  onPressed: canDelete ? onDelete : null,
                ),
              ],
            ),
    );
  }
}

class _DeleteConfirmation extends StatelessWidget {
  const new({
    required this.document,
    required this.onConfirm,
    required this.onCancel,
  });

  final PropertyDocument document;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.sm,
      children: [
        Text(
          l10n.documentsDeleteMessage(
            document.fileName ?? l10n.documentKind(document.kind),
          ),
          style: RealestyTextStyles.body.copyWith(color: c.encre2),
        ),
        const SizedBox(height: RealestySpacing.xxs),
        RealestyButton(label: l10n.documentsDelete, onPressed: onConfirm),
        RealestyButton(
          label: l10n.documentsCancel,
          variant: RealestyButtonVariant.text,
          onPressed: onCancel,
        ),
      ],
    );
  }
}
