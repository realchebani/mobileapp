import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sale_repository/sale_repository.dart';

/// Loading of the seller's sales.
enum SalesStatus { initial, loading, success, failure }

/// The active sales of the seller.
final class SalesState extends Equatable {
  const new({this.status = SalesStatus.initial, this.sales = const []});

  final SalesStatus status;
  final List<Sale> sales;

  @override
  List<Object?> get props => [status, sales];
}

/// The active sales (not withdrawn) of the signed-in seller, for V9, the
/// lot page and "Mes biens" (EPIC-08). Provided by `SalesScope` above every
/// `/vendeur` screen when sales are available.
class SalesCubit extends Cubit<SalesState> {
  new({
    required this._repository,
    required this._ownerId,
    this._timeout = const Duration(seconds: 15),
  }) : super(const SalesState());

  final SaleRepository _repository;
  final String _ownerId;
  final Duration _timeout;

  /// Loads (or reloads) the sales; a failed reload keeps the list.
  Future<void> load() async {
    emit(SalesState(status: SalesStatus.loading, sales: state.sales));
    try {
      final sales = await _repository.listSales(_ownerId).timeout(_timeout);
      if (isClosed) return;
      emit(SalesState(status: SalesStatus.success, sales: sales));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(SalesState(status: SalesStatus.failure, sales: state.sales));
    }
  }
}
