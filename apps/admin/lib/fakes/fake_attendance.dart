import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'live.dart';

/// A mark as the tests write it: [locationId] is filled in like the real
/// repository fills it from the document path.
AttendanceRecord mark(
  String locationId,
  String date,
  String staffId,
  String staffName,
  AttendanceStatus status, {
  String? note,
}) => AttendanceRecord(
  staffId: staffId,
  staffName: staffName,
  businessDate: date,
  status: status,
  note: note,
  markedBy: const ServedBy(uid: 'sm-1', name: 'Store Manager'),
  deviceId: 'D01',
  locationId: locationId,
);

/// An in-memory `AttendanceRepository`. It records every month it was asked
/// for, so a test can check that only one store's month is ever read.
final class FakeAttendanceRepository implements AttendanceRepository {
  FakeAttendanceRepository([List<AttendanceRecord> seed = const []])
    : _all = Live(List.of(seed));

  final Live<List<AttendanceRecord>> _all;

  /// `PTB 2026-09` for each `watchMonth`.
  final List<String> monthReads = [];

  /// The dates asked of `watchDayAllLocations`.
  final List<String> allLocationReads = [];

  void add(AttendanceRecord r) => _all.value = [..._all.value, r];

  @override
  Stream<List<AttendanceRecord>> watchDay(String locationId, String date) =>
      _all.watch(
        (l) => [
          for (final r in l)
            if (r.locationId == locationId && r.businessDate == date) r,
        ],
      );

  @override
  Stream<List<AttendanceRecord>> watchMonth(
    String locationId,
    String monthKey,
  ) {
    monthReads.add('$locationId $monthKey');
    return _all.watch(
      (l) => [
        for (final r in l)
          if (r.locationId == locationId &&
              r.businessDate.startsWith('$monthKey-'))
            r,
      ]..sort((a, b) => a.businessDate.compareTo(b.businessDate)),
    );
  }

  @override
  Stream<List<AttendanceRecord>> watchDayAllLocations(String date) {
    allLocationReads.add(date);
    return _all.watch(
      (l) => [
        for (final r in l)
          if (r.businessDate == date) r,
      ],
    );
  }
}
