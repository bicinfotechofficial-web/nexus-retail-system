import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Plans for the staff roster (D-042). The Admin keeps it, online.
abstract final class StaffPlans {
  /// A new, active staff member at [locationId] under [staffId] (a Firestore
  /// auto ID, so the plan stays pure). The doc holds exactly what rule #15
  /// lets a create carry: the name, role and `active`, `createdBy` and the
  /// server time.
  ///
  /// Throws `DataFailure(ruleViolation)` for a name or role the roster
  /// doesn't accept, or an unusable [staffId].
  static PlannedWrite<StaffMember> create({
    required PlanContext ctx,
    required String locationId,
    required String staffId,
    required String name,
    String role = '',
  }) {
    _checkLocation(locationId);
    if (!Ids.isSafeKey(staffId)) {
      throw DataFailure(FailureReason.ruleViolation, 'bad staff id $staffId');
    }
    final n = _name(name);
    final r = _role(role);
    final member = StaffMember(
      id: staffId,
      name: n,
      role: r,
      active: true,
      locationId: locationId,
      createdBy: ctx.uid,
    );
    final plan =
        (PlanBuilder()
              ..create(FirestorePaths.staffMember(locationId, staffId), {
                ...member.toMap(),
                'createdBy': ctx.uid,
                'createdAt': serverTimestamp,
              }))
            .build();
    return PlannedWrite(member, plan);
  }

  /// Changes the name, role or `active` of a member; whatever is null stays.
  /// Writes only those fields and the update stamp (rule #15). Nothing to
  /// change is `DataFailure(ruleViolation)`.
  static WritePlan update({
    required PlanContext ctx,
    required String locationId,
    required String staffId,
    String? name,
    String? role,
    bool? active,
  }) {
    _checkLocation(locationId);
    if (!Ids.isSafeKey(staffId)) {
      throw DataFailure(FailureReason.ruleViolation, 'bad staff id $staffId');
    }
    if (name == null && role == null && active == null) {
      throw const DataFailure(FailureReason.ruleViolation, 'nothing to change');
    }
    return (PlanBuilder()
          ..update(FirestorePaths.staffMember(locationId, staffId), {
            'name': ?(name == null ? null : _name(name)),
            'role': ?(role == null ? null : _role(role)),
            'active': ?active,
            'updatedBy': ctx.uid,
            'updatedAt': serverTimestamp,
          }))
        .build();
  }

  static void _checkLocation(String locationId) {
    if (!Ids.isLocationCode(locationId)) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'bad location $locationId',
      );
    }
  }

  static String _name(String raw) {
    final problem = StaffMember.nameError(raw);
    if (problem != null) {
      throw DataFailure(FailureReason.ruleViolation, 'name: $problem');
    }
    return StaffMember.cleanText(raw);
  }

  static String _role(String raw) {
    final problem = StaffMember.roleError(raw);
    if (problem != null) {
      throw DataFailure(FailureReason.ruleViolation, 'role: $problem');
    }
    return StaffMember.cleanText(raw);
  }
}
