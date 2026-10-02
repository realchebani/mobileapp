import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sale_repository/sale_repository.dart';

part 'valuation_state.dart';

/// The certified valuation of the current dossier (V9 hero, V9b report),
/// shared by the seller space tabs (provided by `SellerTabScaffold`).
class ValuationCubit extends Cubit<ValuationState> {
  new({
    required this._valuationRepository,
    this._timeout = const Duration(seconds: 15),
  }) : super(const ValuationState());

  final ValuationRepository _valuationRepository;
  final Duration _timeout;

  /// Loads the latest valuation of [propertyId] (the current one stays
  /// shown while it loads).
  Future<void> load(String propertyId) async {
    if (state.status == ValuationStatus.loading) return;
    emit(state.copyWith(status: ValuationStatus.loading));
    try {
      final valuation = await _valuationRepository
          .getLatestValuation(propertyId)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        ValuationState(status: ValuationStatus.success, valuation: valuation),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ValuationStatus.failure));
    }
  }
}
