import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/cubit/notification_preference_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/data/notification_preference_store.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/ai_estimate_card.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_format.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V8 · Attente de validation expert: confirmation once the dossier is
/// sent, AI trend (when computed), expert review timeline (from `status`
/// and `submitted_at`) and notification preference. Read-only: works for
/// submitted, in_review and certified dossiers.
class SubmittedPage extends StatelessWidget {
  const new({this.notificationStore, super.key});

  /// Where the notification choice is kept (device preferences by default).
  final NotificationPreferenceStore? notificationStore;

  @override
  Widget build(BuildContext context) {
    final tunnel = context.read<SellerTunnelCubit>();
    final property = tunnel.state.property!;
    // The dossier can only be written while it is open (RLS); once locked,
    // the device preference is the only record of the choice.
    final isOpen =
        property.status == PropertyStatus.draft ||
        property.status == PropertyStatus.submitted;
    return BlocProvider(
      create: (_) {
        final cubit = NotificationPreferenceCubit(
          store: notificationStore ?? NotificationPreferenceStore(),
          propertyId: property.id,
          initialValue: property.notifyPush,
          saveRemote: isOpen
              ? ({required enabled}) async {
                  // A failure shows the tunnel save-error snackbar
                  // (SellerTunnelGate).
                  await tunnel.save({PropertyColumns.notifyPush: enabled});
                  return tunnel.state.saveStatus ==
                      SellerTunnelSaveStatus.success;
                }
              : null,
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const SubmittedView(),
    );
  }
}

class SubmittedView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<SellerTunnelCubit>().state;
    final property = state.property!;
    final status = property.status;
    final low = property.aiEstimateLowEur;
    final median = property.aiEstimateMedianEur;
    final high = property.aiEstimateHighEur;
    return TunnelScaffold(
      spacing: 14,
      actionBar: _ActionBar(
        onSummary: () => showDossierSummarySheet(context, state),
      ),
      children: [
        _Hero(state: state),
        if (status != PropertyStatus.certified &&
            low != null &&
            median != null &&
            high != null)
          AiEstimateCard(
            low: low,
            median: median,
            high: high,
            computedAt: property.aiEstimateComputedAt,
          ),
        _Card(child: SubmittedTimeline(entries: _timeline(l10n, property))),
        if (status == PropertyStatus.submitted ||
            status == PropertyStatus.inReview)
          _NotificationRow(email: _email(context, state)),
      ],
    );
  }

  static String? _email(BuildContext context, SellerTunnelState state) {
    for (final owner in state.owners) {
      if (owner.position == 1 && (owner.email?.isNotEmpty ?? false)) {
        return owner.email;
      }
    }
    return context.read<AppBloc>().state.user?.email;
  }

  static List<TimelineEntry> _timeline(
    AppLocalizations l10n,
    Property property,
  ) {
    const done = TimelineNodeState.done;
    const current = TimelineNodeState.current;
    const todo = TimelineNodeState.todo;
    final submittedAt = property.submittedAt;
    final sent = submittedAt == null
        ? l10n.submittedStepCompleteSentNoDate
        : l10n.submittedStepCompleteSent(
            dayMonth(submittedAt),
            timeOfDay(l10n, submittedAt),
          );
    final (complete, review, certified) = switch (property.status) {
      PropertyStatus.draft => (current, todo, todo),
      PropertyStatus.submitted ||
      PropertyStatus.inReview => (done, current, todo),
      PropertyStatus.certified => (done, done, done),
    };
    return [
      TimelineEntry(
        title: l10n.submittedStepComplete,
        subtitle: property.status == PropertyStatus.draft
            ? l10n.submittedStepCompleteDraft
            : sent,
        state: complete,
      ),
      TimelineEntry(
        title: l10n.submittedStepReview,
        subtitle: switch (property.status) {
          PropertyStatus.inReview => l10n.submittedStepReviewInProgress,
          PropertyStatus.certified => l10n.submittedStepReviewDone,
          PropertyStatus.draft ||
          PropertyStatus.submitted => l10n.submittedStepReviewEstimate,
        },
        state: review,
      ),
      TimelineEntry(
        title: l10n.submittedStepCertified,
        subtitle: certified == done
            ? l10n.submittedStepCertifiedDone
            : l10n.submittedStepCertifiedTodo,
        state: certified,
      ),
    ];
  }
}

class _Hero extends StatelessWidget {
  const new({required this.state});

  final SellerTunnelState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final status = state.property!.status;
    String? firstName;
    for (final owner in state.owners) {
      if (owner.position == 1 && owner.firstName.trim().isNotEmpty) {
        firstName = owner.firstName.trim();
      }
    }
    final title = status == PropertyStatus.draft
        ? l10n.submittedTitleDraft
        : status == PropertyStatus.certified
        ? l10n.submittedTitleCertified
        : firstName == null
        ? l10n.submittedTitleNoName
        : l10n.submittedTitle(firstName);
    final intro = switch (status) {
      PropertyStatus.draft => l10n.submittedIntroDraft,
      PropertyStatus.submitted => l10n.submittedIntroSubmitted,
      PropertyStatus.inReview => l10n.submittedIntroInReview,
      PropertyStatus.certified => l10n.submittedIntroCertified,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RealestySpacing.xxs,
        RealestySpacing.xl,
        RealestySpacing.xxs,
        RealestySpacing.xs,
      ),
      child: Column(
        spacing: 14,
        children: [
          Container(
            width: 96,
            height: 96,
            margin: const EdgeInsets.only(bottom: RealestySpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.vertTeinte,
              boxShadow: [
                BoxShadow(
                  color: c.vert.withValues(alpha: 0.12),
                  spreadRadius: 12,
                ),
              ],
            ),
            child: RealestyIcon(
              status == PropertyStatus.draft
                  ? RealestyIcons.file
                  : RealestyIcons.check,
              size: 44,
              color: c.vertTexte,
            ),
          ),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: RealestyTextStyles.title1.copyWith(
                fontSize: 24,
                height: 1.2,
                color: c.encre,
              ),
            ),
          ),
          Text(
            intro,
            textAlign: TextAlign.center,
            style: RealestyTextStyles.body.copyWith(
              fontSize: 15,
              height: 1.5,
              color: c.texteDiscret,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: child,
    );
  }
}

/// "Me prévenir par notification": a device preference in v1 (no push
/// notifications yet), see `NotificationPreferenceStore`.
class _NotificationRow extends StatelessWidget {
  const new({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final enabled = context.watch<NotificationPreferenceCubit>().state;
    final email = this.email;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: RealestySpacing.minTouchTarget,
        ),
        child: Row(
          spacing: RealestySpacing.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.submittedNotifyTitle,
                    style: RealestyTextStyles.listTitle.copyWith(
                      color: c.encre,
                    ),
                  ),
                  if (email != null && email.isNotEmpty)
                    Text(
                      l10n.submittedNotifyEmail(email),
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (value) => context
                  .read<NotificationPreferenceCubit>()
                  .toggled(enabled: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const new({required this.onSummary});

  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ColoredBox(
      color: context.realestyColors.ivoire,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: RealestySpacing.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            14,
            RealestySpacing.gutter,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              RealestyButton(
                label: l10n.submittedBackToDossier,
                onPressed: context.leaveTunnel,
              ),
              // Text button that wraps (RealestyButton keeps one line) so
              // the label stays whole with large text sizes.
              RealestyPressable(
                onPressed: onSummary,
                semanticLabel: l10n.submittedSummaryButton,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: RealestySpacing.minTouchTarget,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RealestySpacing.md,
                        vertical: RealestySpacing.xxs,
                      ),
                      child: Text(
                        l10n.submittedSummaryButton,
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.button.copyWith(
                          color: context.realestyColors.vertTexte,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
