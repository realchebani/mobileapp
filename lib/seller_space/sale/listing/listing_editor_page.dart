import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_text.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_sections.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// V11a · Mise en ligne (L’Essentiel, Le Premium, mandate signed): photos,
/// generated description (editable), price within the certified range with
/// the commission, "Publier mon annonce" (Realesty only), and "Mettre hors
/// ligne" once published. L’Expert's listing is prepared by the agent.
class ListingEditorPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sale = context.select<SaleCubit, Sale>((cubit) => cubit.state.sale!);
    if (!sale.formula.selfPublished || !sale.isSigned) {
      return SaleScaffold(
        title: l10n.listingTitle,
        children: [
          InlineBanner(
            message: sale.formula.selfPublished
                ? l10n.saleErrorMandateNotSigned
                : l10n.listingByAgent,
            variant: InlineBannerVariant.info,
          ),
          RealestyButton(
            label: l10n.listingBackToFormula,
            variant: RealestyButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.sellerSale(sale.id)),
          ),
        ],
      );
    }
    return const ListingEditorView();
  }
}

/// The editor of [ListingEditorPage].
class ListingEditorView extends StatefulWidget {
  const new({this.saveDelay = const Duration(milliseconds: 800), super.key});

  /// Delay before a price change is saved.
  final Duration saveDelay;

  @override
  State<ListingEditorView> createState() => _ListingEditorViewState();
}

class _ListingEditorViewState extends State<ListingEditorView> {
  final _priceField = TextEditingController();
  late final SaleCubit _cubit;
  Timer? _saveTimer;
  int? _price;
  int? _pendingPrice;
  List<ListingPhoto> _photos = const [];
  Map<String, String> _urls = const {};

  static const _minPrice = 1000;
  static const _maxPrice = 100000000;

  /// The bounds the server accepts (from half of the certified low bound to
  /// twice the high bound), when the valuations are known.
  (int, int)? get _hardBounds {
    final low = _cubit.state.certifiedLow;
    final high = _cubit.state.certifiedHigh;
    return low == null || high == null
        ? null
        : SalePrices.hardBounds(low, high);
  }

  /// The error of [price], or null when it can be saved.
  String? _priceError(int? price) {
    final l10n = context.l10n;
    if (price == null) return null;
    if (price < _minPrice || price > _maxPrice) return l10n.listingPriceInvalid;
    if (_hardBounds case (final low, final high)
        when price < low || price > high) {
      return l10n.saleErrorPriceBounds(frenchNumber(low), frenchNumber(high));
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _cubit = context.read<SaleCubit>();
    final state = _cubit.state;
    _price = state.basePrice;
    _priceField.text = _price == null ? '' : '$_price';
    unawaited(_loadPhotos());
  }

  bool _generated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_generated) return;
    _generated = true;
    final state = _cubit.state;
    final sale = state.sale!;
    if (sale.listingTitle == null &&
        sale.listingDescription == null &&
        state.members.isNotEmpty) {
      final text = listingTextOf(context.l10n, state.members);
      unawaited(
        _cubit.updateListing({
          SaleColumns.listingTitle: text.title,
          SaleColumns.listingDescription: text.description,
          SaleColumns.descriptionSource: DescriptionSource.template.value,
          if (sale.askingPriceEur == null && _price != null)
            SaleColumns.askingPriceEur: _price,
        }),
      );
    }
  }

  Future<void> _loadPhotos() async {
    final repository = context.read<SaleRepository>();
    final saleId = context.read<SaleCubit>().state.sale!.id;
    try {
      final photos = await repository.getListingPhotos(saleId);
      final urls = await repository.listingPhotoUrls([
        for (final photo in photos.take(4)) photo.storagePath,
      ]);
      if (mounted) {
        setState(() {
          _photos = photos;
          _urls = urls;
        });
      }
    } on Object {
      // The strip then shows no photo; "Gérer les photos" still works.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final pending = _pendingPrice;
    if (pending != null) {
      unawaited(_cubit.updateListing({SaleColumns.askingPriceEur: pending}));
    }
    _priceField.dispose();
    super.dispose();
  }

  void _setPrice(int? price, {bool fromSlider = false}) {
    setState(() => _price = price);
    if (fromSlider) _priceField.text = price == null ? '' : '$price';
    _saveTimer?.cancel();
    if (price == null || _priceError(price) != null) {
      _pendingPrice = null;
      return;
    }
    _pendingPrice = price;
    _saveTimer = Timer(widget.saveDelay, () => unawaited(_savePrice()));
  }

  Future<SaleFailure?> _savePrice() async {
    final price = _pendingPrice;
    if (price == null) return null;
    _pendingPrice = null;
    await _cubit.updateListing({SaleColumns.askingPriceEur: price});
    final failure = _cubit.state.failure;
    if (mounted) showSaleResult(context, failure);
    return failure;
  }

  Future<void> _publish() async {
    final l10n = context.l10n;
    final cubit = context.read<SaleCubit>();
    final price = _price;
    if (price == null || _priceError(price) != null) {
      showRealestySnackBar(
        context,
        _priceError(price) ?? l10n.listingPriceInvalid,
        isError: true,
      );
      return;
    }
    _saveTimer?.cancel();
    if (await _savePrice() != null) return;
    await cubit.publish();
    final failure = cubit.state.failure;
    if (!mounted) return;
    if (failure == null) {
      showRealestySnackBar(context, l10n.listingPublished);
      return;
    }
    if (failure.reason == SaleFailureReason.publishIncomplete) {
      showRealestySnackBar(
        context,
        l10n.listingMissing(
          [
            for (final missing in failure.missing)
              switch (missing) {
                PublishMissing.price => l10n.listingMissingPrice,
                PublishMissing.title => l10n.listingMissingTitle,
                PublishMissing.description => l10n.listingMissingDescription,
                PublishMissing.photos => l10n.listingMissingPhotos,
              },
          ].join(', '),
        ),
        isError: true,
      );
      return;
    }
    showSaleResult(context, failure);
  }

  Future<void> _unpublish() async {
    await _cubit.unpublish();
    final failure = _cubit.state.failure;
    if (mounted) {
      showSaleResult(context, failure, success: context.l10n.listingOffline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SaleCubit>().state;
    final sale = state.sale!;
    final published = sale.stage == SaleStage.published;
    final busy = state.busy != null;
    final low = state.certifiedLow;
    final high = state.certifiedHigh;
    final price = _price;
    final inRange =
        price != null &&
        low != null &&
        high != null &&
        price >= low &&
        price <= high;
    return SaleScaffold(
      title: l10n.listingTitle,
      badges: [
        FormulaBadge(sale.formula),
        RealestyBadge(
          label: published ? saleStageLabel(context, sale) : l10n.listingDraft,
          variant: published
              ? RealestyBadgeVariant.certified
              : RealestyBadgeVariant.neutral,
        ),
      ],
      actions: [
        RealestyIconButton(
          icon: RealestyIcons.eye,
          semanticLabel: l10n.listingPreview,
          onPressed: () =>
              context.push(AppRoutes.sellerSaleListingPreview(sale.id)),
        ),
      ],
      onRefresh: () async {
        await context.read<SaleCubit>().refresh();
        await _loadPhotos();
      },
      bottom: published
          ? RealestyButton(
              label: l10n.listingUnpublish,
              variant: RealestyButtonVariant.secondary,
              isLoading: state.busy == SaleAction.publish,
              onPressed: busy ? null : () => unawaited(_unpublish()),
            )
          : RealestyButton(
              label: l10n.listingPublish,
              variant: RealestyButtonVariant.accent,
              isLoading: state.busy == SaleAction.publish,
              onPressed: busy ? null : () => unawaited(_publish()),
            ),
      children: [
        Text(
          published ? l10n.listingOnlineHeadline : l10n.listingHeadline,
          style: RealestyTextStyles.title1.copyWith(
            fontSize: 22,
            color: c.encre,
          ),
        ),
        Text(
          l10n.listingIntro,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              Row(
                children: [
                  Expanded(child: CardHeading(l10n.listingPhotos)),
                  RealestyBadge(label: l10n.listingPhotoCount(_photos.length)),
                ],
              ),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 76,
                  child: Row(
                    spacing: RealestySpacing.xs,
                    children: [
                      for (final (index, photo) in _photos.take(4).indexed)
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              RealestyRadius.field,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (index < 3 || _photos.length <= 4)
                                  PhotoImage(url: _urls[photo.storagePath])
                                else ...[
                                  if (_urls[photo.storagePath] case final url?)
                                    PhotoImage(url: url),
                                  ColoredBox(
                                    color: c.nuit.withValues(alpha: 0.7),
                                    child: Center(
                                      child: Text(
                                        l10n.listingMorePhotos(
                                          _photos.length - 4,
                                        ),
                                        style: RealestyTextStyles.listTitle
                                            .copyWith(color: c.nuitTexte),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              RealestyButton(
                label: l10n.listingManagePhotos,
                variant: RealestyButtonVariant.secondary,
                leadingIcon: RealestyIcons.camera,
                onPressed: () async {
                  await context.push(
                    AppRoutes.sellerSaleListingPhotos(sale.id),
                  );
                  await _loadPhotos();
                },
              ),
            ],
          ),
        ),
        const PhotoPreferencesCard(showAssistant: false),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              Row(
                children: [
                  Expanded(child: CardHeading(l10n.listingDescription)),
                  RealestyBadge(
                    label: sale.descriptionSource == DescriptionSource.seller
                        ? l10n.listingDescriptionBySeller
                        : l10n.listingDescriptionGenerated,
                    variant: sale.descriptionSource == DescriptionSource.seller
                        ? RealestyBadgeVariant.neutral
                        : RealestyBadgeVariant.toComplete,
                  ),
                ],
              ),
              if (sale.listingTitle case final title?)
                Text(
                  title,
                  style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
                ),
              Text(
                sale.listingDescription ?? l10n.listingDescriptionEmpty,
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
              RealestyButton(
                label: l10n.listingEditText,
                variant: RealestyButtonVariant.text,
                onPressed: busy
                    ? null
                    : () => unawaited(showListingTextSheet(context)),
              ),
            ],
          ),
        ),
        SellerSpaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.sm,
            children: [
              Row(
                children: [
                  Expanded(child: CardHeading(l10n.listingPriceTitle)),
                  if (low != null && high != null && price != null)
                    RealestyBadge(
                      label: inRange
                          ? l10n.listingInRange
                          : l10n.listingOutOfRange,
                      variant: inRange
                          ? RealestyBadgeVariant.certified
                          : RealestyBadgeVariant.toComplete,
                    ),
                ],
              ),
              RealestyTextField(
                label: l10n.listingPriceLabel,
                controller: _priceField,
                suffixText: '€',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                errorText: _priceError(price),
                onChanged: (text) => _setPrice(int.tryParse(text)),
              ),
              Text(
                l10n.listingPriceHint,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
              if (low != null && high != null)
                PriceRangeSlider(
                  low: low,
                  high: high,
                  value: price ?? state.certifiedValue ?? low,
                  onChanged: (value) => _setPrice(value, fromSlider: true),
                  lowLabel: l10n.reportEuros(frenchNumber(low)),
                  highLabel: l10n.reportEuros(frenchNumber(high)),
                  caption: l10n.listingCertifiedRange,
                  semanticLabel: l10n.listingPriceLabel,
                ),
              if (!inRange && low != null && high != null)
                Text(
                  l10n.listingOutOfRangeHint,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.attention,
                  ),
                ),
              if (price != null && price >= _minPrice)
                KeyValueRow(
                  label: l10n.listingCommission,
                  value: l10n.listingCommissionValue(
                    sale.formula.feePercent,
                    frenchNumber(sale.formula.commissionOn(price)),
                    frenchNumber(
                      SalePrices.ht(sale.formula.commissionOn(price)),
                    ),
                  ),
                ),
              KeyValueRow(
                label: l10n.listingDiffusion,
                value: l10n.listingDiffusionValue,
                divider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Edits the title and the text of the listing (or regenerates them from
/// the dossier).
Future<void> showListingTextSheet(BuildContext context) {
  final cubit = context.read<SaleCubit>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const ListingTextSheet()),
  );
}

/// The form of [showListingTextSheet].
class ListingTextSheet extends StatefulWidget {
  const new({super.key});

  @override
  State<ListingTextSheet> createState() => _ListingTextSheetState();
}

class _ListingTextSheetState extends State<ListingTextSheet> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    final sale = context.read<SaleCubit>().state.sale!;
    _title = TextEditingController(text: sale.listingTitle);
    _text = TextEditingController(text: sale.listingDescription);
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(DescriptionSource source) async {
    final title = _title.text.trim();
    final text = _text.text.trim();
    if (title.isEmpty || text.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final cubit = context.read<SaleCubit>();
    await cubit.updateListing({
      SaleColumns.listingTitle: title,
      SaleColumns.listingDescription: text,
      SaleColumns.descriptionSource: source.value,
    });
    final failure = cubit.state.failure;
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
    } else {
      showSaleResult(context, failure);
    }
  }

  void _regenerate() {
    final members = context.read<SaleCubit>().state.members;
    final text = listingTextOf(context.l10n, members);
    _title.text = text.title;
    _text.text = text.description;
    unawaited(_save(DescriptionSource.template));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = context.select<SaleCubit, bool>(
      (cubit) => cubit.state.busy != null,
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.lg,
          RealestySpacing.gutter,
          RealestySpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Text(
              l10n.listingEditText,
              style: RealestyTextStyles.title2.copyWith(
                color: context.realestyColors.encre,
              ),
            ),
            RealestyTextField(
              label: l10n.listingTitleLabel,
              controller: _title,
              enabled: !busy,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              errorText: _showErrors && _title.text.trim().isEmpty
                  ? l10n.listingMissingTitle
                  : null,
            ),
            RealestyTextField(
              label: l10n.listingTextLabel,
              controller: _text,
              enabled: !busy,
              maxLines: 8,
              inputFormatters: [LengthLimitingTextInputFormatter(2000)],
              errorText: _showErrors && _text.text.trim().isEmpty
                  ? l10n.listingMissingDescription
                  : null,
            ),
            RealestyButton(
              label: l10n.listingSaveText,
              isLoading: busy,
              onPressed: busy
                  ? null
                  : () => unawaited(_save(DescriptionSource.seller)),
            ),
            RealestyButton(
              label: l10n.listingRegenerate,
              variant: RealestyButtonVariant.text,
              onPressed: busy ? null : _regenerate,
            ),
          ],
        ),
      ),
    );
  }
}
