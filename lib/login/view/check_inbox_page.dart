import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/cubit/login_cubit.dart';
import 'package:mobileapp/login/view/login_failure_message.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri], returning whether it could be opened.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// 01c · Vérifiez vos e-mails: the magic link was sent; open Mail, resend
/// the link (after a delay) or change the address.
///
/// Leaving this screen (back or "Changer d’adresse e-mail") goes back to
/// the e-mail entry.
class CheckInboxPage extends StatelessWidget {
  const new({this.openUrl = launchUrl, super.key});

  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<LoginCubit>().editEmail();
      },
      child: BlocListener<LoginCubit, LoginState>(
        listenWhen: (previous, current) =>
            current.sentTo != null &&
            (current.hasNewFailureSince(previous) ||
                (previous.status == LoginStatus.submitting &&
                    current.status == LoginStatus.sent)),
        listener: (context, state) {
          if (state.status == LoginStatus.sent) {
            showRealestySnackBar(
              context,
              context.l10n.checkInboxResent,
              icon: RealestyIcons.check,
            );
          } else {
            showLoginFailure(context, state);
          }
        },
        child: CheckInboxView(openUrl: openUrl),
      ),
    );
  }
}

class CheckInboxView extends StatelessWidget {
  const new({required this.openUrl, super.key});

  final UrlOpener openUrl;

  /// Opens the Mail app on iOS.
  static final Uri mailAppUri = Uri.parse('message://');

  /// Formats a countdown in seconds as `m:ss`.
  static String formatCountdown(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _openMail(BuildContext context) async {
    var opened = false;
    try {
      opened = await openUrl(mailAppUri);
    } on Object {
      opened = false;
    }
    if (!opened && context.mounted) {
      showRealestySnackBar(
        context,
        context.l10n.checkInboxOpenMailError,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<LoginCubit>().state;
    final email = state.sentTo ?? state.email.trim();
    final body = l10n.checkInboxBody(email);
    final emailStart = body.indexOf(email);
    final bodyStyle = RealestyTextStyles.body.copyWith(color: c.texteDiscret);
    final emailStyle = TextStyle(fontWeight: FontWeight.w600, color: c.encre);
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
                  RealestySpacing.gutter,
                  RealestySpacing.lg,
                  RealestySpacing.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: RealestySpacing.lg,
                  children: [
                    Container(
                      height: 176,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.vertTeinte,
                        borderRadius: BorderRadius.circular(
                          RealestyRadius.sheet,
                        ),
                      ),
                      child: Container(
                        width: 88,
                        height: 88,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface,
                          boxShadow: RealestyShadows.level1,
                        ),
                        child: RealestyIcon(
                          RealestyIcons.mail,
                          size: 40,
                          color: c.vertTexte,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RealestySpacing.xxs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: RealestySpacing.sm,
                        children: [
                          Text(
                            l10n.checkInboxTitle,
                            style: RealestyTextStyles.title1.copyWith(
                              color: c.encre,
                            ),
                          ),
                          Text.rich(
                            emailStart < 0 || email.isEmpty
                                ? TextSpan(text: body)
                                : TextSpan(
                                    children: [
                                      TextSpan(
                                        text: body.substring(0, emailStart),
                                      ),
                                      TextSpan(text: email, style: emailStyle),
                                      TextSpan(
                                        text: body.substring(
                                          emailStart + email.length,
                                        ),
                                      ),
                                    ],
                                  ),
                            style: bodyStyle,
                          ),
                        ],
                      ),
                    ),
                    InlineBanner(
                      message: l10n.checkInboxInfo,
                      variant: InlineBannerVariant.info,
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
                  RealestySpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: RealestySpacing.sm,
                  children: [
                    RealestyButton(
                      label: l10n.checkInboxOpenMail,
                      leadingIcon: RealestyIcons.mail,
                      onPressed: () => _openMail(context),
                    ),
                    RealestyButton(
                      label: l10n.checkInboxResend,
                      variant: RealestyButtonVariant.secondary,
                      isLoading: state.status == LoginStatus.submitting,
                      onPressed: state.canResend
                          ? context.read<LoginCubit>().resend
                          : null,
                    ),
                    if (state.resendAvailableIn > 0)
                      Text(
                        l10n.checkInboxResendCountdown(
                          formatCountdown(state.resendAvailableIn),
                        ),
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.bodySmall.copyWith(
                          fontSize: 13,
                          color: c.texteDiscret,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    RealestyButton(
                      label: l10n.checkInboxChangeEmail,
                      variant: RealestyButtonVariant.text,
                      onPressed: () => context.pop(),
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
