/// Why a data-layer call failed. The UI maps each reason to a message.
///
/// Calculator validation errors (`BillValidationException`,
/// `ReturnValidationException`) come from `nexus_core` and are thrown
/// unchanged, before anything is written.
enum FailureReason {
  /// Sign-in failed: wrong email or password.
  invalidCredentials,

  /// The user exists but `active == false` (D-018).
  userDisabled,

  /// Signed in, but there is no `users/{uid}` doc or role.
  noProfile,

  /// The user's role lacks the permission, or it's another location.
  notPermitted,

  /// This install has no device code yet (D-004).
  deviceNotRegistered,

  /// New billing is blocked by the offline limit (D-016).
  billingBlocked,

  /// The operation needs the network and there is none (registration,
  /// creating users, first sign-in).
  offline,

  /// A referenced document doesn't exist.
  notFound,

  /// The request breaks a business rule not covered by the calculators,
  /// e.g. cancelling a bill on a later day (D-009) or after a return (D-025).
  ruleViolation,

  unknown,
}

final class DataFailure implements Exception {
  const DataFailure(this.reason, [this.detail = '']);

  final FailureReason reason;
  final String detail;

  @override
  String toString() => 'DataFailure(${reason.name}): $detail';
}
