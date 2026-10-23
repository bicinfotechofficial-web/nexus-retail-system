import 'package:nexus_core/nexus_core.dart';

import '../api/attendance.dart';
import '../plans/attendance_plans.dart';
import 'write_env.dart';

/// [AttendanceService] on Firestore (D-042): marks go in batches of at most
/// `Limits.maxAttendanceBatch`, each a `set` of whole documents committed
/// locally without waiting for the server, so marking works offline. A
/// document is `{businessDate}_{staffId}`, so marking twice, or from two
/// phones, overwrites (last write wins) and a retry is harmless: there is no
/// counter and nothing is read first.
final class FirestoreAttendanceService implements AttendanceService {
  FirestoreAttendanceService(this._env);

  final WriteEnv _env;

  @override
  Future<void> mark(String businessDate, List<AttendanceMark> marks) async {
    final loc = _env.requireAtOwnLocation(Permission.attendanceMark);
    _env.requireDevice();
    final s = _env.requireSession();
    final plans = AttendancePlans.mark(
      ctx: _env.context(s, locationId: loc, at: _env.now()),
      businessDate: businessDate,
      marks: marks,
      markedByName: s.user.name,
    );
    // Every chunk is checked before the first is written, so a bad mark
    // never leaves half a day marked. Chunks then go one after the other.
    for (var i = 0; i < plans.length; i++) {
      await _env.write(
        plans[i],
        label:
            'Attendance for $businessDate at $loc '
            '(${i + 1} of ${plans.length})',
      );
    }
  }
}
