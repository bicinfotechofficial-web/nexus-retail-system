/// QA-10: staff attendance end to end (D-042, PLAN section T), on a model of
/// the server that stores one document per staff member per day under the
/// ID `{businessDate}_{staffId}` and writes it with `set` (04-PERMISSIONS
/// #16), and phones that queue marks offline and send them on sync.
///
/// The emulator rules suite (`firebase/test/attendance.test.js`) pins the
/// field checks and the store scope; the 7-day window is client-enforced
/// and tested in `packages/data/test/plans/staff_attendance_plans_test.dart`.
/// These scenarios cover what spans phones, days and the month grid.
library;

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

const ServedBy manager = ServedBy(uid: 'uid-sm-ptb', name: 'Store Manager');
const ServedBy admin = ServedBy(uid: 'uid-admin', name: 'Admin');

StaffMember staff(String id, String name, {bool active = true}) =>
    StaffMember(id: id, name: name, active: active);

/// 18:00 IST on [businessDate].
DateTime eveningOf(String businessDate) =>
    BusinessDate.startOf(businessDate).add(const Duration(hours: 18));

/// The attendance documents of one store, as the server holds them.
final class AttendanceServer {
  final Map<String, AttendanceRecord> docs = {};

  /// A batch of marks, all or nothing, each a `set` on its own ID.
  void apply(List<AttendanceRecord> batch) {
    if (batch.length > Limits.maxAttendanceBatch) {
      throw StateError('batch over ${Limits.maxAttendanceBatch}');
    }
    for (final r in batch) {
      docs[r.id] = r;
    }
  }

  List<AttendanceRecord> month(String month) => [
    for (final r in docs.values)
      if (BusinessDate.monthOf(r.businessDate) == month) r,
  ];
}

/// A phone marking attendance: online it writes at once, offline it keeps
/// the batches and sends them in order on sync.
final class Phone {
  Phone(this.deviceId, this.server);

  final String deviceId;
  final AttendanceServer server;
  final List<List<AttendanceRecord>> queue = [];
  bool online = true;

  void mark(
    String businessDate,
    Map<StaffMember, AttendanceStatus> marks, {
    ServedBy by = manager,
    String? note,
  }) {
    final batch = [
      for (final MapEntry(key: s, value: status) in marks.entries)
        AttendanceRecord(
          staffId: s.id,
          staffName: s.name,
          businessDate: businessDate,
          status: status,
          note: note,
          markedBy: by,
          deviceId: deviceId,
        ),
    ];
    online ? server.apply(batch) : queue.add(batch);
  }

  void sync() {
    online = true;
    queue.forEach(server.apply);
    queue.clear();
  }
}

void main() {
  final asha = staff('st-asha', 'Asha');
  final binu = staff('st-binu', 'Binu');
  final chitra = staff('st-chitra', 'Chitra');

  late AttendanceServer server;
  late Phone p1;
  late Phone p2;

  setUp(() {
    server = AttendanceServer();
    p1 = Phone('D01', server);
    p2 = Phone('D02', server);
  });

  group('QA-10 T-1: marking twice leaves one document', () {
    test('a correction overwrites the day; the last write wins', () {
      p1.mark('2026-09-26', {asha: AttendanceStatus.absent});
      p1.mark('2026-09-26', {
        asha: AttendanceStatus.halfDay,
      }, note: 'Left at 2');
      expect(server.docs.keys, ['2026-09-26_st-asha']);
      final r = server.docs.values.single;
      expect(r.status, AttendanceStatus.halfDay);
      expect(r.note, 'Left at 2');
    });

    test('a retry of the same batch changes nothing', () {
      final marks = {
        asha: AttendanceStatus.present,
        binu: AttendanceStatus.absent,
      };
      p1.mark('2026-09-26', marks);
      final before = Map.of(server.docs);
      p1.mark('2026-09-26', marks);
      expect(server.docs.keys, before.keys);
      expect(
        server.docs.values.map((r) => r.status),
        before.values.map((r) => r.status),
      );
    });

    test('the ID is the date and the staff member, so two people on one day '
        'and one person on two days are separate documents', () {
      p1.mark('2026-09-26', {
        asha: AttendanceStatus.present,
        binu: AttendanceStatus.present,
      });
      p1.mark('2026-09-27', {asha: AttendanceStatus.present});
      expect(server.docs.keys.toSet(), {
        '2026-09-26_st-asha',
        '2026-09-26_st-binu',
        '2026-09-27_st-asha',
      });
      expect(Ids.parseAttendanceId('2026-09-26_st-binu'), (
        businessDate: '2026-09-26',
        staffId: 'st-binu',
      ));
    });
  });

  group('QA-10 T-2: offline marks sync', () {
    test('marks taken offline reach the server on sync, under the day they '
        'were marked for', () {
      p1.online = false;
      p1.mark('2026-09-25', {asha: AttendanceStatus.present});
      p1.mark('2026-09-26', {
        asha: AttendanceStatus.absent,
        binu: AttendanceStatus.present,
      });
      expect(server.docs, isEmpty);
      p1.sync();
      expect(server.docs, hasLength(3));
      expect(
        server.docs['2026-09-25_st-asha']!.status,
        AttendanceStatus.present,
      );
      expect(
        server.docs['2026-09-26_st-asha']!.status,
        AttendanceStatus.absent,
      );
    });

    test('two phones mark the same person offline: one document, and the '
        'phone that syncs last decides', () {
      p1.online = false;
      p2.online = false;
      p1.mark('2026-09-26', {asha: AttendanceStatus.present});
      p2.mark('2026-09-26', {asha: AttendanceStatus.absent});
      p2.sync();
      p1.sync();
      expect(server.docs.keys, ['2026-09-26_st-asha']);
      expect(server.docs.values.single.status, AttendanceStatus.present);
      expect(server.docs.values.single.deviceId, 'D01');
    });

    test('a full store of 15 goes in one batch; 16 is two', () {
      final many = [for (var i = 0; i < 16; i++) staff('st-$i', 'Staff $i')];
      p1.mark('2026-09-26', {
        for (final s in many.take(Limits.maxAttendanceBatch))
          s: AttendanceStatus.present,
      });
      expect(server.docs, hasLength(15));
      expect(
        () => server.apply([
          for (final s in many)
            AttendanceRecord(
              staffId: s.id,
              staffName: s.name,
              businessDate: '2026-09-26',
              status: AttendanceStatus.present,
              markedBy: manager,
              deviceId: 'D01',
            ),
        ]),
        throwsStateError,
      );
    });
  });

  group('QA-10 T-3: the IST day boundary', () {
    test('a mark at 23:59 IST is for that day, at 00:00 IST for the next', () {
      final lastMinute = DateTime.utc(2026, 9, 26, 18, 29);
      final midnight = DateTime.utc(2026, 9, 26, 18, 30);
      expect(BusinessDate.of(lastMinute), '2026-09-26');
      expect(BusinessDate.of(midnight), '2026-09-27');
      p1.mark(BusinessDate.of(lastMinute), {asha: AttendanceStatus.present});
      p1.mark(BusinessDate.of(midnight), {asha: AttendanceStatus.absent});
      expect(server.docs.keys.toSet(), {
        '2026-09-26_st-asha',
        '2026-09-27_st-asha',
      });
    });

    test('the last day of a month and the first of the next fall in their '
        'own month grids', () {
      p1.mark('2026-09-30', {asha: AttendanceStatus.present});
      p1.mark('2026-10-01', {asha: AttendanceStatus.present});
      expect(server.month('2026-09').map((r) => r.businessDate), [
        '2026-09-30',
      ]);
      expect(server.month('2026-10').map((r) => r.businessDate), [
        '2026-10-01',
      ]);
    });

    test('the window the POS offers is today and 7 days back, by IST date', () {
      const today = '2026-10-03';
      final earliest = BusinessDate.addDays(today, -Limits.attendanceBackDays);
      expect(earliest, '2026-09-26', reason: 'crosses the month boundary');
      expect(Limits.attendanceBackDays, 7);
      // The refusal of the 8th day back and of tomorrow is the data plan's:
      // packages/data/test/plans/staff_attendance_plans_test.dart.
    });
  });

  group('QA-10 T-4: the Admin sees the month totals', () {
    test('present, half-day (0.5) and absent add up per person; corrections '
        'count once', () {
      final roster = [asha, binu, chitra];
      p1.mark('2026-09-24', {
        asha: AttendanceStatus.present,
        binu: AttendanceStatus.halfDay,
        chitra: AttendanceStatus.absent,
      });
      p1.mark('2026-09-25', {
        asha: AttendanceStatus.present,
        binu: AttendanceStatus.present,
      });
      // A correction of the 24th from the other phone, offline.
      p2.online = false;
      p2.mark('2026-09-24', {chitra: AttendanceStatus.halfDay});
      p2.sync();

      final totals = {
        for (final t in attendanceTotals(roster, server.month('2026-09')))
          t.staffId: t,
      };
      expect(totals['st-asha']!.daysWorked, 2.0);
      expect(totals['st-binu']!.daysWorked, 1.5);
      expect(totals['st-chitra']!.daysWorked, 0.5);
      expect(
        totals['st-chitra']!.absent,
        0,
        reason: 'the absent was corrected',
      );
      expect(totals['st-chitra']!.marked, 1);
      expect(totals['st-asha']!.marked, 2);
    });

    test('a deactivated staff member keeps their past month; nobody marked '
        'gets a row of zeros', () {
      p1.mark('2026-09-10', {binu: AttendanceStatus.present});
      final rosterNow = [asha, staff('st-chitra', 'Chitra', active: false)];
      final totals = attendanceTotals(rosterNow, server.month('2026-09'));
      expect(totals.map((t) => t.staffId), ['st-asha', 'st-chitra', 'st-binu']);
      expect(totals.first.marked, 0);
      expect(totals.last.staffName, 'Binu');
      expect(totals.last.daysWorked, 1.0);
    });

    test('a month of 30 days and 10 staff is 300 documents, read straight '
        'from the marks (no stored summary)', () {
      final roster = [for (var i = 0; i < 10; i++) staff('st-$i', 'Staff $i')];
      for (var d = 1; d <= 30; d++) {
        final date = '2026-09-${d.toString().padLeft(2, '0')}';
        p1.mark(date, {
          for (final s in roster)
            s: d.isEven ? AttendanceStatus.present : AttendanceStatus.halfDay,
        });
      }
      final month = server.month('2026-09');
      expect(month, hasLength(300));
      for (final t in attendanceTotals(roster, month)) {
        expect(t.present, 15);
        expect(t.halfDays, 15);
        expect(t.daysWorked, 22.5);
      }
    });
  });

  group('QA-10 T-5: permissions per role (seeded roles, 04 role matrix)', () {
    test('the Store Manager marks but does not keep the roster; the Admin '
        'does both', () {
      expect(
        SeedRoles.storeManagerPermissions,
        contains(Permission.attendanceMark),
      );
      expect(
        SeedRoles.storeManagerPermissions,
        isNot(contains(Permission.staffManage)),
      );
      expect(
        SeedRoles.adminPermissions,
        containsAll([
          Permission.attendanceMark,
          Permission.staffManage,
          Permission.reportAll,
        ]),
      );
      // Another store, a disabled user, no user, deleting a mark or a staff
      // member, and the all-stores query as a Store Manager are refused by
      // the rules: firebase/test/attendance.test.js (#15, #16).
    });

    test('an Admin correction is recorded as theirs', () {
      p1.mark('2026-09-26', {asha: AttendanceStatus.absent});
      p2.mark('2026-09-26', {asha: AttendanceStatus.present}, by: admin);
      expect(server.docs.values.single.markedBy.uid, admin.uid);
    });
  });
}
