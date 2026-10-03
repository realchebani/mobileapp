import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/team/cubit/team_cubit.dart';
import 'package:realesty_backoffice/team/view/member_dialog.dart';
import 'package:realesty_ui/realesty_ui.dart';

class TeamPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = TeamCubit(repository: context.read());
        unawaited(
          cubit.load().catchError(context.read<SessionCubit>().onFailure),
        );
        return cubit;
      },
      child: const TeamView(),
    );
  }
}

class TeamView extends StatelessWidget {
  const new({super.key});

  static String _mfa(AppLocalizations l10n, StaffMember m) =>
      m.mfaEnrolled ? l10n.teamMfaOn : l10n.teamMfaOff;

  Future<void> _edit(BuildContext context, [StaffMember? member]) async {
    final l10n = context.l10n;
    final cubit = context.read<TeamCubit>();
    final result = await showDialog<MemberForm>(
      context: context,
      builder: (_) => MemberDialog(member: member),
    );
    if (result == null || !context.mounted) return;
    await runGuarded(
      context,
      () => cubit.upsert(
        email: result.email,
        role: result.role,
        displayName: result.displayName,
        initials: result.initials,
        organisation: result.organisation,
      ),
      success: l10n.teamSaved,
    );
  }

  Future<void> _deactivate(BuildContext context, StaffMember member) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.teamDeactivateTitle(member.displayName)),
        content: Text(l10n.teamDeactivateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.teamDeactivate),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<TeamCubit>().deactivate(member.userId),
      success: l10n.teamDeactivated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<TeamCubit>().state;
    final myId = context.select<SessionCubit, String?>(
      (s) => s.state.me?.userId,
    );
    return ListView(
      padding: const EdgeInsets.all(RealestySpacing.xxl),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.teamTitle, style: RealestyTextStyles.title1),
                  Text(
                    l10n.teamSubtitle,
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.encre2,
                    ),
                  ),
                ],
              ),
            ),
            RealestyButton(
              label: l10n.teamAdd,
              expand: false,
              leadingIcon: RealestyIcons.plus,
              onPressed: () => _edit(context),
            ),
          ],
        ),
        const SizedBox(height: RealestySpacing.lg),
        switch (state.status) {
          TeamStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          TeamStatus.failure => BoMessage(
            icon: RealestyIcons.warning,
            title: l10n.teamError,
            action: RealestyButton(
              label: l10n.retry,
              expand: false,
              onPressed: () =>
                  runGuarded(context, context.read<TeamCubit>().load),
            ),
          ),
          TeamStatus.ready when state.members.isEmpty => BoMessage(
            title: l10n.teamEmpty,
          ),
          TeamStatus.ready => BoCard(
            child: Column(
              children: [
                for (final m in state.members)
                  FieldRow(
                    label: [m.displayName, ?m.email].join('\n'),
                    value: [
                      m.role.label(l10n),
                      ?m.organisation,
                      '${l10n.teamColMfa} : ${_mfa(l10n, m)}',
                      '${l10n.teamColAssignments} : ${m.activeAssignments}',
                    ].join(' · '),
                    tags: [
                      if (m.active)
                        BoChip(
                          l10n.teamActive,
                          color: c.vertTexte,
                          background: c.vertTeinte,
                        )
                      else
                        BoChip(
                          l10n.teamInactive(
                            m.deactivatedAt == null
                                ? ''
                                : dateFr(m.deactivatedAt!),
                          ),
                        ),
                      TextButton(
                        onPressed: () => _edit(context, m),
                        child: Text(l10n.teamEdit),
                      ),
                      if (m.active && m.userId != myId)
                        TextButton(
                          onPressed: () => _deactivate(context, m),
                          child: Text(l10n.teamDeactivate),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        },
      ],
    );
  }
}
