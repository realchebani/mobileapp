import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// State of a [SubmittedTimeline] node.
enum TimelineNodeState { done, current, todo }

/// One step of a [SubmittedTimeline].
class TimelineEntry {
  const new({required this.title, required this.subtitle, required this.state});

  final String title;
  final String subtitle;
  final TimelineNodeState state;
}

/// Vertical stepper of the expert review (V8): 24px nodes (done: filled
/// Vert texte with a check, current: Attention ring with a dot, todo:
/// white with a Ligne ring) joined by 2px connectors, title 15/600 and
/// subtitle 13.
class SubmittedTimeline extends StatelessWidget {
  const new({required this.entries, super.key});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, entry) in entries.indexed)
          _TimelineRow(entry: entry, isLast: index == entries.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const new({required this.entry, required this.isLast});

  final TimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final stateLabel = switch (entry.state) {
      TimelineNodeState.done => l10n.submittedStepStateDone,
      TimelineNodeState.current => l10n.submittedStepStateCurrent,
      TimelineNodeState.todo => l10n.submittedStepStateTodo,
    };
    return Semantics(
      container: true,
      label: '${entry.title}, $stateLabel, ${entry.subtitle}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                spacing: RealestySpacing.xxs,
                children: [
                  _Node(state: entry.state),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        constraints: const BoxConstraints(minHeight: 18),
                        color: entry.state == TimelineNodeState.done
                            ? c.vertTexte
                            : c.ligne,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      entry.title,
                      style: RealestyTextStyles.listTitle.copyWith(
                        color: entry.state == TimelineNodeState.todo
                            ? c.texteDiscret
                            : c.encre,
                      ),
                    ),
                    Text(
                      entry.subtitle,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const new({required this.state});

  final TimelineNodeState state;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          TimelineNodeState.done => c.vertTexte,
          TimelineNodeState.current => c.attentionFond,
          TimelineNodeState.todo => c.surface,
        },
        border: switch (state) {
          TimelineNodeState.done => null,
          TimelineNodeState.current => Border.all(
            color: c.attention,
            width: RealestyBorders.thick,
          ),
          TimelineNodeState.todo => Border.all(
            color: c.ligne,
            width: RealestyBorders.thick,
          ),
        },
      ),
      child: switch (state) {
        TimelineNodeState.done => RealestyIcon(
          RealestyIcons.check,
          size: 14,
          color: c.surface,
        ),
        TimelineNodeState.current => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.attention),
        ),
        TimelineNodeState.todo => null,
      },
    );
  }
}
