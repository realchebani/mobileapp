import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Largest report accepted (the bucket allows 30 MB).
const int maxReportBytes = 20 * 1024 * 1024;

/// Why [bytes] cannot be sent as the report, or null.
String? pdfProblem(AppLocalizations l10n, Uint8List bytes) {
  if (bytes.length > maxReportBytes) return l10n.formReportTooLarge;
  const header = [0x25, 0x50, 0x44, 0x46]; // %PDF
  if (bytes.length < header.length ||
      [for (var i = 0; i < header.length; i++) bytes[i]].join() !=
          header.join()) {
    return l10n.formReportNotPdf;
  }
  return null;
}

/// A certified dossier: the valuation summary and its PDF (upload, open).
class CertifiedView extends StatefulWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  State<CertifiedView> createState() => _CertifiedViewState();
}

class _CertifiedViewState extends State<CertifiedView> {
  final _pages = TextEditingController();
  bool _uploading = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final l10n = context.l10n;
    final pages = int.tryParse(_pages.text.trim());
    if (pages == null || pages < 1 || pages > 500) {
      showRealestySnackBar(context, l10n.formReportPagesInvalid, isError: true);
      return;
    }
    final repository = context.read<BackOfficeRepository>();
    final dossierCubit = context.read<DossierCubit>();
    final file = await context.read<Browser>().pickPdf();
    if (file == null || !mounted) return;
    final problem = pdfProblem(l10n, file.bytes);
    if (problem != null) {
      showRealestySnackBar(context, problem, isError: true);
      return;
    }
    setState(() => _uploading = true);
    final done = await runGuarded(
      context,
      () =>
          repository.uploadReport(widget.dossier.id, file.bytes, pages: pages),
      success: l10n.formReportDone,
    );
    if (mounted) setState(() => _uploading = false);
    if (done && mounted) await runGuarded(context, dossierCubit.load);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final v = widget.dossier.valuation ?? const {};
    final canAttach = context.select<SessionCubit, bool>(
      (s) => s.state.me?.can(BackOfficeCapability.attachReport) ?? false,
    );
    final reportPages = Json.integer(v['report_pages']);
    final hasReport = v['report_storage_path'] != null;
    final certifiedAt = Json.date(v['certified_at']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoCard(
          title: l10n.formCertifiedTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.formCertifiedBody(
                  euros(Json.integer(v['value_eur']) ?? 0),
                  euros(Json.integer(v['low_eur']) ?? 0),
                  euros(Json.integer(v['high_eur']) ?? 0),
                  v['expert_display_name'] as String? ?? '',
                  certifiedAt == null ? '' : dateFr(certifiedAt),
                ),
                style: RealestyTextStyles.label,
              ),
              const SizedBox(height: RealestySpacing.xs),
              Text(
                l10n.formCertifiedCorrect,
                style: RealestyTextStyles.bodySmall.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: RealestySpacing.lg),
        BoCard(
          title: l10n.formReport,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasReport)
                Row(
                  children: [
                    Text(l10n.formReportAttached(reportPages ?? 0)),
                    const SizedBox(width: RealestySpacing.sm),
                    TextButton(
                      onPressed: () {
                        final repository = context.read<BackOfficeRepository>();
                        unawaited(
                          runGuarded(
                            context,
                            () => context.read<Browser>().openPending(() async {
                              final signed = await repository.signFiles(
                                widget.dossier.id,
                                [
                                  FileRequest(
                                    FileKind.report,
                                    v['id'] as String,
                                  ),
                                ],
                              );
                              return signed.single.url;
                            }),
                          ),
                        );
                      },
                      child: Text(l10n.formReportOpen),
                    ),
                  ],
                ),
              if (canAttach) ...[
                const SizedBox(height: RealestySpacing.sm),
                Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: RealestyTextField(
                        label: l10n.formReportPages,
                        controller: _pages,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: RealestySpacing.md),
                    RealestyButton(
                      label: l10n.formReportChoose,
                      expand: false,
                      isLoading: _uploading,
                      leadingIcon: RealestyIcons.upload,
                      onPressed: _upload,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
