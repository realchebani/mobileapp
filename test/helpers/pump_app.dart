import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

import 'mocks.dart';

extension PumpApp on WidgetTester {
  /// Pumps [widget] in a [MaterialApp] with the Realesty theme and the
  /// French localizations, under the app repositories and blocs.
  ///
  /// Anything not given is replaced by a mock (blocs in their initial
  /// state). Pass [goRouter] (e.g. a [MockGoRouter]) for widgets that
  /// navigate.
  Future<void> pumpApp(
    Widget widget, {
    AuthRepository? authRepository,
    ProfileRepository? profileRepository,
    PropertyRepository? propertyRepository,
    OnboardingRepository? onboardingRepository,
    AppBloc? appBloc,
    LoginCubit? loginCubit,
    ProfileCubit? profileCubit,
    GoRouter? goRouter,
    Locale locale = const Locale('fr'),
  }) {
    return pumpWidget(
      _AppProviders(
        authRepository: authRepository,
        profileRepository: profileRepository,
        propertyRepository: propertyRepository,
        onboardingRepository: onboardingRepository,
        appBloc: appBloc,
        loginCubit: loginCubit,
        profileCubit: profileCubit,
        child: MaterialApp(
          theme: realestyTheme(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: goRouter == null
              ? widget
              : InheritedGoRouter(goRouter: goRouter, child: widget),
        ),
      ),
    );
  }

  /// Like [pumpApp], with a real [router] (to test actual navigation).
  Future<void> pumpAppRouter(
    GoRouter router, {
    AuthRepository? authRepository,
    ProfileRepository? profileRepository,
    PropertyRepository? propertyRepository,
    OnboardingRepository? onboardingRepository,
    AppBloc? appBloc,
    LoginCubit? loginCubit,
    ProfileCubit? profileCubit,
    Locale locale = const Locale('fr'),
  }) {
    return pumpWidget(
      _AppProviders(
        authRepository: authRepository,
        profileRepository: profileRepository,
        propertyRepository: propertyRepository,
        onboardingRepository: onboardingRepository,
        appBloc: appBloc,
        loginCubit: loginCubit,
        profileCubit: profileCubit,
        child: MaterialApp.router(
          theme: realestyTheme(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
  }
}

class _AppProviders extends StatelessWidget {
  const new({
    required this.child,
    this.authRepository,
    this.profileRepository,
    this.propertyRepository,
    this.onboardingRepository,
    this.appBloc,
    this.loginCubit,
    this.profileCubit,
  });

  final Widget child;
  final AuthRepository? authRepository;
  final ProfileRepository? profileRepository;
  final PropertyRepository? propertyRepository;
  final OnboardingRepository? onboardingRepository;
  final AppBloc? appBloc;
  final LoginCubit? loginCubit;
  final ProfileCubit? profileCubit;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(
          value: authRepository ?? MockAuthRepository(),
        ),
        RepositoryProvider<ProfileRepository>.value(
          value: profileRepository ?? MockProfileRepository(),
        ),
        RepositoryProvider<PropertyRepository>.value(
          value: propertyRepository ?? MockPropertyRepository(),
        ),
        RepositoryProvider<OnboardingRepository>.value(
          value: onboardingRepository ?? MockOnboardingRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AppBloc>.value(value: appBloc ?? _mockAppBloc()),
          BlocProvider<LoginCubit>.value(
            value: loginCubit ?? _mockLoginCubit(),
          ),
          BlocProvider<ProfileCubit>.value(
            value: profileCubit ?? _mockProfileCubit(),
          ),
        ],
        child: child,
      ),
    );
  }
}

AppBloc _mockAppBloc() {
  final bloc = MockAppBloc();
  when(() => bloc.state).thenReturn(const AppState());
  return bloc;
}

LoginCubit _mockLoginCubit() {
  final cubit = MockLoginCubit();
  when(() => cubit.state).thenReturn(const LoginState());
  return cubit;
}

ProfileCubit _mockProfileCubit() {
  final cubit = MockProfileCubit();
  when(() => cubit.state).thenReturn(const ProfileState());
  return cubit;
}
