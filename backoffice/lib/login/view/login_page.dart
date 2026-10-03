import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/login/cubit/login_cubit.dart';
import 'package:realesty_ui/realesty_ui.dart';

class LoginPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginCubit(
        auth: context.read(),
        redirectUrl: context.read<BackOfficeConfig>().authRedirectUrl,
      ),
      child: const LoginView(),
    );
  }
}

/// Centered card used by the sign-in screens.
class GateCard extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Scaffold(
      backgroundColor: c.ivoire,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RealestySpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: BoCard(
              padding: const EdgeInsets.all(RealestySpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: RealestyLogo(size: 32, showWordmark: true),
                  ),
                  const SizedBox(height: RealestySpacing.xl),
                  Text(
                    title,
                    style: RealestyTextStyles.title1.copyWith(color: c.encre),
                  ),
                  const SizedBox(height: RealestySpacing.sm),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<LoginCubit>().state;
    final cubit = context.read<LoginCubit>();
    final dev = context.read<BackOfficeConfig>().devPasswordLogin;
    final body = RealestyTextStyles.bodySmall.copyWith(color: c.encre2);

    if (state.status == LoginStatus.sent) {
      return GateCard(
        title: l10n.loginSentTitle,
        children: [
          Text(l10n.loginSentBody(state.email.trim()), style: body),
          const SizedBox(height: RealestySpacing.lg),
          RealestyButton(
            label: l10n.loginOtherEmail,
            variant: RealestyButtonVariant.secondary,
            onPressed: cubit.restart,
          ),
        ],
      );
    }

    final error = switch (state.status) {
      LoginStatus.rateLimited => l10n.loginRateLimited,
      LoginStatus.failure => l10n.loginError,
      LoginStatus.passwordFailure => l10n.loginDevError,
      _ => null,
    };
    return GateCard(
      title: l10n.loginTitle,
      children: [
        Text(l10n.loginBody, style: body),
        const SizedBox(height: RealestySpacing.lg),
        RealestyTextField(
          label: l10n.loginEmailLabel,
          hint: l10n.loginEmailHint,
          leadingIcon: RealestyIcons.mail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          enabled: !state.isSending,
          errorText: state.status == LoginStatus.invalidEmail
              ? l10n.loginEmailInvalid
              : null,
          onChanged: cubit.emailChanged,
          onSubmitted: (_) => cubit.sendLink(),
        ),
        const SizedBox(height: RealestySpacing.md),
        RealestyButton(
          label: l10n.loginSend,
          isLoading: state.isSending,
          onPressed: cubit.sendLink,
        ),
        if (error != null) ...[
          const SizedBox(height: RealestySpacing.md),
          InlineBanner(message: error),
        ],
        const SizedBox(height: RealestySpacing.lg),
        Text(
          l10n.loginSecurityNote,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.texteDiscret),
        ),
        if (dev) ...[
          const SizedBox(height: RealestySpacing.xl),
          Text(l10n.loginDevTitle, style: RealestyTextStyles.label),
          const SizedBox(height: RealestySpacing.xs),
          RealestyTextField(
            label: l10n.loginDevPassword,
            obscureText: true,
            enabled: !state.isSending,
            onChanged: cubit.passwordChanged,
          ),
          const SizedBox(height: RealestySpacing.xs),
          RealestyButton(
            label: l10n.loginDevSubmit,
            variant: RealestyButtonVariant.secondary,
            onPressed: state.isSending ? null : cubit.signInWithPassword,
          ),
        ],
      ],
    );
  }
}
