import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// 01 · Connexion. In v1, only the e-mail (magic link) sign-in is offered;
/// the terms are accepted on the next screen, before the link is sent.
class LoginPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const LoginView();
}

class LoginView extends StatelessWidget {
  const new({super.key});

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
                  onPressed: () {
                    context.read<LoginCubit>().editEmail();
                    unawaited(context.push(AppRoutes.loginEmail));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
