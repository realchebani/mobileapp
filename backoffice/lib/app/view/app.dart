import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/browser/browser.dart';
import 'package:realesty_backoffice/app/config/backoffice_config.dart';
import 'package:realesty_backoffice/app/router/app_router.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// The back-office: repositories, session and router.
class App extends StatelessWidget {
  const new({
    required this.authRepository,
    required this.repository,
    required this.config,
    required this.browser,
    this.initialLocation = '/',
    super.key,
  });

  final BackOfficeAuthRepository authRepository;
  final BackOfficeRepository repository;
  final BackOfficeConfig config;
  final Browser browser;
  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: repository),
        RepositoryProvider.value(value: config),
        RepositoryProvider.value(value: browser),
      ],
      child: BlocProvider(
        create: (_) {
          final cubit = SessionCubit(
            auth: authRepository,
            repository: repository,
          );
          unawaited(cubit.refresh());
          return cubit;
        },
        child: AppView(initialLocation: initialLocation),
      ),
    );
  }
}

class AppView extends StatefulWidget {
  const new({this.initialLocation = '/', super.key});

  final String initialLocation;

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  late final GoRouter _router = createRouter(
    context.read<SessionCubit>(),
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: realestyTheme(),
      locale: const Locale('fr'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
