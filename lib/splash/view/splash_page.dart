import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mobileapp/widgets/widgets.dart';

/// 00 · Splash, shown while the session and the profile are restored.
///
/// When the profile fails to load, offers to retry or to sign out.
class SplashPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final failed = context.select<ProfileCubit, bool>(
      (cubit) => cubit.state.status == ProfileStatus.failure,
    );
    return SplashView(profileFailed: failed);
  }
}

class SplashView extends StatelessWidget {
  const new({this.profileFailed = false, super.key});

  final bool profileFailed;

  /// Duration of the progress bar animation.
  static const progressDuration = Duration(milliseconds: 1600);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Scaffold(
      body: SafeArea(
        child: FillScrollView(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RealestySpacing.xxl,
                    vertical: RealestySpacing.xl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const RealestyLogo(
                        size: 120,
                        wordmarkSize: 30,
                        showWordmark: true,
                        direction: Axis.vertical,
                      ),
                      const SizedBox(height: 40),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${l10n.splashTaglineLine1}\n'),
                            TextSpan(
                              text: l10n.splashTaglineLine2,
                              style: TextStyle(color: c.vertTexte),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: RealestyTextStyles.title1.copyWith(
                          fontSize: 22,
                          height: 1.3,
                          color: c.encre,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 0, 60, 24),
                child: profileFailed
                    ? const _ProfileFailure()
                    : Column(
                        spacing: 14,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              RealestyRadius.pill,
                            ),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 0.9),
                              duration: progressDuration,
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) =>
                                  LinearProgressIndicator(
                                    value: value,
                                    minHeight: 4,
                                    color: c.vert,
                                    backgroundColor: c.bordureCarte,
                                    borderRadius: BorderRadius.circular(
                                      RealestyRadius.pill,
                                    ),
                                  ),
                            ),
                          ),
                          Text(
                            l10n.splashFooter,
                            textAlign: TextAlign.center,
                            style: RealestyTextStyles.bodySmall.copyWith(
                              fontSize: 13,
                              color: c.texteDiscret,
                            ),
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

class _ProfileFailure extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return Column(
      spacing: RealestySpacing.sm,
      children: [
        Text(
          l10n.splashProfileError,
          textAlign: TextAlign.center,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.erreur),
        ),
        RealestyButton(
          label: l10n.retryButton,
          onPressed: () => context.read<ProfileCubit>().retry(),
        ),
        RealestyButton(
          label: l10n.logoutButton,
          variant: RealestyButtonVariant.text,
          onPressed: () =>
              context.read<AppBloc>().add(const AppLogoutPressed()),
        ),
      ],
    );
  }
}
