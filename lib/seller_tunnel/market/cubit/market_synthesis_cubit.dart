import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

enum MarketSynthesisStatus {
  loading,

  /// An estimate is available ([MarketSynthesisState.snapshot] is `ok`).
  ready,

  /// No estimate (yet) for the property.
  unavailable,
  failure,
}

class MarketSynthesisState extends Equatable {
  const new({this.status = MarketSynthesisStatus.loading, this.snapshot});

  final MarketSynthesisStatus status;
  final MarketSnapshot? snapshot;

  @override
  List<Object?> get props => [status, snapshot];
}

/// V8b · reads the non-certified estimate of the property (read-only).
class MarketSynthesisCubit extends Cubit<MarketSynthesisState> {
  new({required this._propertyRepository, required this._propertyId})
    : super(const MarketSynthesisState());

  /// Delay after which reading is considered failed.
  static const timeout = Duration(seconds: 15);

  final PropertyRepository _propertyRepository;
  final String _propertyId;

  Future<void> load() async {
    emit(const MarketSynthesisState());
    try {
      final snapshot = await _propertyRepository
          .getMarketSnapshot(_propertyId)
          .timeout(timeout);
      if (isClosed) return;
      emit(
        snapshot != null && snapshot.status == MarketSnapshotStatus.ok
            ? MarketSynthesisState(
                status: MarketSynthesisStatus.ready,
                snapshot: snapshot,
              )
            : const MarketSynthesisState(
                status: MarketSynthesisStatus.unavailable,
              ),
      );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      if (!isClosed) {
        emit(const MarketSynthesisState(status: MarketSynthesisStatus.failure));
      }
    }
  }
}
