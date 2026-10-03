import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

enum TeamStatus { loading, ready, failure }

class TeamState extends Equatable {
  const new({this.status = TeamStatus.loading, this.members = const []});

  final TeamStatus status;
  final List<StaffMember> members;

  @override
  List<Object?> get props => [status, members];
}

/// Admin: the team (add, update, remove an access).
class TeamCubit extends Cubit<TeamState> {
  new({required this._repository}) : super(const TeamState());

  final BackOfficeRepository _repository;

  Future<void> load() async {
    try {
      final members = await _repository.listTeam();
      emit(TeamState(status: TeamStatus.ready, members: members));
    } on Object {
      emit(const TeamState(status: TeamStatus.failure));
      rethrow;
    }
  }

  Future<void> upsert({
    required String email,
    required StaffRole role,
    required String displayName,
    required String initials,
    String? organisation,
  }) async {
    await _repository.upsertMember(
      email: email,
      role: role,
      displayName: displayName,
      initials: initials,
      organisation: organisation,
    );
    await load();
  }

  Future<void> deactivate(String userId) async {
    await _repository.deactivateMember(userId);
    await load();
  }
}
