import 'package:nexus_core/nexus_core.dart';

/// The staff roster (D-042). Staff are not app users. Reads work offline from
/// the local cache.
abstract interface class StaffRepository {
  /// Active staff of [locationId], by name. For the POS attendance screen.
  Stream<List<StaffMember>> watchActive(String locationId);

  /// Every staff member of [locationId], active or not, by name. For the
  /// Admin's roster.
  Stream<List<StaffMember>> watchAll(String locationId);
}

/// Roster changes. Admin only (`staff.manage`) and online, because a new
/// member gets a Firestore auto ID (D-042).
abstract interface class StaffService {
  /// Adds an active staff member. [name] and [role] are cleaned and checked
  /// with `StaffMember.nameError` and `roleError`; a bad value throws
  /// [ArgumentError].
  Future<StaffMember> create({
    required String locationId,
    required String name,
    String role = '',
  });

  /// Changes the name, role or active flag; whatever is null stays.
  Future<void> update({
    required String locationId,
    required String staffId,
    String? name,
    String? role,
    bool? active,
  });
}
