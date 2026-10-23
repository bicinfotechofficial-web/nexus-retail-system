import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 23, 4);
  const by = ServedBy(uid: 'u1', name: 'Manager');

  AttendanceRecord rec(
    String staffId,
    String date,
    AttendanceStatus status, {
    String name = 'Asha',
    String? note,
  }) => AttendanceRecord(
    staffId: staffId,
    staffName: name,
    businessDate: date,
    status: status,
    markedBy: by,
    deviceId: 'D01',
    note: note,
  );

  group('AttendanceStatus', () {
    test('wire names and day values', () {
      expect(AttendanceStatus.fromWire('PRESENT'), AttendanceStatus.present);
      expect(AttendanceStatus.fromWire('HALF_DAY').dayValue, 0.5);
      expect(AttendanceStatus.absent.dayValue, 0);
      expect(() => AttendanceStatus.fromWire('LEAVE'), throwsFormatException);
    });
  });

  group('attendance IDs', () {
    test('build and parse', () {
      final id = Ids.attendanceId('2026-10-23', '8fK2xQ');
      expect(id, '2026-10-23_8fK2xQ');
      final parts = Ids.parseAttendanceId(id)!;
      expect(parts.businessDate, '2026-10-23');
      expect(parts.staffId, '8fK2xQ');
    });

    test('a bad date or staff ID is rejected', () {
      expect(() => Ids.attendanceId('23-10-2026', 'a'), throwsArgumentError);
      expect(() => Ids.attendanceId('2026-10-23', 'a b'), throwsArgumentError);
      expect(Ids.parseAttendanceId('nonsense'), isNull);
      expect(Ids.parseAttendanceId('2026-10-23_'), isNull);
    });

    test('paths', () {
      expect(FirestorePaths.staff('PTB'), 'locations/PTB/staff');
      expect(
        FirestorePaths.attendanceDoc('PTB', '2026-10-23_a'),
        'locations/PTB/attendance/2026-10-23_a',
      );
      expect(
        FirestorePaths.order('PTB', 'D01-O000001'),
        'locations/PTB/orders/D01-O000001',
      );
    });
  });

  group('StaffMember', () {
    test('round trip and defaults', () {
      final s = StaffMember.fromMap('s1', {
        'name': 'Asha',
        'role': 'Baker',
        'active': true,
        'createdBy': 'u1',
        'createdAt': at,
      });
      expect(s.name, 'Asha');
      expect(s.role, 'Baker');
      expect(s.toMap(), {'name': 'Asha', 'role': 'Baker', 'active': true});
      final bare = StaffMember.fromMap('s2', {'name': 'Ravi', 'active': false});
      expect(bare.role, '');
      expect(bare.active, isFalse);
    });

    test('validation', () {
      expect(StaffMember.nameError('  '), isNotNull);
      expect(StaffMember.nameError('Asha'), isNull);
      expect(StaffMember.nameError('x' * 61), isNotNull);
      expect(StaffMember.nameError('x' * 60), isNull);
      expect(StaffMember.roleError('x' * 31), isNotNull);
      expect(StaffMember.roleError(''), isNull);
      expect(StaffMember.cleanText('  Asha   K  '), 'Asha K');
    });
  });

  group('AttendanceRecord', () {
    test('round trip keeps every stored field', () {
      final r = rec(
        's1',
        '2026-10-23',
        AttendanceStatus.halfDay,
        note: 'Left 2pm',
      );
      expect(r.id, '2026-10-23_s1');
      final stored = {...r.toMap(), 'editedAt': at};
      final back = AttendanceRecord.fromMap(r.id, stored);
      expect(back.toMap(), r.toMap());
      expect(back.editedAt, at);
      expect(back.status, AttendanceStatus.halfDay);
      expect(back.note, 'Left 2pm');
      expect(back.markedBy.name, 'Manager');
    });

    test('a note over the limit is rejected', () {
      expect(
        () =>
            rec('s1', '2026-10-23', AttendanceStatus.present, note: 'x' * 101),
        throwsArgumentError,
      );
      expect(
        rec('s1', '2026-10-23', AttendanceStatus.present, note: 'x' * 100).note,
        hasLength(100),
      );
    });
  });

  group('attendanceTotals', () {
    const roster = [
      StaffMember(id: 'a', name: 'Asha', active: true),
      StaffMember(id: 'b', name: 'Ravi', active: true),
      StaffMember(id: 'c', name: 'Meena', active: false),
    ];

    test('counts per person, zero rows for the unmarked, roster order', () {
      final totals = attendanceTotals(roster, [
        rec('a', '2026-10-01', AttendanceStatus.present),
        rec('a', '2026-10-02', AttendanceStatus.present),
        rec('a', '2026-10-03', AttendanceStatus.halfDay),
        rec('a', '2026-10-04', AttendanceStatus.absent),
        rec('b', '2026-10-01', AttendanceStatus.absent, name: 'Ravi'),
      ]);
      expect(totals.map((t) => t.staffId), ['a', 'b', 'c']);
      expect(totals[0].present, 2);
      expect(totals[0].halfDays, 1);
      expect(totals[0].absent, 1);
      expect(totals[0].marked, 4);
      expect(totals[0].daysWorked, 2.5);
      expect(totals[1].daysWorked, 0);
      expect(totals[2].marked, 0);
    });

    test(
      'someone not on the roster still gets a row, named from the record',
      () {
        final totals = attendanceTotals(roster, [
          rec('z', '2026-10-01', AttendanceStatus.present, name: 'Gone'),
        ]);
        expect(totals.last.staffId, 'z');
        expect(totals.last.staffName, 'Gone');
        expect(totals.last.present, 1);
      },
    );
  });

  group('permissions for D-042 and D-043', () {
    test(
      'the manager marks attendance and manages orders; only the admin keeps the roster',
      () {
        expect(
          SeedRoles.storeManagerPermissions,
          contains(Permission.attendanceMark),
        );
        expect(
          SeedRoles.storeManagerPermissions,
          contains(Permission.orderManage),
        );
        expect(
          SeedRoles.storeManagerPermissions,
          isNot(contains(Permission.staffManage)),
        );
        expect(SeedRoles.adminPermissions, contains(Permission.staffManage));
      },
    );
  });
}
