import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/tabs/documents_tab.dart';
import 'package:realesty_backoffice/dossier/tabs/journal_tab.dart';
import 'package:realesty_backoffice/dossier/tabs/photos_tab.dart';
import 'package:realesty_backoffice/dossier/tabs/synthesis_tab.dart';
import 'package:realesty_backoffice/dossier/tabs/voice_tab.dart';
import 'package:realesty_backoffice/dossier/view/dossier_header.dart';
import 'package:realesty_backoffice/dossier/view/dossier_tab.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/valuation_form/valuation_form.dart';
import 'package:realesty_ui/realesty_ui.dart';

class DossierPage extends StatelessWidget {
  const new({required this.propertyId, required this.tab, super.key});

  final String propertyId;
  final DossierTab tab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(propertyId),
      create: (context) {
        final cubit = DossierCubit(
          repository: context.read(),
          propertyId: propertyId,
        );
        unawaited(
          cubit.load().catchError(context.read<SessionCubit>().onFailure),
        );
        return cubit;
      },
      child: DossierView(tab: tab),
    );
  }
}

class DossierView extends StatelessWidget {
  const new({required this.tab, super.key});

  final DossierTab tab;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<DossierCubit>().state;
    final dossier = state.dossier;
    if (dossier == null) {
      return state.load == DossierLoad.failure
          ? BoMessage(
              icon: RealestyIcons.warning,
              title: l10n.dossierError,
              action: RealestyButton(
                label: l10n.dossierBack,
                expand: false,
                variant: RealestyButtonVariant.secondary,
                onPressed: () => context.go(BoRoutes.queue),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(RealestySpacing.xxl),
      children: [
        DossierHeader(dossier: dossier),
        const SizedBox(height: RealestySpacing.lg),
        _TabBar(propertyId: dossier.id, selected: tab),
        const SizedBox(height: RealestySpacing.lg),
        switch (tab) {
          DossierTab.synthesis => SynthesisTab(dossier: dossier),
          DossierTab.photos => PhotosTab(dossier: dossier),
          DossierTab.documents => DocumentsTab(dossier: dossier),
          DossierTab.voice => VoiceTab(dossier: dossier),
          DossierTab.valuation => ValuationFormPage(dossier: dossier),
          DossierTab.journal => const JournalTab(),
        },
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const new({required this.propertyId, required this.selected});

  final String propertyId;
  final DossierTab selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final labels = {
      DossierTab.synthesis: l10n.dossierTabSynthesis,
      DossierTab.photos: l10n.dossierTabPhotos,
      DossierTab.documents: l10n.dossierTabDocuments,
      DossierTab.voice: l10n.dossierTabVoice,
      DossierTab.valuation: l10n.dossierTabValuation,
      DossierTab.journal: l10n.dossierTabJournal,
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.ligne)),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: tab, value: label) in labels.entries)
            InkWell(
              onTap: () =>
                  context.go(BoRoutes.dossier(propertyId, tab.segment)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RealestySpacing.md,
                  vertical: RealestySpacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == selected ? c.vert : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  label,
                  style: RealestyTextStyles.label.copyWith(
                    color: tab == selected ? c.encre : c.texteDiscret,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Capabilities of the signed-in member, for the dossier widgets.
extension DossierCapabilities on BuildContext {
  bool can(BackOfficeCapability capability) =>
      select<SessionCubit, bool>((s) => s.state.me?.can(capability) ?? false);
}
