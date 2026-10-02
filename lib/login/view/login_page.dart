import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';
import 'package:mobileapp/login/view/dev_test_login.dart';
import 'package:mobileapp/login/view/login_failure_message.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// 01 · Connexion. In v1, only the e-mail (magic link) sign-in is offered;
/// the terms are accepted on the next screen, before the link is sent.
///
/// Also reports magic link failures that happen here, e.g. when the app is
/// cold-started from an expired link.
class LoginPage extends StatefulWidget {
  const new({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    // The failure may have been reported before this screen was shown
    // (splash, redirect).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<LoginCubit>().state;
      if (state.isLinkFailure) showLoginFailure(context, state);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginCubit, LoginState>(
      listenWhen: (previous, current) =>
          current.isLinkFailure && current.hasNewFailureSince(previous),
      listener: showLoginFailure,
      child: LoginView(devTestCredentials: DevTestCredentials.fromEnvironment),
    );
  }
}

class LoginView extends StatefulWidget {
  const new({this.devTestCredentials, super.key});

  /// Shows the "Connexion de test (dev)" button when set (development
  /// flavor only, see [DevTestCredentials.fromEnvironment]).
  final DevTestCredentials? devTestCredentials;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  /// Set while the e-mail screen is open, so a double tap opens it once.
  bool _openingEmail = false;

  Future<void> _openEmailLogin() async {
    if (_openingEmail) return;
    _openingEmail = true;
    context.read<LoginCubit>().editEmail();
    await context.push(AppRoutes.loginEmail);
    _openingEmail = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Scaffold(
      body: SafeArea(
        child: FillScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RealestySpacing.xl,
              RealestySpacing.xxxl,
              RealestySpacing.xl,
              RealestySpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RealestyLockup(),
                const SizedBox(height: 44),
                Text(
                  l10n.loginTitle,
                  style: RealestyTextStyles.display.copyWith(
                    height: 1.2,
                    letterSpacing: -0.32,
                    color: c.encre,
                  ),
                ),
                const SizedBox(height: RealestySpacing.lg),
                Text(
                  l10n.loginSubtitle,
                  style: RealestyTextStyles.body.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: RealestySpacing.xxl),
                RealestyButton(
                  label: l10n.loginEmailButton,
                  leadingIcon: RealestyIcons.mail,
                  onPressed: () => unawaited(_openEmailLogin()),
                ),
                if (widget.devTestCredentials case final credentials?) ...[
                  const SizedBox(height: RealestySpacing.xs),
                  DevTestLoginButton(credentials: credentials),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
