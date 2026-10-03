import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';

/// Actions on this dossier (admin: all; others: their own).
class JournalTab extends StatefulWidget {
  const new({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<DossierCubit>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => mounted ? runGuarded(context, cubit.loadAudit) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = context.select<DossierCubit, List<AuditEntry>?>(
      (cubit) => cubit.state.audit,
    );
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) return BoMessage(title: l10n.journalNone);
    return BoCard(
      child: Column(
        children: [
          for (final entry in entries)
            FieldRow(
              label: dateTimeFr(entry.at),
              value:
                  '${auditActionLabel(l10n, entry.action)} · '
                  '${auditActorLabel(l10n, entry)}',
              detail: entry.details.isEmpty ? null : compactJson(entry.details),
            ),
        ],
      ),
    );
  }
}
