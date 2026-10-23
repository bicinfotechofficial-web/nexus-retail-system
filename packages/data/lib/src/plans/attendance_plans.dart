import 'package:nexus_core/nexus_core.dart';

import '../api/attendance.dart';
import '../api/failures.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Plans for marking attendance (D-042).
abstract final class AttendancePlans {
  /// The batches that mark [marks] for [businessDate] at the context's
  /// location: one `set` of the whole document `{businessDate}_{staffId}` per
  /// mark, with `editedAt` as the server time, in chunks of at most
  /// `Limits.maxAttendanceBatch` so each batch stays inside the rules budget
  /// (D-030). Marking again overwrites (last write wins), so a retry is
  /// harmless and no document is read first. An empty list gives no plans.
  ///
  /// Throws `DataFailure(ruleViolation)` when [businessDate] is not a date,
  /// is in the future or is more than `Limits.attendanceBackDays` days
  /// before today (client-enforced, D-031), when a staff ID is not usable,
  /// when a name is empty or too long, when a note is longer than
  /// `Limits.attendanceNoteMax`, or when [marks] names a staff member twice.
  static List<WritePlan> mark({
    required PlanContext ctx,
    required String businessDate,
    required List<AttendanceMark> marks,
    required String markedByName,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    _checkDate(businessDate, ctx.businessDate);
    final seen = <String>{};
    final records = <AttendanceRecord>[];
    for (final m in marks) {
      if (!Ids.isSafeKey(m.staffId)) {
        throw DataFailure(
          FailureReason.ruleViolation,
          'bad staff id ${m.staffId}',
        );
      }
      if (!seen.add(m.staffId)) {
        throw DataFailure(
          FailureReason.ruleViolation,
          'staff ${m.staffId} is marked twice',
        );
      }
      final nameProblem = StaffMember.nameError(m.staffName);
      if (nameProblem != null) {
        throw DataFailure(
          FailureReason.ruleViolation,
          'name of ${m.staffId}: $nameProblem',
        );
      }
      final note = _note(m.staffId, m.note);
      records.add(
        AttendanceRecord(
          staffId: m.staffId,
          staffName: StaffMember.cleanText(m.staffName),
          businessDate: businessDate,
          status: m.status,
          note: note,
          markedBy: ServedBy(uid: ctx.uid, name: markedByName),
          deviceId: dev,
        ),
      );
    }
    final plans = <WritePlan>[];
    for (var i = 0; i < records.length; i += Limits.maxAttendanceBatch) {
      final chunk = records.sublist(
        i,
        i + Limits.maxAttendanceBatch > records.length
            ? records.length
            : i + Limits.maxAttendanceBatch,
      );
      final b = PlanBuilder();
      for (final r in chunk) {
        b.create(
          FirestorePaths.attendanceDoc(loc, r.id),
          withServerTimestamps(
            r.toMap(),
            AttendanceRecord.serverTimestampFields,
          ),
        );
      }
      plans.add(b.build());
    }
    return plans;
  }

  /// The earliest date the POS lets a manager mark, for [today].
  static String earliest(String today) =>
      BusinessDate.addDays(today, -Limits.attendanceBackDays);

  static void _checkDate(String businessDate, String today) {
    if (!BusinessDate.isValid(businessDate)) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'not a date: $businessDate',
      );
    }
    if (businessDate.compareTo(today) > 0) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'attendance cannot be marked for a future day',
      );
    }
    if (businessDate.compareTo(earliest(today)) < 0) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'attendance can only be marked up to '
        '${Limits.attendanceBackDays} days back',
      );
    }
  }

  /// The trimmed note, or null when there is none.
  static String? _note(String staffId, String? raw) {
    final n = raw?.trim();
    if (n == null || n.isEmpty) return null;
    if (n.length > Limits.attendanceNoteMax) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'note of $staffId is longer than ${Limits.attendanceNoteMax} '
        'characters',
      );
    }
    return n;
  }
}
