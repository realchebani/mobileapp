part of 'mfa_cubit.dart';

enum MfaStatusValue { idle, loading, verifying, verified, invalidCode, failure }

class MfaState extends Equatable {
  const new({
    this.factorId,
    this.enrollment,
    this.code = '',
    this.status = MfaStatusValue.idle,
  });

  final String? factorId;

  /// Set during the first enrolment (QR code to scan).
  final TotpEnrollment? enrollment;
  final String code;
  final MfaStatusValue status;

  bool get isBusy =>
      status == MfaStatusValue.loading || status == MfaStatusValue.verifying;

  MfaState copyWith({required MfaStatusValue status, String? code}) => MfaState(
    factorId: factorId,
    enrollment: enrollment,
    code: code ?? this.code,
    status: status,
  );

  @override
  List<Object?> get props => [factorId, enrollment, code, status];
}
