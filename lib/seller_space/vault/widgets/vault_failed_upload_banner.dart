import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/vault/cubit/vault_cubit.dart';
import 'package:mobileapp/ui/ui.dart';

/// "L’envoi de … a échoué" + Réessayer / Abandonner.
class VaultFailedUploadBanner extends StatelessWidget {
  const new({required this.fileName, super.key});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<VaultCubit>();
    final busy = context.select<VaultCubit, bool>((c) => c.state.busy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        InlineBanner(message: l10n.vaultUploadFailed(fileName)),
        Row(
          spacing: RealestySpacing.sm,
          children: [
            Expanded(
              child: RealestyButton(
                label: l10n.vaultUploadDiscard,
                variant: RealestyButtonVariant.text,
                onPressed: busy ? null : cubit.discardFailedUpload,
              ),
            ),
            Expanded(
              child: RealestyButton(
                label: l10n.vaultRetry,
                variant: RealestyButtonVariant.secondary,
                isLoading: busy,
                onPressed: busy ? null : cubit.retryUpload,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
