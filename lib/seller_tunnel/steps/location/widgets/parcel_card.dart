import 'package:geo_repository/geo_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// V2 parcel card: "Section · Parcelle" and "Surface cadastrale" of the
/// selected [parcels], tagged "Source externe" (cadastre).
class ParcelCard extends StatelessWidget {
  const new({required this.parcels, super.key});

  /// Selected parcels (at least one).
  final List<CadastreParcel> parcels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final caption = RealestyTextStyles.listSubtitle.copyWith(
      color: c.texteDiscret,
    );
    final value = RealestyTextStyles.title2.copyWith(
      fontSize: 20,
      height: 1.1,
      letterSpacing: -0.4,
      color: c.encre,
    );
    final ids = parcels
        .map(
          (parcel) => l10n.locationParcelId(
            parcel.section ?? '',
            parcel.shortNumero ?? '',
          ),
        )
        .join(', ');
    final area = parcels.fold(0, (sum, parcel) => sum + (parcel.areaM2 ?? 0));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: RealestySpacing.sm,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(l10n.locationParcelHeading, style: caption),
                      Text(ids, style: value),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 2,
                    children: [
                      Text(
                        l10n.locationParcelArea,
                        textAlign: TextAlign.end,
                        style: caption,
                      ),
                      Text(
                        l10n.locationSquareMeters(frenchNumber(area)),
                        textAlign: TextAlign.end,
                        style: value,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProvenanceTag(
                ProvenanceKind.externalSource,
                label: l10n.locationSourceExternal,
              ),
              Text(
                l10n.locationParcelSource,
                style: RealestyTextStyles.badge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: c.texteDiscret,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A validation error under a V2 question.
class LocationErrorText extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: RealestyIcon(
              RealestyIcons.infoCircle,
              size: 14,
              color: c.erreur,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
            ),
          ),
        ],
      ),
    );
  }
}
