import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/view/dossier_page.dart';
import 'package:realesty_backoffice/dossier/widgets/dossier_labels.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Documents of the dossier: open (signed URL), verify, refuse with a
/// reason. Identity documents are listed apart (never sent to partners).
class DocumentsTab extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final identity = [
      for (final d in dossier.documents)
        if (d.isIdentity) d,
    ];
    final others = [
      for (final d in dossier.documents)
        if (!d.isIdentity) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.docsIntro,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        const SizedBox(height: RealestySpacing.md),
        if (identity.isNotEmpty) ...[
          BoCard(
            title: l10n.docsIdentity,
            child: Column(
              children: [
                for (final document in identity)
                  _DocumentRow(document: document),
              ],
            ),
          ),
          const SizedBox(height: RealestySpacing.md),
        ],
        BoCard(
          title: l10n.dossierTabDocuments,
          child: others.isEmpty
              ? Text(l10n.docsNone)
              : Column(
                  children: [
                    for (final document in others)
                      _DocumentRow(document: document),
                  ],
                ),
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const new({required this.document});

  final DossierDocument document;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<DossierCubit>();
    final busy = context.select<DossierCubit, bool>(
      (cubit) => cubit.state.busy,
    );
    final canVerify = context.can(BackOfficeCapability.verifyDocuments);
    final kind = documentKindLabel(l10n, document.kind);
    return FieldRow(
      label: document.title ?? kind,
      value: [
        if (document.title != null) kind,
        ?document.fileName,
        if (document.uploadedAt != null) dateTimeFr(document.uploadedAt!),
      ].join(' · '),
      detail: document.isRejected
          ? l10n.docsRejected(document.rejectedReason ?? '')
          : null,
      tags: [
        if (document.isVerified)
          BoChip(
            l10n.docsVerified(dateFr(document.verifiedAt!)),
            color: c.vertTexte,
            background: c.vertTeinte,
          ),
        if (document.toVerify)
          BoChip(
            l10n.docsToVerify,
            color: c.attention,
            background: c.attentionFond,
          ),
        if (document.addedAfterSubmission) BoChip(l10n.docsAfter),
        if (document.isReplaced) BoChip(l10n.docsReplaced),
        TextButton(
          onPressed: () => runGuarded(context, () async {
            final browser = context.read<Browser>();
            final signed = await context.read<BackOfficeRepository>().signFiles(
              cubit.state.dossier!.id,
              [FileRequest(FileKind.document, document.id)],
            );
            await browser.open(signed.single.url);
          }),
          child: Text(l10n.docsOpen),
        ),
        if (canVerify && !document.isVerified && !document.isReplaced)
          TextButton(
            onPressed: busy
                ? null
                : () => runGuarded(
                    context,
                    () => cubit.verifyDocument(document.id),
                    success: l10n.docsVerifiedDone,
                  ),
            child: Text(l10n.docsVerify),
          ),
        if (canVerify && !document.isRejected && !document.isReplaced)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final reason = await showDialog<String>(
                      context: context,
                      builder: (_) => const RejectDialog(),
                    );
                    if (reason == null || !context.mounted) return;
                    await runGuarded(
                      context,
                      () => cubit.rejectDocument(document.id, reason),
                      success: l10n.docsRejectedDone,
                    );
                  },
            child: Text(l10n.docsReject),
          ),
      ],
    );
  }
}

/// Asks the reason of a refusal (templates or free text, 1 to 300).
class RejectDialog extends StatefulWidget {
  const new({super.key});

  @override
  State<RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final templates = [
      l10n.docsReasonUnreadable,
      l10n.docsReasonIncomplete,
      l10n.docsReasonWrong,
      l10n.docsReasonExpired,
    ];
    final reason = _reason.text.trim();
    return AlertDialog(
      title: Text(l10n.docsRejectTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.docsRejectBody),
            const SizedBox(height: RealestySpacing.md),
            Wrap(
              spacing: RealestySpacing.xs,
              runSpacing: RealestySpacing.xs,
              children: [
                for (final template in templates)
                  ActionChip(
                    label: Text(template),
                    onPressed: () => setState(() => _reason.text = template),
                  ),
              ],
            ),
            const SizedBox(height: RealestySpacing.md),
            RealestyTextField(
              label: l10n.docsRejectReason,
              controller: _reason,
              maxLines: 3,
              inputFormatters: [LengthLimitingTextInputFormatter(300)],
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.of(context).pop(reason),
          child: Text(l10n.docsReject),
        ),
      ],
    );
  }
}
