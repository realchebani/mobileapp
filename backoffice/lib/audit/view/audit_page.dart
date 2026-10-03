import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/audit/csv.dart';
import 'package:realesty_backoffice/audit/cubit/audit_cubit.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Actions of the journal (`bo_audit` codes).
const auditActions = [
  'dossier_opened',
  'file_signed',
  'review_started',
  'assigned',
  'unassigned',
  'draft_saved',
  'submitted_for_approval',
  'draft_returned',
  'certified',
  'report_upload_signed',
  'report_attached',
  'document_verified',
  'document_rejected',
  'identity_verified',
  'member_added',
  'member_updated',
  'member_deactivated',
];

class AuditPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = AuditCubit(repository: context.read());
        final session = context.read<SessionCubit>();
        unawaited(cubit.load().catchError(session.onFailure));
        unawaited(cubit.loadTeam().catchError(session.onFailure));
        return cubit;
      },
      child: const AuditView(),
    );
  }
}

class AuditView extends StatefulWidget {
  const new({super.key});

  @override
  State<AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<AuditView> {
  final _dossier = TextEditingController();
  final _since = TextEditingController();
  final _until = TextEditingController();
  String? _actor;
  String? _action;
  bool _invalidDate = false;

  @override
  void dispose() {
    _dossier.dispose();
    _since.dispose();
    _until.dispose();
    super.dispose();
  }

  static DateTime? _day(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final date = DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    return date.month == int.parse(match[2]!) ? date : null;
  }

  void _apply() {
    final since = _since.text.trim().isEmpty ? null : _day(_since.text);
    final until = _until.text.trim().isEmpty ? null : _day(_until.text);
    final invalid =
        (_since.text.trim().isNotEmpty && since == null) ||
        (_until.text.trim().isNotEmpty && until == null);
    setState(() => _invalidDate = invalid);
    if (invalid) return;
    final cubit = context.read<AuditCubit>();
    unawaited(
      runGuarded(
        context,
        () => cubit.load(
          AuditFilters(
            actorUserId: _actor,
            action: _action,
            propertyId: _dossier.text.trim().isEmpty
                ? null
                : _dossier.text.trim(),
            since: since,
            until: until,
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    final l10n = context.l10n;
    final entries = context.read<AuditCubit>().state.entries;
    final now = DateTime.now();
    final stamp =
        '${now.year}${'${now.month}'.padLeft(2, '0')}'
        '${'${now.day}'.padLeft(2, '0')}';
    await runGuarded(
      context,
      () => context.read<Browser>().saveText(
        'journal-realesty-$stamp.csv',
        auditCsv(l10n, entries),
      ),
      success: l10n.auditExported(entries.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<AuditCubit>().state;
    Widget labeled(String label, Widget child, {int flex = 2}) => Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RealestyTextStyles.label),
          const SizedBox(height: RealestySpacing.xs),
          child,
        ],
      ),
    );
    const gap = SizedBox(width: RealestySpacing.sm);
    return ListView(
      padding: const EdgeInsets.all(RealestySpacing.xxl),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.auditTitle, style: RealestyTextStyles.title1),
                  Text(
                    '${l10n.auditSubtitle} ${l10n.auditLimit}',
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.encre2,
                    ),
                  ),
                ],
              ),
            ),
            RealestyButton(
              label: l10n.auditExport,
              expand: false,
              variant: RealestyButtonVariant.secondary,
              leadingIcon: RealestyIcons.download,
              onPressed: state.entries.isEmpty ? null : _export,
            ),
          ],
        ),
        const SizedBox(height: RealestySpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            labeled(
              l10n.auditFilterActor,
              DropdownButtonFormField<String?>(
                key: ValueKey('actor-${state.team.length}'),
                initialValue: _actor,
                isExpanded: true,
                items: [
                  DropdownMenuItem(child: Text(l10n.auditAll)),
                  for (final m in state.team)
                    DropdownMenuItem(
                      value: m.userId,
                      child: Text(m.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _actor = value),
              ),
            ),
            gap,
            labeled(
              l10n.auditFilterAction,
              DropdownButtonFormField<String?>(
                initialValue: _action,
                isExpanded: true,
                items: [
                  DropdownMenuItem(child: Text(l10n.auditAll)),
                  for (final action in auditActions)
                    DropdownMenuItem(
                      value: action,
                      child: Text(auditActionLabel(l10n, action)),
                    ),
                ],
                onChanged: (value) => setState(() => _action = value),
              ),
            ),
            gap,
            Expanded(
              flex: 3,
              child: RealestyTextField(
                label: l10n.auditFilterDossier,
                controller: _dossier,
              ),
            ),
            gap,
            Expanded(
              flex: 2,
              child: RealestyTextField(
                label: l10n.auditFilterSince,
                controller: _since,
              ),
            ),
            gap,
            Expanded(
              flex: 2,
              child: RealestyTextField(
                label: l10n.auditFilterUntil,
                controller: _until,
              ),
            ),
            gap,
            RealestyButton(
              label: l10n.auditApply,
              expand: false,
              onPressed: _apply,
            ),
          ],
        ),
        if (_invalidDate) ...[
          const SizedBox(height: RealestySpacing.sm),
          InlineBanner(message: l10n.auditInvalidDate),
        ],
        const SizedBox(height: RealestySpacing.lg),
        switch (state.status) {
          AuditStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          AuditStatus.failure => BoMessage(
            icon: RealestyIcons.warning,
            title: l10n.auditError,
          ),
          AuditStatus.ready when state.entries.isEmpty => BoMessage(
            title: l10n.auditEmpty,
          ),
          AuditStatus.ready => BoCard(
            child: Column(
              children: [
                for (final e in state.entries)
                  FieldRow(
                    label: dateTimeFr(e.at),
                    value:
                        '${auditActionLabel(l10n, e.action)} · '
                        '${auditActorLabel(l10n, e)}',
                    detail: [
                      ?e.propertyId,
                      if (e.details.isNotEmpty)
                        compactJson(e.details, display: true),
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        },
      ],
    );
  }
}
