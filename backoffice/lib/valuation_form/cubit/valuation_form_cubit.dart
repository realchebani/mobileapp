import 'dart:async';
import 'dart:typed_data';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'valuation_form_state.dart';

/// Technical sheet lines pre-filled from the fill sheet of the dossier
/// (step « technical »), with the provenance of the dossier.
List<JsonMap> technicalSheetFrom(Dossier dossier) => [
  for (final row in dossier.fillSheet)
    if (row.step == 'technical' && row.value != null && row.confirmed != false)
      {
        'label': _clip(row.label, 60),
        'value': _clip(row.value!, 200),
        'provenance': switch (row.source) {
          'extrait' => 'document',
          'externe' => 'external',
          _ => 'declared',
        },
      },
];

/// Sales of the DVF snapshot as comparables (street without number; the
/// sales without a public street are left out). The expert ticks the ones
/// to exclude.
List<JsonMap> comparablesFrom(Dossier dossier) => [
  for (final sale in Json.maps(dossier.market?['comparables']))
    if (Json.text(sale['street']) case final String street)
      {
        'street': _clip(street, 120),
        if (Json.number(sale['area_m2']) case final num area) 'area_m2': area,
        if (Json.integer(sale['land_m2']) case final int land) 'land_m2': land,
        'price_eur': Json.integer(sale['price_eur']),
        'excluded': false,
      },
];

String _clip(String text, int max) => text.runes.length <= max
    ? text
    : String.fromCharCodes(text.runes.take(max));

/// The valuation form: a draft saved automatically (optimistic lock),
/// checked with the shared validator, then certified (expert, admin) or
/// submitted for approval (partner).
class ValuationFormCubit extends Cubit<ValuationFormState> {
  new({
    required this._repository,
    required this.propertyId,
    required ValuationDraft? draft,
    JsonMap initialPayload = const {},
    this.autosaveDelay = const Duration(seconds: 5),
  }) : super(
         draft == null
             ? ValuationFormState(payload: initialPayload)
             : ValuationFormState(
                 payload: draft.payload,
                 version: draft.version,
                 draftStatus: draft.status,
                 savedAt: draft.updatedAt,
                 approvalNote: draft.approvalNote,
                 submittedByName: draft.submittedByName,
               ),
       );

  final BackOfficeRepository _repository;
  final String propertyId;
  final Duration autosaveDelay;
  Timer? _timer;
  Future<void>? _saving;

  /// Sets [key] (null removes it) and saves a few seconds later.
  void setField(String key, Object? value) {
    final payload = {...state.payload};
    if (value == null) {
      payload.remove(key);
    } else {
      payload[key] = value;
    }
    emit(state.copyWith(payload: payload, saveStatus: SaveStatus.dirty));
    _timer?.cancel();
    _timer = Timer(autosaveDelay, () => unawaited(save().catchError((_) {})));
  }

  /// Saves now (waits for a save in progress, then saves again if needed).
  Future<void> save() async {
    _timer?.cancel();
    if (_saving != null) await _saving;
    if (state.saveStatus != SaveStatus.dirty &&
        state.saveStatus != SaveStatus.failure) {
      return;
    }
    final saving = _save();
    _saving = saving;
    try {
      await saving;
    } finally {
      _saving = null;
    }
  }

  Future<void> _save() async {
    final payload = state.payload;
    emit(state.copyWith(saveStatus: SaveStatus.saving));
    try {
      final version = await _repository.saveDraft(
        propertyId,
        payload,
        expectedVersion: state.version,
      );
      emit(
        state.copyWith(
          version: version,
          savedAt: DateTime.now(),
          saveStatus: identical(payload, state.payload)
              ? SaveStatus.saved
              : SaveStatus.dirty,
        ),
      );
    } on BackOfficeFailure catch (failure) {
      emit(
        state.copyWith(
          saveStatus: failure.reason == BackOfficeFailureReason.draftConflict
              ? SaveStatus.conflict
              : SaveStatus.failure,
          conflictBy: () => failure.details,
        ),
      );
      rethrow;
    }
  }

  /// Takes the draft saved by someone else (after a conflict).
  void reset(ValuationDraft? draft) {
    _timer?.cancel();
    emit(
      ValuationFormState(
        payload: draft?.payload ?? const {},
        version: draft?.version ?? 0,
        draftStatus: draft?.status ?? ValuationDraftStatus.editing,
        savedAt: draft?.updatedAt,
        approvalNote: draft?.approvalNote,
        submittedByName: draft?.submittedByName,
      ),
    );
  }

  Future<T> _run<T>(FormAction action, Future<T> Function() run) async {
    emit(state.copyWith(action: action));
    try {
      return await run();
    } finally {
      emit(state.copyWith(action: FormAction.none));
    }
  }

  /// Expert / admin: saves, then certifies; returns the valuation id.
  Future<String> certify() => _run(FormAction.certifying, () async {
    await save();
    return await _repository.certify(propertyId, version: state.version);
  });

  /// Partner: saves, then hands the draft over.
  Future<void> submitForApproval() => _run(FormAction.submitting, () async {
    await save();
    await _repository.submitForApproval(propertyId, version: state.version);
    emit(
      state.copyWith(
        draftStatus: ValuationDraftStatus.submittedForApproval,
        approvalNote: () => null,
      ),
    );
  });

  /// Expert / admin: sends a submitted draft back with [note].
  Future<void> returnDraft(String note) => _run(FormAction.returning, () async {
    await _repository.returnDraft(propertyId, note);
    emit(
      state.copyWith(
        draftStatus: ValuationDraftStatus.editing,
        approvalNote: () => note,
      ),
    );
  });

  /// Expert / admin: the PDF of the certified valuation.
  Future<void> uploadReport(Uint8List pdf, int pages) => _run(
    FormAction.uploading,
    () => _repository.uploadReport(propertyId, pdf, pages: pages),
  );

  @override
  Future<void> close() async {
    _timer?.cancel();
    await super.close();
  }
}
