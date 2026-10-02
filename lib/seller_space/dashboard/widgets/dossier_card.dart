import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V9 · "Mon dossier": transparency score and the documents, surfaces
/// and living environment rows, each opening the dossier overview.
class DossierCard extends StatelessWidget {
  const new({required this.state, required this.onOpen, super.key});

  final SellerTunnelState state;

  /// Opens the dossier overview (V8 data preview sheet).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final property = state.property!;
    final score = property.transparencyScore;
    final rejected = state.documents
        .where((document) => document.status == DocumentStatus.rejected)
        .length;
    final area = property.livingAreaM2;
    final assets = state.lifestyleItems
        .where((item) => item.kind == LifestyleItemKind.asset)
        .length;
    final watchPoints = state.lifestyleItems.length - assets;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xxs,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.dashboardDossierTitle,
                    style: RealestyTextStyles.title2.copyWith(
                      fontSize: 17,
                      color: c.encre,
                    ),
                  ),
                ),
              ),
              if (score != null)
                Text(
                  l10n.dashboardDossierScore(score),
                  style: RealestyTextStyles.title2.copyWith(
                    fontSize: 16,
                    color: c.encre,
                  ),
                ),
            ],
          ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(top: RealestySpacing.xxs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RealestyRadius.pill),
                child: LinearProgressIndicator(
                  value: score.clamp(0, 100) / 100,
                  minHeight: 6,
                  color: c.vert,
                  backgroundColor: c.bordureCarte,
                ),
              ),
            ),
          RealestyListItem(
            title: l10n.dashboardDocuments,
            subtitle: [
              l10n.dashboardDocumentsCount(state.documents.length),
              if (rejected > 0) l10n.dashboardDocumentsRejected(rejected),
            ].join(' · '),
            leadingIcon: RealestyIcons.file,
            trailing: rejected > 0
                ? RealestyBadge(
                    label: l10n.dashboardActionRequired,
                    variant: RealestyBadgeVariant.toComplete,
                  )
                : RealestyIcon(RealestyIcons.chevronRight, color: c.encre),
            onTap: onOpen,
          ),
          RealestyListItem(
            title: l10n.dashboardSurfaces,
            subtitle: [
              if (area != null) squareMeters(l10n, area),
              l10n.dashboardRooms(state.rooms.length),
            ].join(' · '),
            leadingIcon: RealestyIcons.plan,
            trailing: RealestyIcon(RealestyIcons.chevronRight, color: c.encre),
            onTap: onOpen,
          ),
          RealestyListItem(
            title: l10n.dashboardLifestyle,
            subtitle:
                '${l10n.dashboardLifestyleAssets(assets)} · '
                '${l10n.dashboardLifestyleWatch(watchPoints)}',
            leadingIcon: RealestyIcons.spark,
            trailing: RealestyIcon(RealestyIcons.chevronRight, color: c.encre),
            showDivider: false,
            onTap: onOpen,
          ),
        ],
      ),
    );
  }
}
