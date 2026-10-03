import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/seller_space/vault/models/vault_contents.dart';
import 'package:mobileapp/seller_space/vault/models/vault_rubric.dart';
import 'package:mobileapp/seller_space/vault/vault_scope.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_actions.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_entry_row.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_failed_upload_banner.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_target_selector.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';

/// C1 · Coffre-fort ("Coffre-fort" tab): the documents of one property or
/// lot (chosen with a selector when the seller has several), by rubric,
/// with a search, the latest ones and the missing required ones.
class VaultPage extends StatelessWidget {
  const new({this.services = const VaultServices(), super.key});

  final VaultServices services;

  @override
  Widget build(BuildContext context) {
    return VaultScope(services: services, child: const VaultView());
  }
}

class VaultView extends StatefulWidget {
  const new({super.key});

  @override
  State<VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<VaultView> {
  VaultTarget? _target;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sync(context.read<SellerPropertiesCubit>().state);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Shows the chosen target (else the first property) once the
  /// properties are known, and follows their changes.
  void _sync(SellerPropertiesState properties) {
    if (properties.properties.isEmpty) return;
    final current = _target;
    final target =
        current != null && vaultTargetMembers(properties, current).isNotEmpty
        ? current
        : VaultTarget.property(properties.properties.first.id);
    final members = vaultTargetMembers(properties, target);
    final cubit = context.read<VaultCubit>();
    if (target != cubit.state.target) {
      _target = target;
      unawaited(cubit.show(target, members));
    } else if (members != cubit.state.properties) {
      unawaited(cubit.refresh(properties: members));
    }
  }

  void _select(VaultTarget target) {
    setState(() => _target = target);
    final properties = context.read<SellerPropertiesCubit>().state;
    unawaited(
      context.read<VaultCubit>().show(
        target,
        vaultTargetMembers(properties, target),
      ),
    );
  }

  void _openRubric(VaultTarget target, VaultRubric? rubric) {
    final lotId = target.lotId;
    unawaited(
      context.push(
        lotId != null
            ? AppRoutes.sellerVaultLot(lotId)
            : AppRoutes.sellerVaultProperty(
                target.propertyId!,
                rubric: rubric?.code,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final properties = context.watch<SellerPropertiesCubit>().state;
    final state = context.watch<VaultCubit>().state;
    final target = state.target;
    return BlocListener<SellerPropertiesCubit, SellerPropertiesState>(
      listener: (context, properties) => _sync(properties),
      child: ColoredBox(
        color: c.ivoire,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: c.vertTexte,
            onRefresh: () async {
              await context.read<SellerPropertiesCubit>().refresh();
              if (context.mounted) {
                await context.read<VaultCubit>().refresh();
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.md,
                RealestySpacing.gutter,
                RealestySpacing.xl,
              ),
              children: [
                Row(
                  children: [
                    Expanded(child: SellerSpaceTitle(l10n.vaultTitle)),
                    if (target != null)
                      RealestyIconButton(
                        icon: RealestyIcons.plus,
                        semanticLabel: l10n.vaultAdd,
                        onPressed:
                            state.status == VaultStatus.success && !state.busy
                            ? () => addVaultDocument(context)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: RealestySpacing.md),
                ..._content(context, properties, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    SellerPropertiesState properties,
    VaultState state,
  ) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final target = state.target;
    if (properties.status == SellerPropertiesStatus.success &&
        properties.properties.isEmpty) {
      return [
        InlineBanner(
          message: l10n.vaultNoProperty,
          variant: InlineBannerVariant.info,
        ),
        const SizedBox(height: RealestySpacing.md),
        RealestyButton(
          label: l10n.myPropertiesAdd,
          leadingIcon: RealestyIcons.plus,
          onPressed: () => context.go(AppRoutes.sellerNewProperty),
        ),
      ];
    }
    if (target == null ||
        state.status == VaultStatus.loading ||
        state.status == VaultStatus.initial) {
      return [
        Padding(
          padding: const EdgeInsets.all(RealestySpacing.xxl),
          child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
        ),
      ];
    }
    final selector =
        properties.properties.length > 1 || properties.lots.isNotEmpty
        ? [
            VaultTargetSelector(
              properties: properties,
              target: target,
              onChanged: _select,
            ),
            const SizedBox(height: RealestySpacing.md),
          ]
        : const <Widget>[];
    if (state.status == VaultStatus.failure) {
      return [
        ...selector,
        InlineBanner(message: l10n.vaultLoadFailed),
        const SizedBox(height: RealestySpacing.md),
        RealestyButton(
          label: l10n.vaultRetry,
          variant: RealestyButtonVariant.secondary,
          onPressed: () => context.read<VaultCubit>().refresh(),
        ),
      ];
    }
    final contents = state.contents;
    final showProperty = state.properties.length > 1;
    final results = contents.search(
      _query,
      (entry) => [
        l10n.vaultDocumentTitle(
          entry.document,
          owner: vaultOwnerOf(state, entry.document),
        ),
        l10n.vaultKind(entry.document.kind),
        entry.document.fileName ?? '',
        if (showProperty) propertyShortLabel(l10n, entry.property),
      ].join(' '),
    );
    final failed = state.failedUpload;
    return [
      ...selector,
      RealestyTextField(
        label: l10n.vaultSearchLabel,
        hint: l10n.vaultSearchHint,
        leadingIcon: RealestyIcons.search,
        controller: _search,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
      ),
      const SizedBox(height: RealestySpacing.md),
      if (failed != null) ...[
        VaultFailedUploadBanner(fileName: failed.file.fileName),
        const SizedBox(height: RealestySpacing.md),
      ],
      if (_query.trim().isNotEmpty) ...[
        _SectionTitle(l10n.vaultSearchResults(results.length)),
        if (results.isEmpty)
          Text(
            l10n.vaultSearchEmpty,
            style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
          )
        else
          SellerSpaceCard(
            padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
            child: Column(
              children: [
                for (final (index, entry) in results.indexed)
                  VaultEntryRow(
                    entry: entry,
                    showProperty: showProperty,
                    showDivider: index < results.length - 1,
                  ),
              ],
            ),
          ),
      ] else ...[
        SellerSpaceCard(
          padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
          child: Column(
            children: [
              for (final (index, section) in contents.sections.indexed)
                RealestyListItem(
                  title: l10n.vaultRubric(section.rubric),
                  subtitle: l10n.vaultSectionSummary(section),
                  leadingIcon: VaultLabels.rubricIcon(section.rubric),
                  tone: section.missing.isNotEmpty || section.toReplaceCount > 0
                      ? RealestyListTileTone.error
                      : RealestyListTileTone.neutral,
                  trailing: RealestyIcon(
                    RealestyIcons.chevronRight,
                    size: 18,
                    color: c.texteDiscret,
                  ),
                  showDivider: index < contents.sections.length - 1,
                  onTap: () => _openRubric(target, section.rubric),
                ),
            ],
          ),
        ),
        if (contents.recents.isNotEmpty || contents.missing.isNotEmpty) ...[
          const SizedBox(height: RealestySpacing.lg),
          _SectionTitle(l10n.vaultRecents),
          SellerSpaceCard(
            padding: const EdgeInsets.symmetric(horizontal: RealestySpacing.md),
            child: Column(
              children: [
                for (final (index, entry) in <VaultEntry>[
                  ...contents.recents,
                  ...contents.missing,
                ].indexed)
                  VaultEntryRow(
                    entry: entry,
                    showProperty: showProperty,
                    showDivider:
                        index <
                        contents.recents.length + contents.missing.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ],
      const SizedBox(height: RealestySpacing.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RealestySpacing.xs,
        children: [
          RealestyIcon(RealestyIcons.lock, size: 16, color: c.texteDiscret),
          Expanded(
            child: Text(
              l10n.vaultPrivacy,
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          title.toUpperCase(),
          style: RealestyTextStyles.caption.copyWith(
            color: context.realestyColors.texteDiscret,
          ),
        ),
      ),
    );
  }
}
