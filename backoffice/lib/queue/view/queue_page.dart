import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/queue/cubit/queue_cubit.dart';
import 'package:realesty_backoffice/queue/widgets/assign_dialog.dart';
import 'package:realesty_backoffice/queue/widgets/queue_table.dart';
import 'package:realesty_ui/realesty_ui.dart';

class QueuePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = QueueCubit(repository: context.read());
        final session = context.read<SessionCubit>();
        unawaited(cubit.load().catchError(session.onFailure));
        return cubit;
      },
      child: const QueueView(),
    );
  }
}

class QueueView extends StatelessWidget {
  const new({super.key});

  Future<void> _assign(BuildContext context, DossierSummary row) async {
    final cubit = context.read<QueueCubit>();
    final l10n = context.l10n;
    await runGuarded(context, cubit.loadTeam);
    if (!context.mounted) return;
    final choice = await showAssignDialog(
      context,
      team: cubit.state.team,
      current: row.assignedTo?.userId,
    );
    if (choice == null || !context.mounted) return;
    if (choice.userId == null) {
      await runGuarded(
        context,
        () => cubit.unassign(row.id),
        success: l10n.queueUnassignedDone,
      );
      return;
    }
    final name = cubit.state.team
        .firstWhere((m) => m.userId == choice.userId)
        .displayName;
    await runGuarded(
      context,
      () => cubit.assign(row.id, choice.userId!, note: choice.note),
      success: l10n.queueAssigned(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<QueueCubit>().state;
    final cubit = context.read<QueueCubit>();
    final me = context.select<SessionCubit, StaffMe?>((s) => s.state.me);
    final seesAll = me?.can(BackOfficeCapability.queueAll) ?? false;

    return ListView(
      padding: const EdgeInsets.all(RealestySpacing.xxl),
      children: [
        Text(l10n.queueTitle, style: RealestyTextStyles.title1),
        const SizedBox(height: RealestySpacing.xxs),
        Text(
          l10n.queueSubtitle,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        const SizedBox(height: RealestySpacing.lg),
        Wrap(
          spacing: RealestySpacing.md,
          runSpacing: RealestySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 520,
              child: RealestySegmentedControl<QueueFilter>(
                segments: [
                  RealestySegment(
                    value: QueueFilter.open,
                    label: l10n.queueFilterOpen,
                  ),
                  RealestySegment(
                    value: QueueFilter.submitted,
                    label: l10n.queueFilterSubmitted,
                  ),
                  RealestySegment(
                    value: QueueFilter.inReview,
                    label: l10n.queueFilterInReview,
                  ),
                  RealestySegment(
                    value: QueueFilter.certified,
                    label: l10n.queueFilterCertified,
                  ),
                  RealestySegment(
                    value: QueueFilter.all,
                    label: l10n.queueFilterAll,
                  ),
                ],
                selected: state.filter,
                onChanged: (f) => runGuarded(context, () => cubit.setFilter(f)),
              ),
            ),
            if (seesAll)
              SizedBox(
                width: 420,
                child: RealestySegmentedControl<DossierScope>(
                  segments: [
                    RealestySegment(
                      value: DossierScope.all,
                      label: l10n.queueScopeAll,
                    ),
                    RealestySegment(
                      value: DossierScope.mine,
                      label: l10n.queueScopeMine,
                    ),
                    RealestySegment(
                      value: DossierScope.unassigned,
                      label: l10n.queueScopeUnassigned,
                    ),
                  ],
                  selected: state.scope,
                  onChanged: (s) =>
                      runGuarded(context, () => cubit.setScope(s)),
                ),
              ),
            SizedBox(
              width: 340,
              child: RealestyTextField(
                label: l10n.queueSearchLabel,
                hint: l10n.queueSearchHint,
                leadingIcon: RealestyIcons.search,
                onSubmitted: (value) =>
                    runGuarded(context, () => cubit.setSearch(value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: RealestySpacing.lg),
        switch (state.status) {
          QueueStatus.loading => const Padding(
            padding: EdgeInsets.all(RealestySpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          QueueStatus.failure => BoMessage(
            icon: RealestyIcons.warning,
            title: l10n.queueError,
            action: RealestyButton(
              label: l10n.retry,
              expand: false,
              onPressed: () => runGuarded(context, cubit.load),
            ),
          ),
          QueueStatus.ready when state.rows.isEmpty => BoMessage(
            title: l10n.queueEmpty,
            body: l10n.queueEmptyBody,
          ),
          QueueStatus.ready => QueueTable(
            rows: state.rows,
            busyId: state.busyId,
            canAssign: me?.can(BackOfficeCapability.assign) ?? false,
            onOpen: (row) => context.go(BoRoutes.dossier(row.id)),
            onTake: (row) => runGuarded(
              context,
              () => cubit.startReview(row.id),
              success: l10n.queueTaken,
            ),
            onAssign: (row) => _assign(context, row),
          ),
        },
        if (state.hasMore) ...[
          const SizedBox(height: RealestySpacing.md),
          Center(
            child: RealestyButton(
              label: l10n.queueMore,
              expand: false,
              variant: RealestyButtonVariant.secondary,
              onPressed: () => runGuarded(context, cubit.loadMore),
            ),
          ),
        ],
      ],
    );
  }
}
