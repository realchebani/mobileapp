import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';
import 'package:realesty_backoffice/app/widgets/labels.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Runs a back-office [action]: a snackbar tells the result; a refused
/// access sends the session back to the right screen. Returns whether it
/// succeeded.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final l10n = context.l10n;
  final session = context.read<SessionCubit>();
  try {
    await action();
    if (success != null && context.mounted) {
      showRealestySnackBar(context, success, icon: RealestyIcons.check);
    }
    return true;
  } on Object catch (error) {
    session.onFailure(error);
    if (context.mounted) {
      showRealestySnackBar(context, failureText(l10n, error), isError: true);
    }
    return false;
  }
}
