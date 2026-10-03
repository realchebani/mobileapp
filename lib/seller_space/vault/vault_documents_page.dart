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
import 'package:mobileapp/seller_space/vault/widgets/collapsible_section.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_actions.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_entry_row.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_failed_upload_banner.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_labels.dart';
import 'package:mobileapp/seller_space/vault/widgets/vault_target_selector.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_properties_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V18 · Mes documents of one property or lot: every rubric as a
/// collapsible section, with the status and the sharing of each document,
/// the missing required ones, and what the expert asks to replace.
class VaultDocumentsPage extends StatelessWidget {
  const new({
    required this.target,
    this.rubric,
    this.services = const VaultServices(),
    super.key,
  });

  final VaultTarget target;

  /// The rubric to open (the others are folded).
  final VaultRubric? rubric;
  final VaultServices services;

  @override
  Widget build(BuildContext context) {
    return VaultScope(
      services: services,
      child: VaultDocumentsView(target: target, rubric: rubric),
    );
  }
}

class VaultDocumentsView extends StatefulWidget {
  const new({required this.target, this.rubric, super.key});

  final VaultTarget target;
  final VaultRubric? rubric;

  @override
  State<VaultDocumentsView> createState() => _VaultDocumentsViewState();
}

class _VaultDocumentsViewState extends State<VaultDocumentsView> {
  late Set<VaultRubric> _expanded = {
    if (widget.rubric case final rubric?) rubric else ...VaultRubric.values,
  };

  @override
  void initState() {
    super.initState();
    _sync(context.read<SellerPropertiesCubit>().state);
  }

  void _sync(SellerPropertiesState properties) {
    final members = vaultTargetMembers(properties, widget.target);
    if (members.isEmpty) return;
    final cubit = context.read<VaultCubit>();
    if (cubit.state.target != widget.target) {
      unawaited(cubit.show(widget.target, members));
    } else if (members != cubit.state.properties) {
      unawaited(cubit.refresh(properties: members));
    }
  }

  void _back() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.sellerVault);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final properties = context.watch<SellerPropertiesCubit>().state;
    final state = context.watch<VaultCubit>().state;
    final members = vaultTargetMembers(properties, widget.target);
    final List<Widget> body;
    if (members.isEmpty &&
        properties.status == SellerPropertiesStatus.success) {
      body = [InlineBanner(message: l10n.vaultNotFound)];
    } else if (state.status == VaultStatus.failure) {
      body = [
        InlineBanner(message: l10n.vaultLoadFailed),
        const SizedBox(height: RealestySpacing.md),
        RealestyButton(
          label: l10n.vaultRetry,
          variant: RealestyButtonVariant.secondary,
          onPressed: () => context.read<VaultCubit>().refresh(),
        ),
      ];
    } else if (state.status != VaultStatus.success) {
      body = [
        Padding(
          padding: const EdgeInsets.all(RealestySpacing.xxl),
          child: Center(child: CircularProgressIndicator(color: c.vertTexte)),
        ),
      ];
    } else {
      body = _documents(context, state);
    }
    return BlocListener<SellerPropertiesCubit, SellerPropertiesState>(
      listener: (context, properties) => _sync(properties),
      child: ColoredBox(
        color: c.ivoire,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: c.vertTexte,
            onRefresh: () => context.read<VaultCubit>().refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                RealestySpacing.gutter,
                RealestySpacing.xs,
                RealestySpacing.gutter,
                RealestySpacing.xl,
              ),
              children: [
                Row(
                  children: [
                    RealestyIconButton(
                      icon: RealestyIcons.chevronLeft,
                      semanticLabel: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      onPressed: _back,
                    ),
                    Expanded(
                      child: Text(
                        l10n.vaultDocumentsEyebrow,
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.caption.copyWith(
                          color: c.texteDiscret,
                        ),
                      ),
                    ),
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
                const SizedBox(height: RealestySpacing.xs),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.vaultDocumentsTitle,
                    style: RealestyTextStyles.title1.copyWith(
                      fontSize: 24,
                      color: c.encre,
                    ),
                  ),
                ),
                if (members.isNotEmpty)
                  Text(
                    vaultTargetLabel(l10n, properties, widget.target),
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                const SizedBox(height: RealestySpacing.md),
                ...body,
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _documents(BuildContext context, VaultState state) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final contents = state.contents;
    final showProperty = state.properties.length > 1;
    final missing = contents.missing;
    final toReplace = contents.toReplace;
    final missingIdentity = missing.any(
      (entry) => entry.kind == DocumentKind.identityDocument,
    );
    final allExpanded = _expanded.length == VaultRubric.values.length;
    final failed = state.failedUpload;
    return [
      Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: RealestySpacing.xs,
              runSpacing: RealestySpacing.xs,
              children: [
                RealestyBadge(
                  label: l10n.vaultDocumentCount(contents.documentCount),
                ),
                if (missing.isNotEmpty)
                  RealestyBadge(
                    label: l10n.vaultToAdd(missing.length),
                    variant: RealestyBadgeVariant.toComplete,
                  ),
              ],
            ),
          ),
          RealestyPressable(
            semanticLabel: allExpanded
                ? l10n.vaultCollapseAll
                : l10n.vaultExpandAll,
            onPressed: () => setState(
              () => _expanded = allExpanded ? {} : {...VaultRubric.values},
            ),
            child: Padding(
              padding: const EdgeInsets.all(RealestySpacing.xs),
              child: Text(
                allExpanded ? l10n.vaultCollapseAll : l10n.vaultExpandAll,
                style: RealestyTextStyles.label.copyWith(color: c.vertTexte),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: RealestySpacing.md),
      if (toReplace.isNotEmpty || missingIdentity) ...[
        AgentBubble(
          senderName: l10n.vaultAgentName,
          message: switch (toReplace.firstOrNull) {
            final entry? => switch (entry.document.rejectedReason) {
              final reason? => l10n.vaultAgentReplace(
                l10n.vaultDocumentTitle(
                  entry.document,
                  owner: vaultOwnerOf(state, entry.document),
                ),
                reason,
              ),
              null => l10n.vaultAgentReplaceNoReason(
                l10n.vaultDocumentTitle(
                  entry.document,
                  owner: vaultOwnerOf(state, entry.document),
                ),
              ),
            },
            null => l10n.vaultAgentIdentity,
          },
        ),
        const SizedBox(height: RealestySpacing.md),
      ],
      if (failed != null) ...[
        VaultFailedUploadBanner(fileName: failed.file.fileName),
        const SizedBox(height: RealestySpacing.md),
      ],
      for (final section in contents.sections) ...[
        CollapsibleSection(
          title: l10n.vaultRubric(section.rubric),
          summary: l10n.vaultSectionSummary(section),
          icon: VaultLabels.rubricIcon(section.rubric),
          trailing: section.missing.isNotEmpty || section.toReplaceCount > 0
              ? RealestyBadge(
                  label: l10n.vaultBadgeToComplete,
                  variant: RealestyBadgeVariant.toComplete,
                )
              : null,
          expanded: _expanded.contains(section.rubric),
          onToggle: () => setState(() {
            if (!_expanded.remove(section.rubric)) {
              _expanded.add(section.rubric);
            }
          }),
          children: [
            for (final (index, entry) in <VaultEntry>[
              ...section.valuations,
              ...section.documents,
              ...section.missing,
            ].indexed)
              VaultEntryRow(
                entry: entry,
                showProperty: showProperty,
                showDivider: index < section.count + section.missing.length - 1,
              ),
            if (section.count + section.missing.length == 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RealestySpacing.sm,
                ),
                child: Text(
                  section.rubric == VaultRubric.mandates
                      ? l10n.vaultMandatesEmpty
                      : l10n.vaultSectionEmpty,
                  style: RealestyTextStyles.listSubtitle.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
            if (section.rubric.acceptsDocuments)
              Align(
                alignment: Alignment.centerLeft,
                child: RealestyButton(
                  label: l10n.vaultAddToRubric,
                  leadingIcon: RealestyIcons.plus,
                  variant: RealestyButtonVariant.text,
                  expand: false,
                  height: 40,
                  onPressed: state.busy
                      ? null
                      : () => addVaultDocument(context, rubric: section.rubric),
                ),
              ),
          ],
        ),
        const SizedBox(height: RealestySpacing.sm),
      ],
      const SizedBox(height: RealestySpacing.sm),
      Text(
        l10n.vaultSharingFooter,
        style: RealestyTextStyles.listSubtitle.copyWith(color: c.texteDiscret),
      ),
    ];
  }
}
