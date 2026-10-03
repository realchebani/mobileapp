part of 'dossier_cubit.dart';

enum DossierLoad { loading, ready, failure }

class DossierState extends Equatable {
  const new({
    this.load = DossierLoad.loading,
    this.dossier,
    this.photoUrls = const {},
    this.audit,
    this.busy = false,
  });

  final DossierLoad load;
  final Dossier? dossier;

  /// Signed URLs of the room photos already asked (5 minutes).
  final Map<String, String> photoUrls;

  /// Journal of this dossier, once the Journal tab asked for it.
  final List<AuditEntry>? audit;

  /// An action is running (buttons disabled).
  final bool busy;

  DossierState copyWith({
    DossierLoad? load,
    Dossier? dossier,
    Map<String, String>? photoUrls,
    List<AuditEntry>? audit,
    bool? busy,
  }) => DossierState(
    load: load ?? this.load,
    dossier: dossier ?? this.dossier,
    photoUrls: photoUrls ?? this.photoUrls,
    audit: audit ?? this.audit,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [load, dossier, photoUrls, audit, busy];
}
