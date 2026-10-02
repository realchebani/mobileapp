import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// "Tendance IA" card of V8 without a figure: while computing, when there
/// is no estimate for the property (the expert takes over), or after a
/// failure (with [onRetry]).
class AiEstimateStatusCard extends StatelessWidget {
  const new({
    required this.message,
    this.isLoading = false,
    this.onRetry,
    super.key,
  });

  final String message;

  /// Shows a progress indicator next to [message].
  final bool isLoading;

  /// "Réessayer" button, hidden when null.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final onRetry = this.onRetry;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Expanded(
                child: Text(
                  l10n.submittedAiLabel.toUpperCase(),
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
              RealestyBadge(
                label: l10n.submittedAiBadge,
                variant: RealestyBadgeVariant.toComplete,
              ),
            ],
          ),
          Row(
            spacing: RealestySpacing.sm,
            children: [
              if (isLoading)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.vertTexte,
                  ),
                ),
              Expanded(
                child: Text(
                  message,
                  style: RealestyTextStyles.body.copyWith(
                    fontSize: 14,
                    height: 1.45,
                    color: c.encre,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            RealestyButton(
              label: l10n.retryButton,
              variant: RealestyButtonVariant.secondary,
              height: 48,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
