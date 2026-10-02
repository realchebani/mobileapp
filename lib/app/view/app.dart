import 'package:auth_repository/auth_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/bloc/app_bloc.dart';
import 'package:mobileapp/app/data/onboarding_repository.dart';
import 'package:mobileapp/app/router/app_router.dart';
import 'package:mobileapp/app/router/stream_listenable.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Root of the app: provides the repositories and the app-wide blocs.
///
/// The [LoginCubit] lives at the app level so that its state survives the
/// e-mail ↔ "check your inbox" navigation and catches magic link failures.
class App extends StatelessWidget {
  const new({
    required this.authRepository,
    required this.profileRepository,
    required this.propertyRepository,
    required this.onboardingRepository,
    required this.valuationRepository,
    required this.notificationRepository,
    this.geoRepository,
    this.enableDesignSystem,
    super.key,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final PropertyRepository propertyRepository;
  final OnboardingRepository onboardingRepository;
  final ValuationRepository valuationRepository;
  final NotificationRepository notificationRepository;

  /// Addresses and cadastre (seller tunnel V2); a default one when null.
  final GeoRepository? geoRepository;

  /// Whether the design system gallery is reachable; defaults to the
  /// development flavor.
  final bool? enableDesignSystem;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: profileRepository),
        RepositoryProvider.value(value: propertyRepository),
        RepositoryProvider.value(value: onboardingRepository),
        RepositoryProvider.value(value: valuationRepository),
        RepositoryProvider.value(value: notificationRepository),
        RepositoryProvider<GeoRepository>(
          lazy: false,
          create: (_) => geoRepository ?? GeoRepository(),
          dispose: (repository) => repository.close(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            lazy: false,
            create: (_) =>
                AppBloc(authRepository: authRepository)
                  ..add(const AppUserSubscriptionRequested()),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => ProfileCubit(
              authRepository: authRepository,
              profileRepository: profileRepository,
            ),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => LoginCubit(authRepository: authRepository),
          ),
        ],
        child: AppView(
          enableDesignSystem: enableDesignSystem ?? appFlavor == 'development',
        ),
      ),
    );
  }
}

class AppView extends StatefulWidget {
  const new({required this.enableDesignSystem, super.key});

  final bool enableDesignSystem;

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  late final List<StreamListenable> _refreshListenables;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final appBloc = context.read<AppBloc>();
    final profileCubit = context.read<ProfileCubit>();
    _refreshListenables = [
      StreamListenable(appBloc.stream),
      StreamListenable(profileCubit.stream),
    ];
    _router = createAppRouter(
      appBloc: appBloc,
      profileCubit: profileCubit,
      onboardingRepository: context.read<OnboardingRepository>(),
      refreshListenable: Listenable.merge(_refreshListenables),
      enableDesignSystem: widget.enableDesignSystem,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    for (final listenable in _refreshListenables) {
      listenable.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Forgets the e-mail and the accepted terms on sign-out.
    return BlocListener<AppBloc, AppState>(
      listenWhen: (previous, current) =>
          previous.status == AppStatus.authenticated &&
          current.status == AppStatus.unauthenticated,
      listener: (context, _) => context.read<LoginCubit>().reset(),
      child: MaterialApp.router(
        title: 'Realesty',
        theme: realestyTheme(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      ),
    );
  }
}
