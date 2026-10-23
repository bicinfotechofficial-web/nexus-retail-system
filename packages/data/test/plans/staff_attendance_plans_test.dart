import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

Matcher _failure(FailureReason r) =>
    isA<DataFailure>().having((f) => f.reason, 'reason', r);

AttendanceMark _mark(
  int i, {
  AttendanceStatus status = AttendanceStatus.present,
  String? note,
}) => AttendanceMark(
  staffId: 'staff$i',
  staffName: 'Person $i',
  status: status,
  note: note,
);

void main() {
  group('StaffPlans.create', () {
    final planned = StaffPlans.create(
      ctx: Fx.admin(),
      locationId: 'PTB',
      staffId: 'aB3dE',
      name: '  Asha   Baker ',
      role: ' Baker ',
    );

    test('one create at the roster path with exactly the rule #15 keys', () {
      expect(planned.plan.paths, ['locations/PTB/staff/aB3dE']);
      expect(planned.plan.ops.single.kind, WriteKind.create);
      expect(planned.plan.ops.single.data, {
        'name': 'Asha Baker',
        'role': 'Baker',
        'active': true,
        'createdBy': 'admin',
        'createdAt': serverTimestamp,
      });
    });

    test('the member is active, cleaned and carries its location', () {
      final m = planned.value;
      expect(m.id, 'aB3dE');
      expect(m.name, 'Asha Baker');
      expect(m.role, 'Baker');
      expect(m.active, isTrue);
      expect(m.locationId, 'PTB');
      expect(m.createdBy, 'admin');
    });

    test('a bad name, role, ID or location is a ruleViolation', () {
      Object? failure(void Function() f) {
        try {
          f();
        } on Object catch (e) {
          return e;
        }
        return null;
      }

      _Call call({
        String name = 'Asha',
        String role = '',
        String id = 'a1',
        String loc = 'PTB',
      }) =>
          () => StaffPlans.create(
            ctx: Fx.admin(),
            locationId: loc,
            staffId: id,
            name: name,
            role: role,
          );
      for (final bad in [
        call(name: '   '),
        call(name: 'x' * (Limits.staffNameMax + 1)),
        call(role: 'y' * (Limits.staffRoleMax + 1)),
        call(id: 'has space'),
        call(id: 'a/b'),
        call(loc: 'ptb'),
      ]) {
        expect(failure(bad), _failure(FailureReason.ruleViolation));
      }
      // The limits themselves are fine.
      call(name: 'x' * Limits.staffNameMax, role: 'y' * Limits.staffRoleMax)();
    });
  });

  group('StaffPlans.update', () {
    test('writes only what changed, with the update stamp', () {
      final plan = StaffPlans.update(
        ctx: Fx.admin(),
        locationId: 'PTB',
        staffId: 'a1',
        name: ' Asha K ',
        active: false,
      );
      expect(plan.paths, ['locations/PTB/staff/a1']);
      expect(plan.ops.single.kind, WriteKind.update);
      expect(plan.ops.single.data, {
        'name': 'Asha K',
        'active': false,
        'updatedBy': 'admin',
        'updatedAt': serverTimestamp,
      });
    });

    test('the role can be cleared to empty', () {
      final plan = StaffPlans.update(
        ctx: Fx.admin(),
        locationId: 'PTB',
        staffId: 'a1',
        role: '',
      );
      expect(plan.ops.single.data['role'], '');
    });

    test('nothing to change, or a bad value, is a ruleViolation', () {
      expect(
        () => StaffPlans.update(
          ctx: Fx.admin(),
          locationId: 'PTB',
          staffId: 'a1',
        ),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => StaffPlans.update(
          ctx: Fx.admin(),
          locationId: 'PTB',
          staffId: 'a1',
          name: '',
        ),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });
  });

  group('AttendancePlans.mark', () {
    List<WritePlan> mark(
      List<AttendanceMark> marks, {
      String date = Fx.today,
      PlanContext? ctx,
    }) => AttendancePlans.mark(
      ctx: ctx ?? Fx.sm(),
      businessDate: date,
      marks: marks,
      markedByName: 'Store Manager PTB',
    );

    test('one whole-document create per mark, the ID {date}_{staffId}', () {
      final plans = mark([
        _mark(1),
        _mark(2, status: AttendanceStatus.halfDay, note: ' left at noon '),
        _mark(3, status: AttendanceStatus.absent),
      ]);
      expect(plans, hasLength(1));
      final p = plans.single;
      expect(p.paths, [
        'locations/PTB/attendance/2026-09-26_staff1',
        'locations/PTB/attendance/2026-09-26_staff2',
        'locations/PTB/attendance/2026-09-26_staff3',
      ]);
      expect(p.ops.map((o) => o.kind), everyElement(WriteKind.create));
      expect(p.ops[1].data, {
        'staffId': 'staff2',
        'staffName': 'Person 2',
        'businessDate': '2026-09-26',
        'status': 'HALF_DAY',
        'note': 'left at noon',
        'markedBy': {'uid': 'sm-ptb', 'name': 'Store Manager PTB'},
        'deviceId': 'D01',
        'editedAt': serverTimestamp,
      });
      expect(p.ops[0].data['note'], isNull);
      expect(p.ops[2].data['status'], 'ABSENT');
    });

    test('an empty or blank note is stored as null', () {
      final p = mark([_mark(1, note: '   ')]).single;
      expect(p.ops.single.data['note'], isNull);
    });

    test('chunks of Limits.maxAttendanceBatch: 15, 15 and 3 for 33 marks', () {
      final plans = mark([for (var i = 1; i <= 33; i++) _mark(i)]);
      expect(plans.map((p) => p.ops.length), [
        Limits.maxAttendanceBatch,
        Limits.maxAttendanceBatch,
        3,
      ]);
      final all = [for (final p in plans) ...p.paths];
      expect(all.toSet(), hasLength(33));
      expect(all.first, 'locations/PTB/attendance/2026-09-26_staff1');
      expect(all.last, 'locations/PTB/attendance/2026-09-26_staff33');
    });

    test('exactly 15 marks are one batch; none is no batch', () {
      expect(mark([for (var i = 1; i <= 15; i++) _mark(i)]), hasLength(1));
      expect(mark(const []), isEmpty);
    });

    test(
      'today and 7 days back are marked, 8 days back or tomorrow are not',
      () {
        expect(mark([_mark(1)], date: '2026-09-19'), hasLength(1));
        expect(
          () => mark([_mark(1)], date: '2026-09-18'),
          throwsA(_failure(FailureReason.ruleViolation)),
        );
        expect(
          () => mark([_mark(1)], date: '2026-09-27'),
          throwsA(_failure(FailureReason.ruleViolation)),
        );
        expect(
          () => mark([_mark(1)], date: '2026/09/26'),
          throwsA(_failure(FailureReason.ruleViolation)),
        );
      },
    );

    test('the window follows the business date (IST), not the UTC date', () {
      // 2026-09-26 23:30 UTC is already 2026-09-27 in IST.
      final late = Fx.sm(at: DateTime.utc(2026, 9, 26, 23, 30));
      expect(mark([_mark(1)], date: '2026-09-27', ctx: late), hasLength(1));
      expect(AttendancePlans.earliest('2026-09-27'), '2026-09-20');
    });

    test('a note of exactly 100 characters passes, 101 does not', () {
      expect(
        mark([_mark(1, note: 'n' * Limits.attendanceNoteMax)]),
        hasLength(1),
      );
      expect(
        () => mark([_mark(1, note: 'n' * (Limits.attendanceNoteMax + 1))]),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });

    test('the same staff member twice, a bad ID or an empty name is refused '
        'before anything is built', () {
      expect(
        () => mark([_mark(1), _mark(1, status: AttendanceStatus.absent)]),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => mark([
          const AttendanceMark(
            staffId: 'a b',
            staffName: 'X',
            status: AttendanceStatus.present,
          ),
        ]),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => mark([
          const AttendanceMark(
            staffId: 'a1',
            staffName: ' ',
            status: AttendanceStatus.present,
          ),
        ]),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });

    test('a user without a location or device is refused', () {
      expect(
        () => mark([_mark(1)], ctx: Fx.admin()),
        throwsA(_failure(FailureReason.notPermitted)),
      );
      expect(
        () => mark([
          _mark(1),
        ], ctx: PlanContext(uid: 'sm-ptb', locationId: 'PTB', now: Fx.now)),
        throwsA(_failure(FailureReason.deviceNotRegistered)),
      );
    });
  });
}

typedef _Call = void Function();
