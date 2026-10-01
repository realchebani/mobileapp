import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

/// What the "Tendance IA" card of V8 shows.
enum AiEstimateStatus {
  /// No card (draft or certified dossier).
  hidden,

  /// The estimate is being computed.
  computing,

  /// The estimate is available.
  ready,

  /// No estimate for this property (fewer than 5 comparable sales…): the
  /// expert takes over.
  unavailable,

  /// The computation or its reading failed: "Réessayer".
  failed,
}

class AiEstimateState extends Equatable {
  const new({this.status = AiEstimateStatus.hidden, this.snapshot});

  final AiEstimateStatus status;

  /// The definitive result (ready / unavailable).
  final MarketSnapshot? snapshot;

  @override
  List<Object?> get props => [status, snapshot];
}

/// Reads the non-certified estimate of a sent dossier (EPIC-05).
///
/// The computation is requested when the dossier is sent (V7); V8 only
/// requests it again when no attempt exists (the app was closed before the
/// request reached the backend) or, through [retry], after a failure. The
/// backend never recomputes a definitive result. While it computes, the
/// snapshot is polled every [_pollInterval], at most [_maxPolls] times.
class AiEstimateCubit extends Cubit<AiEstimateState> {
  new({
    required this._propertyRepository,
    required this._propertyId,
    required this._enabled,
    this._pollInterval = const Duration(seconds: 3),
    this._maxPolls = 60,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const AiEstimateState());

  /// A computation running for longer than this has died on the backend.
  static const staleAfter = Duration(minutes: 3);

  final PropertyRepository _propertyRepository;
  final String _propertyId;
  final bool _enabled;
  final Duration _pollInterval;
  final int _maxPolls;
  final DateTime Function() _now;

  /// Bumped to stop a previous polling loop.
  int _generation = 0;

  /// Reads the current state of the estimate (and requests it when there
  /// was never any attempt).
  Future<void> load() async {
    if (!_enabled) return;
    emit(const AiEstimateState(status: AiEstimateStatus.computing));
    final MarketSnapshot? snapshot;
    try {
      snapshot = await _propertyRepository.getMarketSnapshot(_propertyId);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      _emit(const AiEstimateState(status: AiEstimateStatus.failed));
      return;
    }
    if (snapshot == null) {
      await _request();
      return;
    }
    if (!_settle(snapshot)) await _poll(++_generation);
  }

  /// Requests the estimate again after a failure.
  Future<void> retry() async {
    if (state.status != AiEstimateStatus.failed) return;
    emit(const AiEstimateState(status: AiEstimateStatus.computing));
    await _request();
  }

  Future<void> _request() async {
    try {
      await _propertyRepository.requestEstimate(_propertyId);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      _emit(const AiEstimateState(status: AiEstimateStatus.failed));
      return;
    }
    await _poll(++_generation);
  }

  /// Applies [snapshot]; returns false while it is still computing.
  bool _settle(MarketSnapshot snapshot) {
    switch (snapshot.status) {
      case MarketSnapshotStatus.ok:
        _emit(
          AiEstimateState(status: AiEstimateStatus.ready, snapshot: snapshot),
        );
      case MarketSnapshotStatus.insufficient:
        _emit(
          AiEstimateState(
            status: AiEstimateStatus.unavailable,
            snapshot: snapshot,
          ),
        );
      case MarketSnapshotStatus.error:
        _emit(const AiEstimateState(status: AiEstimateStatus.failed));
      case MarketSnapshotStatus.running:
        if (_now().difference(snapshot.createdAt) < staleAfter) return false;
        _emit(const AiEstimateState(status: AiEstimateStatus.failed));
    }
    return true;
  }

  Future<void> _poll(int generation) async {
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_pollInterval);
      if (isClosed || generation != _generation) return;
      try {
        final snapshot = await _propertyRepository.getMarketSnapshot(
          _propertyId,
        );
        if (snapshot != null && _settle(snapshot)) return;
      } on Object catch (error, stackTrace) {
        // A reading failure while polling: try again at the next tick.
        addError(error, stackTrace);
      }
    }
    _emit(const AiEstimateState(status: AiEstimateStatus.failed));
  }

  void _emit(AiEstimateState state) {
    if (!isClosed) emit(state);
  }
}
