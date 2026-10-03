import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Aperçu de l’annonce (not in the design canvas): "Ce que verront les
/// acquéreurs" — cover and gallery, title, price, town only (plan Q13: the
/// exact address after an accepted visit), areas and rooms, description.
class ListingPreviewPage extends StatefulWidget {
  const new({super.key});

  @override
  State<ListingPreviewPage> createState() => _ListingPreviewPageState();
}

class _ListingPreviewPageState extends State<ListingPreviewPage> {
  List<ListingPhoto> _photos = const [];
  Map<String, String> _urls = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = context.read<SaleRepository>();
    final saleId = context.read<SaleCubit>().state.sale!.id;
    try {
      final photos = await repository.getListingPhotos(saleId);
      final urls = await repository.listingPhotoUrls([
        for (final photo in photos) photo.storagePath,
      ]);
      if (mounted) {
        setState(() {
          _photos = photos;
          _urls = urls;
        });
      }
    } on Object {
      // Shown without photos.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final price = sale.askingPriceEur;
    final cities = {
      for (final member in state.members)
        if (member.addressCity?.trim() case final city? when city.isNotEmpty)
          city,
    };
    final facts = [
      for (final member in state.members)
        [
          ?propertyTypeLabel(l10n, member),
          if (member.livingAreaM2 ?? member.usableAreaM2 case final area?)
            squareMeters(l10n, area),
          if (member.roomsCount case final rooms? when rooms > 0)
            l10n.listingTextRooms(rooms),
        ].join(' · '),
    ];
    return SaleScaffold(
      title: l10n.listingPreviewTitle,
      children: [
        Text(
          l10n.listingPreviewIntro,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.texteDiscret),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(RealestyRadius.card),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: PhotoImage(
              url: _photos.isEmpty ? null : _urls[_photos.first.storagePath],
            ),
          ),
        ),
        if (_photos.length > 1)
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final photo in _photos.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(right: RealestySpacing.xs),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(RealestyRadius.field),
                      child: SizedBox(
                        width: 96,
                        child: PhotoImage(url: _urls[photo.storagePath]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Text(
          sale.listingTitle ?? l10n.listingDescriptionEmpty,
          style: RealestyTextStyles.title2.copyWith(color: c.encre),
        ),
        if (price != null)
          Text(
            euros(l10n, price),
            style: RealestyTextStyles.keyFigure.copyWith(color: c.encre),
          ),
        if (cities.isNotEmpty)
          Text(
            cities.join(', '),
            style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
          ),
        for (final fact in facts)
          if (fact.isNotEmpty)
            Text(
              fact,
              style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
            ),
        Text(
          sale.listingDescription ?? '',
          style: RealestyTextStyles.body.copyWith(color: c.encre2),
        ),
        KeyValueRow(
          label: l10n.listingDiffusion,
          value: l10n.listingDiffusionValue,
          divider: false,
        ),
      ],
    );
  }
}
