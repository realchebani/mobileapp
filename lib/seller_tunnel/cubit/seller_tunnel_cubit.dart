import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:property_repository/property_repository.dart';

part 'seller_tunnel_state.dart';

/// One seller dossier (a property) and its child
/// collections, shared by every screen of that property: its home, the
/// tunnel steps, V8b, V9b (provided by `PropertyRouteScope`, one cubit per
/// property kept by `SellerTunnelCubits` for the whole seller space).
///
/// [load] fetches the property and its child collections. Step screens save
/// their answers with [saveAndContinue] (or [save]); they manage child rows
/// with the `PropertyRepository` (from the context) and report the changes
/// with [updateChildren].
///
/// EPIC-16: it also keeps the pending answers (values said by voice for
/// another step, `pending_answers`) and resolves them once the step that
/// shows them is saved; as the [VoicePendingSink] of the voice sheets it
/// records the new ones and saves the updates of validated steps.
class SellerTunnelCubit extends Cubit<SellerTunnelState>
    implements VoicePendingSink {
  new({
    required this._propertyRepository,
    required this._propertyId,
    this._timeout = defaultTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const SellerTunnelState());

  /// Delay after which loading or saving is considered failed.
  static const defaultTimeout = Duration(seconds: 15);

  final PropertyRepository _propertyRepository;
  final Duration _timeout;
  final DateTime Function() _clock;

  final String _propertyId;

  /// Loads the property and its child collections.
  Future<void> load() async {
    if (state.status == SellerTunnelStatus.loading) return;
    emit(const SellerTunnelState(status: SellerTunnelStatus.loading));
    try {
      final repository = _propertyRepository;
      final id = _propertyId;
      final property = await repository.getProperty(id).timeout(_timeout);
      final (owners, parcels, estimates, rooms, items, documents) = await (
        repository.getOwners(id),
        repository.getParcels(id),
        repository.getPreviousEstimates(id),
        repository.getRooms(id),
        repository.getLifestyleItems(id),
        repository.getDocuments(id),
      ).wait.timeout(_timeout);
      if (isClosed) return;
      emit(
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: property,
          owners: owners,
          parcels: parcels,
          previousEstimates: estimates,
          rooms: rooms,
          lifestyleItems: items,
          documents: documents,
        ),
      );
      await _loadPending();
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        SellerTunnelState(
          status: SellerTunnelStatus.failure,
          notFound: error is PropertyNotFoundFailure,
        ),
      );
    }
  }

  /// Loads the dossier again, after a failure.
  Future<void> retry() => load();

  /// Reloads the dossier in the background (pull to refresh on the seller
  /// space): unlike [load], the current state stays shown while it loads
  /// and is kept on failure, which is rethrown (the caller tells the user).
  Future<void> refresh() async {
    final current = state.property;
    if (current == null || state.status != SellerTunnelStatus.success) return;
    try {
      final repository = _propertyRepository;
      final id = current.id;
      final (property, owners, rooms, items, documents) = await (
        repository.getProperty(id),
        repository.getOwners(id),
        repository.getRooms(id),
        repository.getLifestyleItems(id),
        repository.getDocuments(id),
      ).wait.timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          property: property,
          owners: owners,
          rooms: rooms,
          lifestyleItems: items,
          documents: documents,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      rethrow;
    }
    await _loadPending();
  }

  /// Loads the open pending answers (best effort: the tunnel works
  /// without them). An answer whose value is already saved was accepted
  /// but its resolution was lost: it is resolved again.
  Future<void> _loadPending() async {
    final property = state.property;
    if (property == null || property.status != PropertyStatus.draft) return;
    try {
      final answers = await _propertyRepository
          .getPendingAnswers(property.id)
          .timeout(_timeout);
      if (isClosed) return;
      emit(state.copyWith(pendingAnswers: answers));
      final row = property.toJson();
      final settled = [
        for (final answer in answers)
          if (answer.kind == PendingKind.field &&
              sameStoredValue(row[answer.field], answer.value))
            answer.id,
      ];
      await resolvePending({PendingResolution.continueTapped: settled});
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
    }
  }

  /// Closes pending answers (best effort: they leave the state at once; a
  /// failure keeps them open server-side, resolved again at the next
  /// load, idempotent).
  Future<void> resolvePending(
    Map<PendingResolution, List<String>> resolutions,
  ) async {
    final ids = {for (final list in resolutions.values) ...list};
    if (ids.isEmpty) return;
    if (!isClosed) {
      emit(
        state.copyWith(
          pendingAnswers: [
            for (final answer in state.pendingAnswers)
              if (!ids.contains(answer.id)) answer,
          ],
          // Right after « Continuer »: the navigation still applies.
          nextStep: state.nextStep,
          continuedFrom: state.continuedFrom,
        ),
      );
    }
    for (final MapEntry(key: resolution, value: list) in resolutions.entries) {
      if (list.isEmpty) continue;
      try {
        await _propertyRepository
            .resolvePendingAnswers(list, resolution)
            .timeout(_timeout);
      } on Object catch (error, stackTrace) {
        if (!isClosed) addError(error, stackTrace);
      }
    }
  }

  @override
  void pendingRecorded(List<AgentCrossStep> items, List<String> supersededIds) {
    final property = state.property;
    if (isClosed || property == null) return;
    if (items.isEmpty && supersededIds.isEmpty) return;
    final replaced = {...supersededIds, for (final item in items) item.id};
    emit(
      state.copyWith(
        pendingAnswers: [
          for (final answer in state.pendingAnswers)
            if (!replaced.contains(answer.id)) answer,
          for (final item in items)
            PendingAnswer(
              id: item.id,
              propertyId: property.id,
              targetStep: item.targetStep.value,
              kind: _kindOf(item.kind),
              field: item.field,
              value: item.value,
              label: item.label,
              changedLabel: item.changedLabel,
              quote: item.quote,
              confidence: item.confidence,
              sourceStep: '',
              createdAt: _clock(),
            ),
        ],
      ),
    );
  }

  static PendingKind _kindOf(AgentCrossStepKind kind) => switch (kind) {
    AgentCrossStepKind.field => PendingKind.field,
    AgentCrossStepKind.room => PendingKind.room,
    AgentCrossStepKind.previousEstimate => PendingKind.previousEstimate,
    AgentCrossStepKind.lifestyleItem => PendingKind.lifestyleItem,
    AgentCrossStepKind.note => PendingKind.note,
  };

  @override
  bool isStepValidated(AgentStep step) =>
      state.isValidated(SellerTunnelState.stepOfTarget(step.value));

  /// « Oui » to the update of a validated step: saves the value (or appends
  /// the note) with its origin, then accepts the pending answer.
  @override
  Future<bool> acceptPendingUpdate(String id) async {
    final property = state.property;
    final answer = state.pendingAnswers.where((a) => a.id == id).firstOrNull;
    if (property == null || answer == null) return false;
    final source = FieldSource(
      kind: FieldSourceKind.dictatedElsewhere,
      at: _clock(),
      turnId: answer.turnId,
      pendingId: answer.id,
      confirmation: FieldConfirmation.update,
    );
    final Map<String, Object?> patch;
    if (answer.kind == PendingKind.field) {
      final field = answer.field!;
      patch = {
        field: answer.value,
        PropertyColumns.provenance: property.mergeProvenance({
          field: Provenance.declared,
        }),
        PropertyColumns.fieldSources: property.mergeFieldSources({
          field: source,
        }),
      };
    } else if (answer.kind == PendingKind.note) {
      final current = property.stepNoteOf(answer.targetStep) ?? '';
      final text = [
        if (current.trim().isNotEmpty) current.trim(),
        '${answer.value}',
      ].join(' · ');
      patch = {
        PropertyColumns.stepNotes: property.withStepNote(
          answer.targetStep,
          text.length > StepNoteKeys.maxLength
              ? text.substring(0, StepNoteKeys.maxLength)
              : text,
        ),
        PropertyColumns.fieldSources: property.mergeFieldSources({
          StepNoteKeys.sourceKey(answer.targetStep): source,
        }),
      };
    } else {
      return false;
    }
    await _save(patch);
    if (isClosed || state.saveStatus != SellerTunnelSaveStatus.success) {
      return false;
    }
    await resolvePending({
      PendingResolution.yes: [id],
    });
    return true;
  }

  @override
  Future<void> rejectPending(String id, {required bool cancelled}) =>
      resolvePending({
        cancelled ? PendingResolution.cancelled : PendingResolution.no: [id],
      });

  /// Saves the columns of [patch] (keys from `PropertyColumns`).
  ///
  /// `saveStatus` goes through [SellerTunnelSaveStatus.inProgress] to
  /// [SellerTunnelSaveStatus.success] (with the updated property) or
  /// [SellerTunnelSaveStatus.failure].
  Future<void> save(Map<String, Object?> patch) => _save(patch);

  /// [save], then closes the pending answers the screen showed ([resolve],
  /// EPIC-16).
  Future<void> saveStep(
    Map<String, Object?> patch, {
    Map<PendingResolution, List<String>> resolve = const {},
  }) async {
    await _save(patch);
    await _resolveAfterSave(resolve);
  }

  Future<void> _resolveAfterSave(
    Map<PendingResolution, List<String>> resolve,
  ) async {
    if (resolve.isEmpty || state.saveStatus != SellerTunnelSaveStatus.success) {
      return;
    }
    await resolvePending(resolve);
  }

  /// Saves [patch] for [step] and moves the resume point past it. On
  /// success, `nextStep` is the screen to open (`PropertyRouteScope`
  /// navigates to it): the next screen of the type of the property (the
  /// type given by [patch] when it changes it, on V3).
  Future<void> saveAndContinue(
    SellerTunnelStep step, [
    Map<String, Object?> patch = const {},
  ]) => _saveAndContinue(step, patch, const {});

  /// [saveAndContinue], then closes the pending answers the screen showed
  /// ([resolve], EPIC-16).
  Future<void> saveStepAndContinue(
    SellerTunnelStep step,
    Map<String, Object?> patch, {
    Map<PendingResolution, List<String>> resolve = const {},
  }) => _saveAndContinue(step, patch, resolve);

  Future<void> _saveAndContinue(
    SellerTunnelStep step,
    Map<String, Object?> patch,
    Map<PendingResolution, List<String>> resolve,
  ) async {
    final next = _profileAfter(patch).nextAfter(step);
    final currentStep = state.property?.currentStep ?? 1;
    await _save({
      ...patch,
      PropertyColumns.currentStep: next.number > currentStep
          ? next.number
          : currentStep,
    }, from: step);
    await _resolveAfterSave(resolve);
  }

  /// The profile of the property once [patch] is saved.
  PropertyTypeProfile _profileAfter(Map<String, Object?> patch) {
    if (!patch.containsKey(PropertyColumns.propertyType)) return state.profile;
    return PropertyTypeProfile.of(
      patch[PropertyColumns.propertyType] as PropertyType?,
    );
  }

  Future<void> _save(
    Map<String, Object?> patch, {
    SellerTunnelStep? from,
  }) async {
    final property = state.property;
    if (property == null || state.isSaving) return;
    emit(state.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress));
    try {
      final updated = await _propertyRepository
          .updateProperty(property.id, patch)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          property: updated,
          saveStatus: SellerTunnelSaveStatus.success,
          nextStep: from == null
              ? null
              : PropertyTypeProfile.of(updated.propertyType).nextAfter(from),
          continuedFrom: from,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(saveStatus: SellerTunnelSaveStatus.failure));
    }
  }

  /// Replaces the given child collections after a step saved them.
  void updateChildren({
    List<PropertyOwner>? owners,
    List<PropertyParcel>? parcels,
    List<PreviousEstimate>? previousEstimates,
    List<Room>? rooms,
    List<LifestyleItem>? lifestyleItems,
    List<PropertyDocument>? documents,
  }) {
    emit(
      state.copyWith(
        owners: owners,
        parcels: parcels,
        previousEstimates: previousEstimates,
        rooms: rooms,
        lifestyleItems: lifestyleItems,
        documents: documents,
      ),
    );
  }
}
