import 'dart:developer';

import 'package:bloc/bloc.dart';

/// Logs every bloc state change and error.
class AppBlocObserver extends BlocObserver {
  const new({this._log = log});

  final void Function(String message) _log;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    _log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    _log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}
