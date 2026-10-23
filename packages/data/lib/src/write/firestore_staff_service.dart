import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/staff.dart';
import '../plans/staff_plans.dart';
import '../sync/connectivity.dart';
import 'plan_committer.dart';
import 'write_env.dart';

/// [StaffService] on Firestore (D-042): the Admin's roster changes. These
/// are **online** writes: the new member gets a Firestore auto ID, which
/// must not be created twice by a retry, so nothing here relies on the
/// offline queue. Each change is committed with [committer] awaited
/// against the server (`FirestorePlanCommitter(awaitServer: true)`) and
/// refused with `DataFailure(offline)` when the network monitor says there
/// is no connection. A rejection by the rules comes back as a [DataFailure]
/// (`notPermitted`).
final class FirestoreStaffService implements StaffService {
  FirestoreStaffService({
    required WriteEnv env,
    required FirebaseFirestore firestore,
    required PlanCommitter committer,
    required NetworkMonitor network,
  }) : _env = env,
       _db = firestore,
       _committer = committer,
       _network = network;

  final WriteEnv _env;
  final FirebaseFirestore _db;
  final PlanCommitter _committer;
  final NetworkMonitor _network;

  @override
  Future<StaffMember> create({
    required String locationId,
    required String name,
    String role = '',
  }) async {
    final s = _env.requireAt(Permission.staffManage, locationId);
    final ctx = _env.context(s, locationId: locationId, at: _env.now());
    // Dry run first, so a bad name never uses an ID or touches the network.
    StaffPlans.create(
      ctx: ctx,
      locationId: locationId,
      staffId: 'x',
      name: name,
      role: role,
    );
    await _requireOnline();
    final id = _db.collection(FirestorePaths.staff(locationId)).doc().id;
    final planned = StaffPlans.create(
      ctx: ctx,
      locationId: locationId,
      staffId: id,
      name: name,
      role: role,
    );
    await _committer.commit(planned.plan);
    return planned.value;
  }

  @override
  Future<void> update({
    required String locationId,
    required String staffId,
    String? name,
    String? role,
    bool? active,
  }) async {
    final s = _env.requireAt(Permission.staffManage, locationId);
    final plan = StaffPlans.update(
      ctx: _env.context(s, locationId: locationId, at: _env.now()),
      locationId: locationId,
      staffId: staffId,
      name: name,
      role: role,
      active: active,
    );
    await _requireOnline();
    await _committer.commit(plan);
  }

  Future<void> _requireOnline() async {
    if (!await _network.isOnline()) {
      throw const DataFailure(
        FailureReason.offline,
        'the roster can only be changed online',
      );
    }
  }
}
