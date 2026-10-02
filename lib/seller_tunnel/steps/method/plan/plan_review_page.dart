import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_reading_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// What the seller decided on the plan review.
sealed class PlanReviewResult {
  const new();
}

/// Add these rooms to V5c.
final class PlanReviewAccepted extends PlanReviewResult {
  const new(this.rooms);

  final List<RoomInput> rooms;
}

/// Type the rooms instead ("Saisir mes pièces").
final class PlanReviewManual extends PlanReviewResult {
  const new();
}

/// Opens the review of [reading] (full screen); null when the seller goes
/// back.
Future<PlanReviewResult?> showPlanReview(
  BuildContext context,
  PlanReading reading,
) {
  return Navigator.of(context).push<PlanReviewResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlanReviewPage(reading: reading),
    ),
  );
}

class _Line {
  new(PlanRoom room)
    : input = PlanReadingCubit.inputOf(room),
      name = TextEditingController(text: room.name),
      area = TextEditingController(
        text: room.areaM2 == null ? '' : RoomArea.input(room.areaM2!),
      ),
      level = room.level;

  final RoomInput input;
  final TextEditingController name;
  final TextEditingController area;
  final GlobalKey key = GlobalKey();
  RoomLevel? level;
  bool keep = true;

  void dispose() {
    name.dispose();
    area.dispose();
  }
}

/// EPIC-15 · V5 « Pièces lues sur le plan »: every room the vision AI read
/// on the plan, to keep or not and correct (name, level, area) line by
/// line; the printed total compared with the sum. Only printed areas were
/// read: a missing one must be typed (or the line unticked).
class PlanReviewPage extends StatefulWidget {
  const new({required this.reading, super.key});

  final PlanReading reading;

  @override
  State<PlanReviewPage> createState() => _PlanReviewPageState();
}

class _PlanReviewPageState extends State<PlanReviewPage> {
  late final List<_Line> _lines = [
    for (final room in widget.reading.rooms) _Line(room),
  ];
  bool _submitted = false;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String? _nameError(_Line line) =>
      line.name.text.trim().isEmpty ? context.l10n.surfacesErrorName : null;

  String? _areaError(_Line line) {
    final l10n = context.l10n;
    final area = RoomArea.parse(line.area.text);
    if (area == null) return l10n.planReviewAreaMissing;
    if (area < RoomArea.min || area > RoomArea.max) {
      return l10n.surfacesErrorAreaRange(
        RoomArea.input(RoomArea.min),
        RoomArea.input(RoomArea.max),
      );
    }
    return null;
  }

  bool _valid(_Line line) =>
      !line.keep || (_nameError(line) == null && _areaError(line) == null);

  void _submit() {
    final invalid = _lines.where((line) => !_valid(line)).toList();
    if (invalid.isNotEmpty) {
      setState(() => _submitted = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = invalid.first.key.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: RealestyMotion.page,
            alignment: 0.1,
          );
        }
      });
      return;
    }
    Navigator.of(context).pop(
      PlanReviewAccepted([
        for (final line in _lines)
          if (line.keep)
            RoomInput(
              name: line.name.text.trim(),
              level: line.level,
              areaM2: RoomArea.round(RoomArea.parse(line.area.text)!),
              isMain: line.input.isMain,
              isAnnex: line.input.isAnnex,
            ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final reading = widget.reading;
    final kept = _lines.where((line) => line.keep).length;
    final sum = RoomArea.round(
      _lines
          .where((line) => line.keep)
          .fold(0, (sum, line) => sum + (RoomArea.parse(line.area.text) ?? 0)),
    );
    final printed = reading.printedTotalM2;
    final empty = _lines.isEmpty;
    return TunnelScaffold(
      spacing: 14,
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            10,
            RealestySpacing.gutter,
            RealestySpacing.xs,
          ),
          child: Row(
            spacing: RealestySpacing.xs,
            children: [
              RealestyIconButton(
                icon: RealestyIcons.chevronLeft,
                semanticLabel: l10n.planReviewBack,
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.planReviewTitle,
                    style: RealestyTextStyles.title2.copyWith(color: c.encre),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actionBar: empty
          ? AgentActionBar(
              label: l10n.planReviewManual,
              onPressed: () =>
                  Navigator.of(context).pop(const PlanReviewManual()),
            )
          : AgentActionBar(
              label: l10n.planReviewAdd(kept),
              onPressed: kept == 0 ? null : _submit,
            ),
      children: [
        AgentIntro(
          message: !reading.isFloorPlan
              ? l10n.planReviewNotPlan
              : empty
              ? l10n.planReviewEmpty
              : l10n.planReviewIntro,
        ),
        if (!empty && printed != null)
          InlineBanner(
            message: (sum - printed).abs() <= printed * 0.05
                ? l10n.planReviewTotalMatch(RoomArea.format(printed))
                : l10n.planReviewTotalMismatch(
                    RoomArea.format(sum),
                    RoomArea.format(printed),
                  ),
            variant: (sum - printed).abs() <= printed * 0.05
                ? InlineBannerVariant.info
                : InlineBannerVariant.warning,
            icon: RealestyIcons.plan,
          ),
        for (final line in _lines)
          _LineCard(
            key: line.key,
            line: line,
            nameError: _submitted && line.keep ? _nameError(line) : null,
            areaError: _submitted && line.keep ? _areaError(line) : null,
            onChanged: () => setState(() {}),
          ),
        if (!empty)
          RealestyButton(
            label: l10n.planReviewManual,
            variant: RealestyButtonVariant.text,
            onPressed: () =>
                Navigator.of(context).pop(const PlanReviewManual()),
          ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const new({
    required this.line,
    required this.onChanged,
    this.nameError,
    this.areaError,
    super.key,
  });

  final _Line line;
  final VoidCallback onChanged;
  final String? nameError;
  final String? areaError;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: line.keep ? c.bordureCarte : c.ligne),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Expanded(
                child: RealestyCheckbox(
                  value: line.keep,
                  label: l10n.planReviewKeep(line.name.text.trim()),
                  onChanged: (value) {
                    line.keep = value;
                    onChanged();
                  },
                ),
              ),
              const ProvenanceTag(ProvenanceKind.document),
            ],
          ),
          if (line.keep) ...[
            RealestyTextField(
              label: l10n.planReviewNameLabel,
              controller: line.name,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              onChanged: (_) => onChanged(),
              errorText: nameError,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: RealestySpacing.xs,
              children: [
                Expanded(
                  child: RealestyTextField(
                    label: l10n.planReviewAreaLabel,
                    controller: line.area,
                    suffixText: 'm²',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    errorText: areaError,
                  ),
                ),
                Expanded(
                  child: RealestySelect<RoomLevel>(
                    label: l10n.planReviewLevelLabel,
                    value: line.level,
                    hint: l10n.surfacesNotSpecified,
                    options: [
                      for (final level in RoomLevel.values)
                        RealestySelectOption(
                          value: level,
                          label: level.label(l10n),
                        ),
                    ],
                    onChanged: (level) {
                      line.level = level;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
