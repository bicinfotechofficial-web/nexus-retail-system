import 'package:nexus_core/nexus_core.dart';

/// The signed-in user with their role and location, prefetched at login and
/// kept fresh by snapshot listeners (03-SYNC §8).
final class SessionContext {
  const SessionContext({
    required this.user,
    required this.role,
    required this.location,
  });

  final AppUser user;
  final Role role;

  /// The user's own location. Null for roles with `allLocations` (Admin).
  final Location? location;

  bool can(String permission) => user.active && role.can(permission);

  /// [can] and allowed at [locationId] (04-PERMISSIONS `canAt`).
  bool canAt(String permission, String locationId) =>
      can(permission) && (role.allLocations || user.locationId == locationId);
}

abstract interface class AuthService {
  /// Emits on sign-in, sign-out, and any change to the user, role or
  /// location docs. Null means signed out.
  Stream<SessionContext?> get session;

  SessionContext? get current;

  /// Throws `DataFailure` with invalidCredentials, userDisabled, noProfile
  /// or offline.
  Future<SessionContext> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();
}
