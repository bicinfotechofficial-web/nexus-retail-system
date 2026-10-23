import '../enums.dart';
import '../ids.dart';
import '../limits.dart';
import '../map_reader.dart';
import 'sales.dart';

/// `locations/{loc}/staff/{staffId}` (D-042): a member of the store's staff.
/// Staff are not app users. The Admin keeps the roster, and a person who
/// leaves is set inactive, never deleted, so old attendance keeps a name.
final class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.active,
    this.role = '',
    this.locationId,
    this.createdBy,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
  });

  factory StaffMember.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'staff $id');
    return StaffMember(
      id: id,
      name: r.string('name'),
      role: r.stringOrNull('role') ?? '',
      active: r.boolean('active'),
      createdBy: r.stringOrNull('createdBy'),
      createdAt: r.dateTimeOrNull('createdAt'),
      updatedBy: r.stringOrNull('updatedBy'),
      updatedAt: r.dateTimeOrNull('updatedAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'createdAt', 'updatedAt'};

  /// A name the roster accepts, trimmed and with runs of spaces collapsed, or
  /// a message saying why not.
  static String? nameError(String raw) {
    final n = cleanText(raw);
    if (n.isEmpty) return 'Enter the name.';
    if (n.length > Limits.staffNameMax) {
      return 'At most ${Limits.staffNameMax} characters.';
    }
    return null;
  }

  static String? roleError(String raw) {
    if (cleanText(raw).length > Limits.staffRoleMax) {
      return 'At most ${Limits.staffRoleMax} characters.';
    }
    return null;
  }

  /// Trims and collapses whitespace.
  static String cleanText(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  final String id;
  final String name;

  /// A free label such as "Baker"; may be empty.
  final String role;
  final bool active;

  /// Which location's roster this is. Not stored: the repository fills it
  /// from the document path.
  final String? locationId;
  final String? createdBy;
  final DateTime? createdAt;
  final String? updatedBy;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
    'name': name,
    'role': role,
    'active': active,
  };
}

/// `locations/{loc}/attendance/{businessDate}_{staffId}` (D-042): one
/// staff member's mark for one day. Written with `set`, so marking again
/// overwrites it and a retry is harmless.
final class AttendanceRecord {
  AttendanceRecord({
    required this.staffId,
    required this.staffName,
    required this.businessDate,
    required this.status,
    required this.markedBy,
    required this.deviceId,
    this.note,
    this.editedAt,
    this.locationId,
  }) {
    final n = note;
    if (n != null && n.length > Limits.attendanceNoteMax) {
      throw ArgumentError.value(n, 'note', 'too long');
    }
  }

  factory AttendanceRecord.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'attendance $id');
    return AttendanceRecord(
      staffId: r.string('staffId'),
      staffName: r.string('staffName'),
      businessDate: r.string('businessDate'),
      status: r.enumValue('status', AttendanceStatus.fromWire),
      note: r.stringOrNull('note'),
      markedBy: ServedBy.fromReader(r.child('markedBy')),
      deviceId: r.string('deviceId'),
      editedAt: r.dateTimeOrNull('editedAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'editedAt'};

  /// `2026-10-23_8fK2xQ`.
  String get id => Ids.attendanceId(businessDate, staffId);

  final String staffId;

  /// The name when marked, so a report never needs the roster.
  final String staffName;
  final String businessDate;
  final AttendanceStatus status;
  final String? note;
  final ServedBy markedBy;
  final String deviceId;

  /// Server time of the last write; null until it reaches the server.
  final DateTime? editedAt;

  /// Which location this is. Not stored: the repository fills it from the
  /// document path.
  final String? locationId;

  Map<String, Object?> toMap() => {
    'staffId': staffId,
    'staffName': staffName,
    'businessDate': businessDate,
    'status': status.wire,
    'note': note,
    'markedBy': markedBy.toMap(),
    'deviceId': deviceId,
  };
}

/// One staff member's totals for a month (D-042).
final class AttendanceTotals {
  const AttendanceTotals({
    required this.staffId,
    required this.staffName,
    required this.present,
    required this.halfDays,
    required this.absent,
  });

  final String staffId;
  final String staffName;
  final int present;
  final int halfDays;
  final int absent;

  /// Days marked at all.
  int get marked => present + halfDays + absent;

  /// Present days plus half a day for each half-day.
  double get daysWorked => present + halfDays * 0.5;
}

/// Builds the monthly grid's totals (D-042). Staff with no record in the
/// month still get a row of zeros, in roster order. A record for someone not
/// on [roster] (since deactivated and removed from the list passed in) still
/// gets a row, named from the record, after the roster.
List<AttendanceTotals> attendanceTotals(
  List<StaffMember> roster,
  List<AttendanceRecord> records,
) {
  final byStaff = <String, List<AttendanceRecord>>{};
  for (final r in records) {
    (byStaff[r.staffId] ??= []).add(r);
  }
  AttendanceTotals totalsFor(String id, String name) {
    final list = byStaff[id] ?? const <AttendanceRecord>[];
    int count(AttendanceStatus s) => list.where((r) => r.status == s).length;
    return AttendanceTotals(
      staffId: id,
      staffName: name,
      present: count(AttendanceStatus.present),
      halfDays: count(AttendanceStatus.halfDay),
      absent: count(AttendanceStatus.absent),
    );
  }

  final rosterIds = {for (final s in roster) s.id};
  return [
    for (final s in roster) totalsFor(s.id, s.name),
    for (final e in byStaff.entries)
      if (!rosterIds.contains(e.key)) totalsFor(e.key, e.value.first.staffName),
  ];
}
