import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:sale_repository/sale_repository.dart';

/// Withdraws the sale with an optional reason; returns the failure, if any.
typedef WithdrawCallback = Future<SaleFailure?> Function(String? reason);

/// "Retirer de la vente": the consequences, an optional reason, confirm
/// or cancel (no system dialog). Returns whether the sale was withdrawn.
Future<bool> showWithdrawSaleSheet(
  BuildContext context, {
  required WithdrawCallback onWithdraw,
}) async {
  final withdrawn = await showModalBottomSheet<bool>(
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
    builder: (_) => WithdrawSaleSheet(onWithdraw: onWithdraw),
  );
  return withdrawn ?? false;
}

/// The content of [showWithdrawSaleSheet].
class WithdrawSaleSheet extends StatefulWidget {
  const new({required this.onWithdraw, super.key});

  final WithdrawCallback onWithdraw;

  @override
  State<WithdrawSaleSheet> createState() => _WithdrawSaleSheetState();
}

class _WithdrawSaleSheetState extends State<WithdrawSaleSheet> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    final reason = _reason.text.trim();
    final failure = await widget.onWithdraw(reason.isEmpty ? null : reason);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
    showRealestySnackBar(
      context,
      saleFailureMessage(l10n, failure),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
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
              l10n.saleWithdrawTitle,
              style: RealestyTextStyles.title2.copyWith(color: c.encre),
            ),
            InlineBanner(
              message: l10n.saleWithdrawMessage,
              icon: RealestyIcons.warning,
            ),
            RealestyTextField(
              label: l10n.saleWithdrawReason,
              controller: _reason,
              enabled: !_saving,
              maxLines: 3,
              inputFormatters: [LengthLimitingTextInputFormatter(300)],
            ),
            RealestyButton(
              label: l10n.saleWithdrawConfirm,
              isLoading: _saving,
              onPressed: _saving ? null : () => unawaited(_withdraw()),
            ),
            RealestyButton(
              label: l10n.saleWithdrawCancel,
              variant: RealestyButtonVariant.secondary,
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
