import 'package:nexus_core/nexus_core.dart';

/// One mark in a batch (D-042).
final class AttendanceMark {
  const AttendanceMark({
    required this.staffId,
    required this.staffName,
    required this.status,
    this.note,
  });

  final String staffId;

  /// The name now, stored with the mark so reports never need the roster.
  final String staffName;
  final AttendanceStatus status;

  /// Up to `Limits.attendanceNoteMax` characters, or null.
  final String? note;
}

/// Marking and reading attendance (D-042).
abstract interface class AttendanceService {
  /// Marks every staff member in [marks] for [businessDate] at the signed-in
  /// user's location with `set`, so a repeat overwrites (last write wins) and
  /// a retry is harmless. Chunks into batches of at most
  /// `Limits.maxAttendanceBatch`, and works offline.
  ///
  /// Throws `DataFailure(ruleViolation)` when [businessDate] is in the
  /// future or more than `Limits.attendanceBackDays` days before today
  /// (client-enforced, D-031), when a note is too long, or when [marks]
  /// names the same staff member twice; `notPermitted` without
  /// `attendance.mark`; `deviceNotRegistered` without a device code.
  Future<void> mark(String businessDate, List<AttendanceMark> marks);
}

abstract interface class AttendanceRepository {
  /// The marks of one day at [locationId]. Served from the local cache when
  /// offline.
  Stream<List<AttendanceRecord>> watchDay(String locationId, String date);

  /// The marks of one month (`YYYY-MM`) at [locationId], by date then name.
  /// About 30 reads per staff member, so the Admin loads one store at a time.
  Stream<List<AttendanceRecord>> watchMonth(
    String locationId,
    String monthKey,
  );

  /// One day's marks across every location, for the Admin's "who hasn't
  /// marked today" view (`report.all`). A collection-group query.
  Stream<List<AttendanceRecord>> watchDayAllLocations(String date);
}
