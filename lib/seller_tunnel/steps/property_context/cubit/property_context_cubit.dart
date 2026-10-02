import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/ui/format/realesty_format.dart';
import 'package:property_repository/property_repository.dart';

part 'property_context_state.dart';

/// Form of V3 · Contexte & type de bien.
///
/// [submit] validates the answers and saves the previous estimates (the
/// `previous_estimates` rows); on success the view hands the saved rows and
/// `PropertyContextState.patch` to the tunnel cubit.
class PropertyContextCubit extends Cubit<PropertyContextState> {
  new({
    required this._propertyRepository,
    required Property property,
    List<PreviousEstimate> estimates = const [],
    DateTime? today,
  }) : _propertyId = property.id,
       _saved = estimates,
       _nextKey = estimates.length + 1,
       super(_initialState(property, estimates, today ?? DateTime.now()));

  final PropertyRepository _propertyRepository;
  final String _propertyId;

  /// The estimates currently stored.
  List<PreviousEstimate> _saved;

  /// Key of the next estimate card.
  int _nextKey;

  /// Ids of the rows inserted for new cards, by card key.
  final Map<int, String?> _ids = {};

  static PropertyContextState _initialState(
    Property property,
    List<PreviousEstimate> estimates,
    DateTime today,
  ) {
    final purchasePrice = property.purchasePriceEur;
    final previouslyEstimated =
        property.previouslyEstimated ?? (estimates.isEmpty ? null : true);
    return PropertyContextState(
      today: today,
      propertyType: property.propertyType,
      propertyTypeOther: property.propertyTypeOther ?? '',
      landKind: property.landKind,
      parkingKind: property.parkingKind,
      commercialUse: property.commercialUse ?? '',
      unitsCount: property.unitsCount?.toString() ?? '',
      purchaseYear: property.purchaseYear?.toString() ?? '',
      purchasePrice: purchasePrice == null ? '' : frenchNumber(purchasePrice),
      selfBuilt: property.selfBuilt,
      saleReason: property.saleReason,
      previouslyEstimated: previouslyEstimated,
      estimates: [
        for (final (index, estimate) in estimates.indexed)
          EstimateDraft(
            key: index,
            id: estimate.id,
            price: frenchNumber(estimate.priceEur),
            month: estimate.estimatedMonth == null
                ? ''
                : PropertyContextState.formatMonth(estimate.estimatedMonth!),
            agency: estimate.agencyName ?? '',
          ),
        if (estimates.isEmpty && (previouslyEstimated ?? false))
          const EstimateDraft(key: 0),
      ],
    );
  }

  void propertyTypeSelected(PropertyType type) =>
      emit(state.copyWith(propertyType: type));

  void propertyTypeOtherChanged(String value) =>
      emit(state.copyWith(propertyTypeOther: value));

  /// Selects [kind], or clears it when it was selected (optional answer).
  void landKindToggled(LandKind kind) => emit(
    state.copyWith(landKind: () => state.landKind == kind ? null : kind),
  );

  /// Selects [kind], or clears it when it was selected (optional answer).
  void parkingKindToggled(ParkingKind kind) => emit(
    state.copyWith(parkingKind: () => state.parkingKind == kind ? null : kind),
  );

  void commercialUseChanged(String value) =>
      emit(state.copyWith(commercialUse: value));

  void unitsCountChanged(String value) =>
      emit(state.copyWith(unitsCount: value));

  void purchaseYearChanged(String value) =>
      emit(state.copyWith(purchaseYear: value));

  void purchasePriceChanged(String value) =>
      emit(state.copyWith(purchasePrice: value));

  void selfBuiltChanged({required bool selfBuilt}) =>
      emit(state.copyWith(selfBuilt: selfBuilt));

  /// Selects [reason], or clears it when it was selected (optional answer).
  void saleReasonToggled(SaleReason reason) => emit(
    state.copyWith(
      saleReason: () => state.saleReason == reason ? null : reason,
    ),
  );

  /// Answers "Déjà estimé par une agence ?"; "Oui" opens a first card.
  void previouslyEstimatedChanged({required bool previouslyEstimated}) {
    final opensCard = previouslyEstimated && state.estimates.isEmpty;
    emit(
      state.copyWith(
        previouslyEstimated: previouslyEstimated,
        estimates: [
          ...state.estimates,
          if (opensCard) EstimateDraft(key: _nextKey++),
        ],
      ),
    );
  }

  /// "Ajouter une autre agence".
  void estimateAdded() => emit(
    state.copyWith(
      estimates: [
        ...state.estimates,
        EstimateDraft(key: _nextKey++),
      ],
    ),
  );

  /// Removes the card [key] (deleted from the dossier on submit).
  void estimateRemoved(int key) => emit(
    state.copyWith(
      estimates: [
        for (final draft in state.estimates)
          if (draft.key != key) draft,
      ],
    ),
  );

  void estimateChanged(
    int key, {
    String? price,
    String? month,
    String? agency,
  }) => emit(
    state.copyWith(
      estimates: [
        for (final draft in state.estimates)
          if (draft.key == key)
            draft.copyWith(price: price, month: month, agency: agency)
          else
            draft,
      ],
    ),
  );

  /// "Continuer": shows the errors, or saves the previous estimates (the
  /// cards when the answer is "Oui", none otherwise).
  Future<void> submit() async {
    if (state.submission == PropertyContextSubmission.inProgress) return;
    if (!state.isValid) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
          submission: PropertyContextSubmission.idle,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        showErrors: true,
        submission: PropertyContextSubmission.inProgress,
      ),
    );
    final drafts = state.hasEstimates ? state.estimates : <EstimateDraft>[];
    try {
      final keptIds = {for (final draft in drafts) ?_idOf(draft)};
      for (final estimate in [..._saved]) {
        final id = estimate.id;
        if (id != null && !keptIds.contains(id)) {
          await _propertyRepository.deletePreviousEstimate(id);
          _saved = [
            for (final e in _saved)
              if (e.id != id) e,
          ];
        }
      }
      final saved = <PreviousEstimate>[];
      for (final draft in drafts) {
        final estimate = _estimateOf(draft);
        final stored = _saved.where(
          (e) => estimate.id != null && e.id == estimate.id,
        );
        if (stored.isNotEmpty && stored.first == estimate) {
          saved.add(stored.first);
          continue;
        }
        final result = await _propertyRepository.savePreviousEstimate(estimate);
        // Recorded at once, so that a retry after a later failure updates
        // this row instead of inserting it again.
        _ids[draft.key] = result.id;
        _saved = [
          for (final e in _saved)
            if (e.id != result.id) e,
          result,
        ];
        saved.add(result);
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          estimates: _withIds(drafts),
          savedEstimates: saved,
          submission: PropertyContextSubmission.success,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          estimates: _withIds(state.estimates),
          submission: PropertyContextSubmission.failure,
        ),
      );
    }
  }

  /// Id of the row of [draft]: loaded, or saved by a previous submission.
  String? _idOf(EstimateDraft draft) => draft.id ?? _ids[draft.key];

  List<EstimateDraft> _withIds(List<EstimateDraft> drafts) => [
    for (final draft in drafts) draft.withId(_idOf(draft)),
  ];

  PreviousEstimate _estimateOf(EstimateDraft draft) {
    final agency = draft.agency.trim();
    return PreviousEstimate(
      id: _idOf(draft),
      propertyId: _propertyId,
      priceEur: PropertyContextState.parseDigits(draft.price)!,
      estimatedMonth: PropertyContextState.parseMonth(draft.month),
      agencyName: agency.isEmpty ? null : agency,
    );
  }
}
