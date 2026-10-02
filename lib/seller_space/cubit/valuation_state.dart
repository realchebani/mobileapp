part of 'valuation_cubit.dart';

enum ValuationStatus { initial, loading, success, failure }

final class ValuationState extends Equatable {
  const new({this.status = ValuationStatus.initial, this.valuation});

  final ValuationStatus status;

  /// The latest valuation; null until loaded or when there is none.
  final Valuation? valuation;

  ValuationState copyWith({ValuationStatus? status}) =>
      ValuationState(status: status ?? this.status, valuation: valuation);

  @override
  List<Object?> get props => [status, valuation];
}
