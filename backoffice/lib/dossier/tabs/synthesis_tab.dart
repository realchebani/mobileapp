import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/view/dossier_page.dart';
import 'package:realesty_backoffice/dossier/widgets/dossier_labels.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Géoportail with the cadastre over the aerial photo, at [lat], [lng].
String geoportailUrl(double lat, double lng) =>
    'https://www.geoportail.gouv.fr/carte?c=$lng,$lat&z=18'
    '&l0=ORTHOIMAGERY.ORTHOPHOTOS::GEOPORTAIL:OGC:WMTS(1)'
    '&l1=CADASTRALPARCELS.PARCELLAIRE_EXPRESS::GEOPORTAIL:OGC:WMTS(1)'
    '&permalink=yes';

/// Every answer of the tunnel with its provenance, the owners, the rooms,
/// the market snapshot and the certified valuation.
class SynthesisTab extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = dossier.property;
    final lat = Json.number(p['lat']);
    final lng = Json.number(p['lng']);
    final living = Json.number(p['living_area_m2']);
    final annex = Json.number(p['annex_area_m2']);
    final notes = Json.map(p['step_notes']) ?? const {};
    const gap = SizedBox(height: RealestySpacing.lg);
    return Column(
      children: [
        _OwnersCard(dossier: dossier),
        gap,
        BoCard(
          title: l10n.synthLocation,
          trailing: lat == null || lng == null
              ? null
              : TextButton(
                  onPressed: () =>
                      context.read<Browser>().open(geoportailUrl(lat, lng)),
                  child: Text(l10n.synthOpenMap),
                ),
          child: Column(
            children: [
              FieldRow(
                label: l10n.synthAddress,
                value: p['address_label'] as String? ?? '—',
              ),
              for (final parcel in dossier.parcels)
                FieldRow(
                  label: l10n.synthParcels,
                  value: l10n.synthParcel(
                    '${parcel['section'] ?? ''}',
                    '${parcel['numero'] ?? ''}',
                    Json.number(parcel['area_m2']) == null
                        ? '—'
                        : squareMeters(Json.number(parcel['area_m2'])!),
                  ),
                  detail: parcel['idu'] as String?,
                ),
            ],
          ),
        ),
        gap,
        _AnswersCard(dossier: dossier),
        gap,
        BoCard(
          title: l10n.synthRooms,
          child: Column(
            children: [
              if (living != null)
                FieldRow(label: l10n.synthLiving, value: squareMeters(living)),
              if (annex != null && annex > 0)
                FieldRow(label: l10n.synthAnnex, value: squareMeters(annex)),
              for (final room in dossier.rooms)
                FieldRow(
                  label: [
                    room.name,
                    if (room.isMain) l10n.synthRoomMain,
                    if (room.isAnnex) l10n.synthRoomAnnex,
                  ].join(' · '),
                  value: [
                    if (room.areaM2 != null) squareMeters(room.areaM2!),
                    ?room.level,
                    l10n.synthRoomPhotos(room.photosCount),
                  ].join(' · '),
                  detail: room.description,
                  tags: [
                    if (sourceLabel(l10n, _roomSource(room.source))
                        case final String label)
                      BoChip(label),
                  ],
                ),
            ],
          ),
        ),
        if (dossier.previousEstimates.isNotEmpty) ...[
          gap,
          BoCard(
            title: l10n.synthPreviousEstimates,
            child: Column(
              children: [
                for (final estimate in dossier.previousEstimates)
                  FieldRow(
                    label: estimate['agency_name'] as String? ?? '—',
                    value: Json.integer(estimate['price_eur']) == null
                        ? '—'
                        : euros(Json.integer(estimate['price_eur'])!),
                    detail: estimate['estimated_month'] as String?,
                  ),
              ],
            ),
          ),
        ],
        if (notes.isNotEmpty) ...[
          gap,
          BoCard(
            title: l10n.synthNotes,
            child: Column(
              children: [
                for (final step in tunnelSteps)
                  if (notes[step] case final String note)
                    FieldRow(label: stepLabel(l10n, step), value: note),
              ],
            ),
          ),
        ],
        gap,
        _MarketCard(market: dossier.market),
        if (dossier.valuation case final JsonMap valuation) ...[
          gap,
          BoCard(
            title: l10n.synthCertified,
            child: Text(
              l10n.synthCertifiedValue(
                euros(Json.integer(valuation['value_eur']) ?? 0),
                euros(Json.integer(valuation['low_eur']) ?? 0),
                euros(Json.integer(valuation['high_eur']) ?? 0),
                valuation['expert_display_name'] as String? ?? '',
                Json.date(valuation['certified_at']) == null
                    ? ''
                    : dateFr(Json.date(valuation['certified_at'])!),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `rooms.source` (voice, plan…) as a fill sheet source.
  static String? _roomSource(String? source) => switch (source) {
    'voice' => 'dicte',
    'plan' || 'scan' => 'extrait',
    'manual' => 'saisi',
    _ => null,
  };
}

class _OwnersCard extends StatelessWidget {
  const new({required this.dossier});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canVerify = context.can(BackOfficeCapability.verifyIdentity);
    final busy = context.select<DossierCubit, bool>(
      (cubit) => cubit.state.busy,
    );
    final seller = dossier.seller;
    final sellerName = [
      seller['first_name'],
      seller['last_name'],
    ].whereType<String>().join(' ');
    return BoCard(
      title: l10n.synthOwners,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final owner in dossier.owners)
            FieldRow(
              label: owner.displayName,
              value: owner.identityVerifiedAt == null
                  ? l10n.synthOwnerNotVerified
                  : l10n.synthOwnerVerified(dateFr(owner.identityVerifiedAt!)),
              detail: [?owner.phone, ?owner.email].join(' · ').nullIfEmpty,
              tags: [
                if (canVerify && owner.identityVerifiedAt == null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => runGuarded(
                            context,
                            () => context.read<DossierCubit>().verifyIdentity(
                              owner.id,
                            ),
                            success: l10n.synthIdentityDone,
                          ),
                    child: Text(l10n.synthVerifyIdentity),
                  ),
              ],
            ),
          if (sellerName.isNotEmpty || seller['email'] != null) ...[
            const SizedBox(height: RealestySpacing.sm),
            Text(
              l10n.synthSeller(
                [
                  if (sellerName.isNotEmpty) sellerName,
                  ?seller['email'] as String?,
                  ?seller['phone'] as String?,
                ].join(' · '),
              ),
              style: RealestyTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswersCard extends StatelessWidget {
  const new({required this.dossier});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final rows = dossier.fillSheet;
    return BoCard(
      title: l10n.synthAnswers,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.synthAnswersHint,
            style: RealestyTextStyles.bodySmall.copyWith(color: c.texteDiscret),
          ),
          if (rows.isEmpty) ...[
            const SizedBox(height: RealestySpacing.sm),
            Text(l10n.synthNoAnswers),
          ],
          for (final step in [
            ...tunnelSteps,
            ...{for (final r in rows) r.step}.difference(tunnelSteps.toSet()),
          ])
            if (rows.where((r) => r.step == step).toList()
                case final List<FillSheetRow> stepRows
                when stepRows.isNotEmpty) ...[
              const SizedBox(height: RealestySpacing.md),
              Text(
                stepLabel(l10n, step).toUpperCase(),
                style: RealestyTextStyles.caption.copyWith(
                  color: c.texteDiscret,
                ),
              ),
              for (final row in stepRows)
                FieldRow(
                  label: [?row.entityLabel, row.label].join(' · '),
                  value: row.value ?? '—',
                  tags: fillSheetTags(l10n, row),
                ),
            ],
        ],
      ),
    );
  }
}

/// Source, « Non confirmé » and « À vérifier » tags of a fill sheet row.
List<Widget> fillSheetTags(AppLocalizations l10n, FillSheetRow row) => [
  if (sourceLabel(l10n, row.source) case final String label) BoChip(label),
  if (row.confirmed == false) BoChip(l10n.notConfirmed),
  if (row.verified == false) WarningChip(l10n.toVerify),
];

class _MarketCard extends StatelessWidget {
  const new({required this.market});

  final JsonMap? market;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = market;
    final low = Json.integer(m?['estimate_low_eur']);
    final median = Json.integer(m?['estimate_median_eur']);
    final high = Json.integer(m?['estimate_high_eur']);
    if (m == null || median == null) {
      return BoCard(title: l10n.synthMarket, child: Text(l10n.synthMarketNone));
    }
    final priceM2 = Json.integer(m['price_m2_median']);
    final confidence = Json.integer(m['confidence']);
    return BoCard(
      title: l10n.synthMarket,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldRow(
            label: l10n.synthMarketRange,
            value: '${euros(low ?? median)} – ${euros(high ?? median)}',
          ),
          FieldRow(label: l10n.synthMarketMedian, value: euros(median)),
          if (priceM2 != null)
            FieldRow(label: l10n.synthMarketPriceM2, value: euros(priceM2)),
          if (confidence != null)
            FieldRow(
              label: l10n.synthMarketConfidence,
              value: '$confidence %',
              detail: l10n.synthMarketScope(
                Json.integer(m['comparables_count']) ?? 0,
                Json.integer(m['radius_m']) ?? 0,
                Json.integer(m['months']) ?? 0,
              ),
            ),
          for (final sale in Json.maps(m['comparables']))
            FieldRow(
              label: l10n.synthComparable(
                '${sale['street'] ?? '—'}',
                '${sale['sold_year'] ?? ''}',
                Json.number(sale['area_m2']) == null
                    ? '—'
                    : squareMeters(Json.number(sale['area_m2'])!),
                Json.integer(sale['price_eur']) == null
                    ? '—'
                    : euros(Json.integer(sale['price_eur'])!),
              ),
              value: '',
            ),
          if (m['explanation_fr'] case final String explanation) ...[
            const SizedBox(height: RealestySpacing.sm),
            Text(explanation, style: RealestyTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
