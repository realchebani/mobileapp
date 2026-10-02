import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Header of a seller tunnel step (spec 0.1): back button,
/// `Étape N · <name>` caption over the title, mode pill or step counter,
/// and the progress below — N and the number of segments follow the type
/// of the property (`PropertyTypeProfile`: 7 steps for a house, 5 for a
/// garage…).
class TunnelHeader extends StatelessWidget {
  const new({
    required this.step,
    required this.onBack,
    this.title,
    this.mode,
    this.onClose,
    super.key,
  });

  /// The step shown (caption, progress, default [mode]).
  final SellerTunnelStep step;

  /// Back button callback (hidden when null).
  final VoidCallback? onBack;

  /// Defaults to "Audit de votre bien".
  final String? title;

  /// Right side; defaults to [SellerTunnelStep.headerMode].
  final TunnelHeaderMode? mode;

  /// When set, a close button ("Enregistrer et quitter") replaces the right
  /// side, to leave the tunnel.
  final VoidCallback? onClose;

  static const double _sideWidth = RealestySpacing.minTouchTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final type = context.select<SellerTunnelCubit?, PropertyType?>(
      (cubit) => cubit?.state.property?.propertyType,
    );
    final profile = PropertyTypeProfile.of(type);
    final total = profile.stepCount;
    final number = profile.positionOf(step);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          10,
          RealestySpacing.gutter,
          RealestySpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              spacing: RealestySpacing.xs,
              children: [
                if (onBack == null)
                  const SizedBox(width: _sideWidth)
                else
                  RealestyIconButton(
                    icon: RealestyIcons.chevronLeft,
                    semanticLabel: l10n.backButtonLabel,
                    onPressed: onBack,
                  ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Column(
                      children: [
                        Text(
                          l10n.tunnelStepCaption(number, step.label(l10n)),
                          textAlign: TextAlign.center,
                          style: RealestyTextStyles.badge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.texteDiscret,
                          ),
                        ),
                        Text(
                          title ?? l10n.tunnelTitle,
                          textAlign: TextAlign.center,
                          style: RealestyTextStyles.segment.copyWith(
                            fontFamily: RealestyFonts.sora,
                            fontSize: 16,
                            color: c.encre,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _trailing(context, number, total),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedProgress(
              total: total,
              completed: number,
              semanticLabel: l10n.tunnelProgressLabel(number, total),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context, int number, int total) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    if (onClose != null) {
      return RealestyIconButton(
        icon: RealestyIcons.close,
        semanticLabel: l10n.tunnelSaveAndQuit,
        onPressed: onClose,
      );
    }
    return switch (mode ?? step.headerMode) {
      TunnelHeaderMode.screen => _ModePill(
        icon: RealestyIcons.keyboard,
        label: l10n.tunnelModeScreen,
      ),
      TunnelHeaderMode.voice => _ModePill(
        icon: RealestyIcons.mic,
        label: l10n.tunnelModeVoice,
      ),
      TunnelHeaderMode.counter => SizedBox(
        width: _sideWidth,
        child: Text(
          '$number/$total',
          textAlign: TextAlign.right,
          style: RealestyTextStyles.segment.copyWith(
            fontFamily: RealestyFonts.sora,
            color: c.encre,
          ),
        ),
      ),
      TunnelHeaderMode.none => const SizedBox(width: _sideWidth),
    };
  }
}

class _ModePill extends StatelessWidget {
  const new({required this.icon, required this.label});

  final RealestyIcons icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.pill),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          RealestyIcon(icon, size: 14, color: c.encre),
          Text(label, style: RealestyTextStyles.badge.copyWith(color: c.encre)),
        ],
      ),
    );
  }
}
