part of 'valuation_form_cubit.dart';

enum SaveStatus { saved, dirty, saving, conflict, failure }

enum FormAction { none, certifying, submitting, returning, uploading }

class ValuationFormState extends Equatable {
  const new({
    required this.payload,
    this.version = 0,
    this.draftStatus = ValuationDraftStatus.editing,
    this.saveStatus = SaveStatus.saved,
    this.conflictBy,
    this.savedAt,
    this.action = FormAction.none,
    this.approvalNote,
    this.submittedByName,
    this.touched = const {},
    this.showAllErrors = false,
  });

  final JsonMap payload;

  /// Version of the saved draft (0 before the first save).
  final int version;
  final ValuationDraftStatus draftStatus;
  final SaveStatus saveStatus;

  /// Who saved the draft in between (conflict).
  final String? conflictBy;
  final DateTime? savedAt;
  final FormAction action;
  final String? approvalNote;
  final String? submittedByName;

  /// Fields changed by the user (their errors show at once).
  final Set<String> touched;

  /// A certification or a submission was attempted: every error shows.
  final bool showAllErrors;

  /// Same rules as the database (`bo_validate_draft`).
  List<ValidationError> get errors => ValuationDraftValidator.validate(payload);

  /// The errors to show next to the fields: those of the fields already
  /// changed, or all of them after an attempt.
  List<ValidationError> get visibleErrors => [
    for (final error in errors)
      if (showAllErrors || touched.contains(_root(error.path))) error,
  ];

  static String _root(String path) => path.split(RegExp(r'[\[.]')).first;

  bool get isSubmitted =>
      draftStatus == ValuationDraftStatus.submittedForApproval;

  ValuationFormState copyWith({
    JsonMap? payload,
    int? version,
    ValuationDraftStatus? draftStatus,
    SaveStatus? saveStatus,
    String? Function()? conflictBy,
    DateTime? savedAt,
    FormAction? action,
    String? Function()? approvalNote,
    Set<String>? touched,
    bool? showAllErrors,
  }) => ValuationFormState(
    payload: payload ?? this.payload,
    version: version ?? this.version,
    draftStatus: draftStatus ?? this.draftStatus,
    saveStatus: saveStatus ?? this.saveStatus,
    conflictBy: conflictBy == null ? this.conflictBy : conflictBy(),
    savedAt: savedAt ?? this.savedAt,
    action: action ?? this.action,
    approvalNote: approvalNote == null ? this.approvalNote : approvalNote(),
    submittedByName: submittedByName,
    touched: touched ?? this.touched,
    showAllErrors: showAllErrors ?? this.showAllErrors,
  );

  @override
  List<Object?> get props => [
    payload,
    version,
    draftStatus,
    saveStatus,
    conflictBy,
    savedAt,
    action,
    approvalNote,
    submittedByName,
    touched,
    showAllErrors,
  ];
}
