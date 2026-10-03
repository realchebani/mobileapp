import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';
import 'package:realesty_backoffice/app/widgets/widgets.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// While the session is checked.
class LoadingGate extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: CircularProgressIndicator(semanticsLabel: context.l10n.loading),
    ),
  );
}

/// Signed in, but not an active member of the team.
class DeniedGate extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final email = context.select<SessionCubit, String>(
      (cubit) => cubit.state.me?.email ?? '',
    );
    return Scaffold(
      body: BoMessage(
        icon: RealestyIcons.lock,
        title: context.l10n.deniedTitle,
        body: context.l10n.deniedBody(email),
        action: RealestyButton(
          label: context.l10n.signOut,
          expand: false,
          variant: RealestyButtonVariant.secondary,
          onPressed: () => context.read<SessionCubit>().signOut(),
        ),
      ),
    );
  }
}

/// The back-office could not be reached.
class FailedGate extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BoMessage(
      icon: RealestyIcons.warning,
      title: context.l10n.unavailableTitle,
      body: context.l10n.unavailableBody,
      action: RealestyButton(
        label: context.l10n.retry,
        expand: false,
        onPressed: () => context.read<SessionCubit>().refresh(),
      ),
    ),
  );
}
