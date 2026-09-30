import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';
import 'package:mobileapp/login/view/login_failure_message.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// 01b · Connexion par e-mail: e-mail entry, terms, and magic link request.
class LoginEmailPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginCubit, LoginState>(
      listenWhen: (previous, current) =>
          current.sentTo == null &&
          previous.status == LoginStatus.submitting &&
          current.status == LoginStatus.failure &&
          current.failureReason != LoginFailureReason.invalidEmail,
      listener: (context, state) => showRealestySnackBar(
        context,
        (state.failureReason ?? LoginFailureReason.unknown).message(
          context.l10n,
        ),
        isError: true,
      ),
      child: BlocListener<LoginCubit, LoginState>(
        listenWhen: (previous, current) =>
            previous.sentTo == null && current.sentTo != null,
        listener: (context, state) => context.push(AppRoutes.checkInbox),
        child: const LoginEmailView(),
      ),
    );
  }
}

class LoginEmailView extends StatefulWidget {
  const new({super.key});

  @override
  State<LoginEmailView> createState() => _LoginEmailViewState();
}

class _LoginEmailViewState extends State<LoginEmailView> {
  late final TextEditingController _emailController = TextEditingController(
    text: context.read<LoginCubit>().state.email,
  );
  late final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer()
    ..onTap = _showComingSoon;
  late final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer()
    ..onTap = _showComingSoon;

  /// Set when the user validates an invalid e-mail from the keyboard.
  bool _showFormatError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  void _showComingSoon() =>
      showRealestySnackBar(context, context.l10n.comingSoon);

  void _onSubmitted(String _) {
    final cubit = context.read<LoginCubit>();
    if (!cubit.state.isEmailValid) {
      setState(() => _showFormatError = true);
    } else {
      cubit.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<LoginCubit>().state;
    final String? emailError;
    if (state.sentTo == null &&
        state.failureReason == LoginFailureReason.invalidEmail) {
      emailError = l10n.loginFailureInvalidEmail;
    } else if (_showFormatError && !state.isEmailValid) {
      emailError = l10n.loginEmailInvalid;
    } else {
      emailError = null;
    }
    final linkStyle = RealestyCheckbox.linkStyle(context);
    return Scaffold(
      body: SafeArea(
        child: FillScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.gutter,
                  RealestySpacing.xs,
                  RealestySpacing.gutter,
                  0,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: RealestyIconButton(
                    icon: RealestyIcons.chevronLeft,
                    semanticLabel: l10n.backButtonLabel,
                    onPressed: () => context.pop(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.xl,
                  28,
                  RealestySpacing.xl,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RealestyLockup(),
                    const SizedBox(height: RealestySpacing.xxl),
                    Text(
                      l10n.loginEmailTitle,
                      style: RealestyTextStyles.title1.copyWith(color: c.encre),
                    ),
                    const SizedBox(height: RealestySpacing.lg),
                    Text(
                      l10n.loginEmailSubtitle,
                      style: RealestyTextStyles.body.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                    const SizedBox(height: RealestySpacing.xl),
                    RealestyTextField(
                      label: l10n.loginEmailLabel,
                      hint: l10n.loginEmailHint,
                      leadingIcon: RealestyIcons.mail,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      errorText: emailError,
                      onChanged: context.read<LoginCubit>().emailChanged,
                      onSubmitted: _onSubmitted,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RealestySpacing.xl,
                  RealestySpacing.xxl,
                  RealestySpacing.xl,
                  RealestySpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: RealestySpacing.lg,
                  children: [
                    RealestyCheckbox(
                      value: state.termsAccepted,
                      onChanged: (_) =>
                          context.read<LoginCubit>().termsToggled(),
                      richLabel: TextSpan(
                        children: [
                          TextSpan(text: l10n.loginTermsPrefix),
                          TextSpan(
                            text: l10n.loginTermsLink,
                            style: linkStyle,
                            recognizer: _termsRecognizer,
                          ),
                          TextSpan(text: l10n.loginTermsMiddle),
                          TextSpan(
                            text: l10n.loginPrivacyLink,
                            style: linkStyle,
                            recognizer: _privacyRecognizer,
                          ),
                          TextSpan(text: l10n.loginTermsSuffix),
                        ],
                      ),
                    ),
                    RealestyButton(
                      label: l10n.loginEmailSubmit,
                      isLoading: state.status == LoginStatus.submitting,
                      onPressed: state.canSubmit
                          ? () {
                              FocusScope.of(context).unfocus();
                              context.read<LoginCubit>().submit();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
