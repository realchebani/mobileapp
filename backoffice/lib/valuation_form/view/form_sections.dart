import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/valuation_form/cubit/valuation_form_cubit.dart';
import 'package:realesty_backoffice/valuation_form/widgets/error_text.dart';
import 'package:realesty_backoffice/valuation_form/widgets/form_input.dart';
import 'package:realesty_backoffice/valuation_form/widgets/list_editor.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// The sections of the valuation, mirroring the tabs of V9b.
class FormSections extends StatelessWidget {
  const new({required this.dossier, required this.enabled, super.key});

  final Dossier dossier;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<ValuationFormCubit>().state;
    final cubit = context.read<ValuationFormCubit>();
    final p = state.payload;
    final errors = state.visibleErrors;
    final canPickSigner = context.select<SessionCubit, bool>(
      (s) => s.state.me?.can(BackOfficeCapability.assign) ?? false,
    );

    Widget input(
      String key,
      String label, {
      InputKind kind = InputKind.text,
      int maxLines = 1,
    }) => FormInput(
      label: label,
      value: p[key],
      kind: kind,
      maxLines: maxLines,
      enabled: enabled,
      error: errorAt(l10n, errors, key),
      onChanged: (value) => cubit.setField(key, value),
    );

    Widget list(
      String key,
      String title,
      List<ListColumn> columns, {
      JsonMap newItem = const {},
      Widget? action,
    }) => ListEditor(
      listKey: key,
      title: title,
      columns: columns,
      items: Json.maps(p[key]),
      errors: errors,
      newItem: newItem,
      enabled: enabled,
      action: action,
      onChanged: (items) => cubit.setField(key, items),
    );

    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: RealestySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final child in children) ...[
            Expanded(child: child),
            if (child != children.last)
              const SizedBox(width: RealestySpacing.md),
          ],
        ],
      ),
    );

    const gap = SizedBox(height: RealestySpacing.lg);
    final market = dossier.market;
    final aiTrend = Json.integer(dossier.property['ai_estimate_median_eur']);
    final provenances = {
      'declared': l10n.provDeclared,
      'document': l10n.provDocument,
      'external': l10n.provExternal,
      'verified': l10n.provVerified,
    };
    final kinds = {
      'base': l10n.kindBase,
      'line': l10n.kindLine,
      'total': l10n.kindTotal,
      'control': l10n.kindControl,
    };
    final amountLines = [
      ListColumn('label', l10n.formColLabel, flex: 4),
      ListColumn('amount_eur', l10n.formColAmount, kind: InputKind.integer),
      ListColumn('kind', l10n.formColKind, choices: kinds),
    ];
    final mismatch = adjustmentsMismatch(Json.maps(p['adjustments']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoCard(
          title: l10n.formSectionValue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row([
                input('value_eur', l10n.formValue, kind: InputKind.integer),
                input('low_eur', l10n.formLow, kind: InputKind.integer),
                input('high_eur', l10n.formHigh, kind: InputKind.integer),
              ]),
              row([
                input(
                  'price_m2_eur',
                  l10n.formPriceM2,
                  kind: InputKind.integer,
                ),
                input(
                  'estimated_delay_weeks',
                  l10n.formDelay,
                  kind: InputKind.integer,
                ),
                input('valid_until', l10n.formValidUntil),
              ]),
              Text(
                [
                  if (aiTrend != null) l10n.formAiTrend(euros(aiTrend)),
                  if (Json.integer(market?['estimate_low_eur'])
                      case final int low)
                    l10n.formDvfRange(
                      euros(low),
                      euros(Json.integer(market?['estimate_high_eur']) ?? low),
                    ),
                ].join(' · '),
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
            ],
          ),
        ),
        gap,
        BoCard(
          title: l10n.formSectionExpert,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPickSigner)
                Padding(
                  padding: const EdgeInsets.only(bottom: RealestySpacing.sm),
                  child: SizedBox(
                    width: 420,
                    child: SignatoryPicker(
                      value: p['expert_user_id'] as String?,
                      enabled: enabled,
                      onChanged: (id) => cubit.setField('expert_user_id', id),
                    ),
                  ),
                )
              else
                Text(l10n.formSignedByDefault, style: RealestyTextStyles.label),
              if (errorAt(l10n, errors, 'expert_user_id') case final String e)
                Text(e, style: TextStyle(color: c.erreur)),
              Text(
                l10n.formExpertHint,
                style: RealestyTextStyles.bodySmall.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ],
          ),
        ),
        gap,
        BoCard(
          title: l10n.formSectionSummary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              list('method_steps', l10n.formMethodSteps, [
                ListColumn('label', l10n.formColLabel, flex: 3),
                ListColumn('detail', l10n.formColDetail, flex: 3),
                ListColumn(
                  'amount_eur',
                  l10n.formColAmount,
                  kind: InputKind.integer,
                ),
                ListColumn('is_delta', l10n.formColDelta, isBool: true),
              ]),
              gap,
              list(
                'reasons',
                l10n.formReasons,
                [
                  ListColumn('text', l10n.formColText, flex: 6),
                  ListColumn('positive', l10n.formColPositive, isBool: true),
                ],
                newItem: const {'positive': true},
              ),
              gap,
              list('delay_curve', l10n.formDelayCurve, [
                ListColumn(
                  'price_eur',
                  l10n.formColPrice,
                  kind: InputKind.integer,
                ),
                ListColumn('label', l10n.formColLabel, flex: 3),
              ]),
              gap,
              input('expert_quote', l10n.formQuote, maxLines: 4),
            ],
          ),
        ),
        gap,
        BoCard(
          title: l10n.formSectionProperty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              input('description', l10n.formDescription, maxLines: 5),
              gap,
              list(
                'technical_sheet',
                l10n.formTechnicalSheet,
                [
                  ListColumn('label', l10n.formColLabel, flex: 3),
                  ListColumn('value', l10n.formColValue, flex: 4),
                  ListColumn(
                    'provenance',
                    l10n.formColProvenance,
                    choices: provenances,
                  ),
                ],
                newItem: const {'provenance': 'verified'},
                action: TextButton(
                  onPressed: enabled
                      ? () => cubit.setField(
                          'technical_sheet',
                          technicalSheetFrom(dossier),
                        )
                      : null,
                  child: Text(l10n.formPrefillSheet),
                ),
              ),
            ],
          ),
        ),
        gap,
        BoCard(
          title: l10n.formSectionSector,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              list(
                'comparables',
                l10n.formComparables,
                [
                  ListColumn('street', l10n.formColStreet, flex: 4),
                  ListColumn('sold_on', l10n.formColSoldOn, flex: 3),
                  ListColumn(
                    'area_m2',
                    l10n.formColArea,
                    kind: InputKind.number,
                  ),
                  ListColumn(
                    'land_m2',
                    l10n.formColLand,
                    kind: InputKind.integer,
                  ),
                  ListColumn(
                    'price_eur',
                    l10n.formColPrice,
                    kind: InputKind.integer,
                  ),
                  ListColumn('excluded', l10n.formColExcluded, isBool: true),
                ],
                action: TextButton(
                  onPressed: enabled && comparablesFrom(dossier).isNotEmpty
                      ? () => cubit.setField(
                          'comparables',
                          comparablesFrom(dossier),
                        )
                      : null,
                  child: Text(l10n.formImportDvf),
                ),
              ),
              gap,
              input('comparables_note', l10n.formComparablesNote, maxLines: 2),
              gap,
              input('competitors_summary', l10n.formCompetitorsSummary),
              gap,
              list(
                'competitors',
                l10n.formCompetitors,
                [
                  ListColumn('label', l10n.formColLabel, flex: 3),
                  ListColumn(
                    'price_eur',
                    l10n.formColPrice,
                    kind: InputKind.integer,
                  ),
                  ListColumn('note', l10n.formColNote, flex: 3),
                  ListColumn(
                    'days_online',
                    l10n.formColDays,
                    kind: InputKind.integer,
                  ),
                  ListColumn('retained', l10n.formColRetained, isBool: true),
                ],
                newItem: const {'retained': true},
              ),
              gap,
              input('risks_note', l10n.formRisks, maxLines: 2),
            ],
          ),
        ),
        gap,
        BoCard(
          title: l10n.formSectionPrice,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              list('adjustments', l10n.formAdjustments, amountLines),
              if (mismatch != null)
                InlineBanner(
                  message: l10n.formAdjustmentsMismatch(
                    euros(mismatch.$1),
                    euros(mismatch.$2),
                  ),
                ),
              gap,
              list('method_summary', l10n.formMethodSummary, amountLines),
              gap,
              row([
                input('works_label', l10n.formWorksLabel),
                input(
                  'works_estimate_eur',
                  l10n.formWorksEstimate,
                  kind: InputKind.integer,
                ),
              ]),
              input('sources', l10n.formSources, maxLines: 2),
            ],
          ),
        ),
      ],
    );
  }
}

/// (sum of the base and adjustment lines, first total) when they differ.
(int, int)? adjustmentsMismatch(List<JsonMap> lines) {
  var sum = 0;
  int? total;
  for (final line in lines) {
    final amount = line['amount_eur'];
    if (amount is! int) continue;
    switch (line['kind']) {
      case 'total':
        total ??= amount;
      case 'control':
        break;
      case _:
        sum += amount;
    }
  }
  return total == null || total == sum ? null : (sum, total);
}

/// Admin: the member who signs the report (« rapport saisi pour »).
class SignatoryPicker extends StatefulWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  State<SignatoryPicker> createState() => _SignatoryPickerState();
}

class _SignatoryPickerState extends State<SignatoryPicker> {
  List<StaffMember> _team = const [];

  @override
  void initState() {
    super.initState();
    final repository = context.read<BackOfficeRepository>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await runGuarded(context, () async {
        final team = await repository.listTeam();
        if (mounted) {
          setState(
            () => _team = [
              for (final m in team)
                if (m.active) m,
            ],
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final known = _team.any((m) => m.userId == widget.value);
    return DropdownButtonFormField<String?>(
      key: ValueKey('signer-${_team.length}-${widget.value}'),
      initialValue: known ? widget.value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.formExpertFor),
      items: [
        DropdownMenuItem(child: Text(l10n.formExpertSelf)),
        for (final member in _team)
          DropdownMenuItem(
            value: member.userId,
            child: Text('${member.displayName} · ${member.role.label(l10n)}'),
          ),
      ],
      onChanged: widget.enabled ? widget.onChanged : null,
    );
  }
}
