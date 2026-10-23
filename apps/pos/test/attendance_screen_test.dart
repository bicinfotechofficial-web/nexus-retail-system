import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';
import 'support/preorder_fakes.dart';

/// POS-20: the Store Manager's attendance screen (D-042).
const _today = '2026-09-26';

List<StaffMember> _roster() => const [
  StaffMember(id: 'baker1', name: 'Anita', role: 'Baker', active: true),
  StaffMember(id: 'helper1', name: 'Bala', role: 'Helper', active: true),
  StaffMember(id: 'gone1', name: 'Chitra', role: 'Helper', active: false),
  StaffMember(id: 'cashier1', name: 'Dev', active: true),
];

AttendanceRecord _record(
  String staffId,
  String name,
  AttendanceStatus status, {
  String date = _today,
  String? note,
}) => AttendanceRecord(
  staffId: staffId,
  staffName: name,
  businessDate: date,
  status: status,
  note: note,
  markedBy: const ServedBy(uid: Seed.userId, name: 'PTB Store Manager'),
  deviceId: Seed.deviceId,
);

Future<(FakeBackend, PreorderFakes)> open(
  WidgetTester tester, {
  List<StaffMember>? staff,
  SyncStatus sync = const Online(),
  void Function(PreorderFakes)? seed,
}) async {
  final b = fakeBackend(syncStatus: sync);
  final f = PreorderFakes(b)..staff.all = staff ?? _roster();
  seed?.call(f);
  await pumpPos(tester, backend: b, fakes: f);
  await openNav(tester, 'Attendance');
  expect(find.widgetWithText(AppBar, 'Attendance'), findsOneWidget);
  return (b, f);
}

Finder chip(String staffId, String which) =>
    find.byKey(Key('att-$staffId-$which'));

bool selected(WidgetTester tester, String staffId, String which) =>
    tester.widget<ChoiceChip>(chip(staffId, which)).selected;

void main() {
  group('the list', () {
    testWidgets('shows active staff only, with three chips each and nothing '
        'chosen', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('staff-baker1')), findsOneWidget);
      expect(find.byKey(const Key('staff-helper1')), findsOneWidget);
      expect(find.byKey(const Key('staff-cashier1')), findsOneWidget);
      expect(find.byKey(const Key('staff-gone1')), findsNothing);
      for (final id in ['baker1', 'helper1', 'cashier1']) {
        expect(
          find.descendant(
            of: find.byKey(Key('staff-$id')),
            matching: find.byType(ChoiceChip),
          ),
          findsNWidgets(3),
        );
        for (final w in ['present', 'half', 'absent']) {
          expect(selected(tester, id, w), isFalse);
        }
      }
      expect(find.text('Present'), findsNWidgets(3));
      expect(find.text('Half-day'), findsNWidgets(3));
      expect(find.text('Absent'), findsNWidgets(3));
      expect(find.text('Baker'), findsOneWidget);
      expect(textOf(tester, 'attendance-summary'), contains('3 not marked'));
      expect(isEnabled(tester, 'save-attendance'), isFalse);
    });

    testWidgets('an empty roster says to ask the Admin', (tester) async {
      await open(tester, staff: const []);
      expect(
        textOf(tester, 'attendance-empty'),
        'No staff yet. Ask the Admin to add staff.',
      );
      expect(isEnabled(tester, 'save-attendance'), isFalse);
      expect(find.byKey(const Key('mark-all-present')), findsNothing);
    });

    testWidgets('a roster that fails to load shows the mapped message', (
      tester,
    ) async {
      final b = fakeBackend();
      await pumpPos(
        tester,
        backend: b,
        fakes: PreorderFakes(b, staffRepository: _FailingStaff()),
      );
      await openNav(tester, 'Attendance');
      expect(
        textOf(tester, 'attendance-error'),
        'This needs an internet connection.',
      );
    });

    testWidgets("is pre-filled from the day's existing marks", (tester) async {
      await open(
        tester,
        seed: (f) => f.attendance
          ..put(_record('baker1', 'Anita', AttendanceStatus.present))
          ..put(
            _record(
              'helper1',
              'Bala',
              AttendanceStatus.halfDay,
              note: 'Left at noon',
            ),
          )
          // Another day's mark must not show today.
          ..put(
            _record(
              'cashier1',
              'Dev',
              AttendanceStatus.absent,
              date: '2026-09-25',
            ),
          ),
      );
      expect(selected(tester, 'baker1', 'present'), isTrue);
      expect(selected(tester, 'helper1', 'half'), isTrue);
      expect(selected(tester, 'cashier1', 'absent'), isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('att-note-helper1')))
            .controller!
            .text,
        'Left at noon',
      );
      expect(textOf(tester, 'attendance-summary'), contains('1 not marked'));
      // Nothing changed yet, so there is nothing to save.
      expect(isEnabled(tester, 'save-attendance'), isFalse);
    });
  });

  group('saving', () {
    testWidgets('sends only the changed rows, in one call', (tester) async {
      final (_, f) = await open(
        tester,
        seed: (f) => f.attendance
          ..put(_record('baker1', 'Anita', AttendanceStatus.present))
          ..put(_record('helper1', 'Bala', AttendanceStatus.present)),
      );
      await tapKey(tester, 'att-helper1-absent');
      await enterKey(tester, 'att-note-helper1', '  Fever  ');
      expect(textOf(tester, 'save-attendance'), contains('Save 1 change'));
      await tapKey(tester, 'save-attendance');

      expect(f.attendance.markCalls, hasLength(1));
      final call = f.attendance.markCalls.single;
      expect(call.date, _today);
      expect(call.marks, hasLength(1));
      expect(call.marks.single.staffId, 'helper1');
      expect(call.marks.single.staffName, 'Bala');
      expect(call.marks.single.status, AttendanceStatus.absent);
      expect(call.marks.single.note, 'Fever');
      expect(
        textOf(tester, 'attendance-saved'),
        startsWith('Saved 1 mark for'),
      );
      // Saved, so nothing is left to save and the marks stay selected.
      expect(isEnabled(tester, 'save-attendance'), isFalse);
      expect(selected(tester, 'helper1', 'absent'), isTrue);
    });

    testWidgets('changing only a note counts as a change', (tester) async {
      final (_, f) = await open(
        tester,
        seed: (f) => f.attendance.put(
          _record('baker1', 'Anita', AttendanceStatus.present),
        ),
      );
      await enterKey(tester, 'att-note-baker1', 'Came late');
      await tapKey(tester, 'save-attendance');
      final m = f.attendance.markCalls.single.marks.single;
      expect(m.status, AttendanceStatus.present);
      expect(m.note, 'Came late');
    });

    testWidgets('Mark all present fills the unmarked ones and keeps marks '
        'already made', (tester) async {
      final (_, f) = await open(
        tester,
        seed: (f) => f.attendance.put(
          _record('helper1', 'Bala', AttendanceStatus.halfDay),
        ),
      );
      await tapKey(tester, 'mark-all-present');
      expect(selected(tester, 'baker1', 'present'), isTrue);
      expect(selected(tester, 'cashier1', 'present'), isTrue);
      expect(selected(tester, 'helper1', 'half'), isTrue);
      expect(isEnabled(tester, 'mark-all-present'), isFalse);
      await tapKey(tester, 'att-cashier1-absent');
      await tapKey(tester, 'save-attendance');

      final marks = f.attendance.markCalls.single.marks;
      expect(
        {for (final m in marks) m.staffId: m.status},
        {
          'baker1': AttendanceStatus.present,
          'cashier1': AttendanceStatus.absent,
        },
      );
      expect(
        f.attendance.records.where((r) => r.businessDate == _today),
        hasLength(3),
      );
    });

    testWidgets('a note is capped at the limit and needs a mark first', (
      tester,
    ) async {
      await open(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('att-note-baker1')))
            .enabled,
        isFalse,
      );
      await tapKey(tester, 'att-baker1-present');
      await enterKey(tester, 'att-note-baker1', 'x' * 150);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('att-note-baker1')))
            .controller!
            .text,
        hasLength(Limits.attendanceNoteMax),
      );
    });

    testWidgets('a double tap sends one call', (tester) async {
      final (_, f) = await open(tester);
      f.attendance.gate = Completer<void>();
      await tapKey(tester, 'mark-all-present');
      final save = find.byKey(const Key('save-attendance'));
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      expect(f.attendance.markCalls, hasLength(1));
      expect(isEnabled(tester, 'save-attendance'), isFalse);
      f.attendance.gate!.complete();
      await tester.pumpAndSettle();
      expect(f.attendance.markCalls, hasLength(1));
      expect(find.byKey(const Key('attendance-saved')), findsOneWidget);
    });

    testWidgets('marking again overwrites: one record per person per day', (
      tester,
    ) async {
      final (_, f) = await open(tester);
      await tapKey(tester, 'att-baker1-present');
      await tapKey(tester, 'save-attendance');
      await tapKey(tester, 'att-baker1-absent');
      await tapKey(tester, 'save-attendance');
      expect(f.attendance.markCalls, hasLength(2));
      final mine = f.attendance.records.where((r) => r.staffId == 'baker1');
      expect(mine, hasLength(1));
      expect(mine.single.status, AttendanceStatus.absent);
    });

    testWidgets('a failure shows the mapped message, keeps the choices and '
        'can be retried', (tester) async {
      final (_, f) = await open(tester);
      f.attendance.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'att-baker1-half');
      await tapKey(tester, 'save-attendance');
      expect(
        textOf(tester, 'attendance-save-error'),
        "You don't have permission to do this.",
      );
      expect(find.byKey(const Key('attendance-saved')), findsNothing);
      expect(selected(tester, 'baker1', 'half'), isTrue);
      expect(isEnabled(tester, 'save-attendance'), isTrue);
      await tapKey(tester, 'save-attendance');
      expect(find.byKey(const Key('attendance-save-error')), findsNothing);
      expect(textOf(tester, 'attendance-saved'), startsWith('Saved 1 mark'));
      expect(f.attendance.markCalls, hasLength(2));
    });

    testWidgets('an unexpected error shows the generic message', (
      tester,
    ) async {
      final (_, f) = await open(tester);
      f.attendance.failNext = Exception('boom');
      await tapKey(tester, 'att-baker1-present');
      await tapKey(tester, 'save-attendance');
      expect(
        textOf(tester, 'attendance-save-error'),
        'Something went wrong. Please try again.',
      );
    });

    testWidgets('works offline: it saves and says it will sync later', (
      tester,
    ) async {
      final (_, f) = await open(
        tester,
        sync: Offline(DateTime.utc(2026, 9, 26, 4)),
      );
      await tapKey(tester, 'mark-all-present');
      await tapKey(tester, 'save-attendance');
      expect(f.attendance.markCalls.single.marks, hasLength(3));
      expect(
        textOf(tester, 'attendance-saved'),
        contains('Kept on this phone'),
      );
      expect(find.byKey(const Key('attendance-save-error')), findsNothing);
    });
  });

  group('the date', () {
    testWidgets('starts today, never goes into the future, and stops '
        '${Limits.attendanceBackDays} days back', (tester) async {
      await open(tester);
      expect(textOf(tester, 'date-label'), contains('Today'));
      expect(isEnabled(tester, 'date-next'), isFalse);
      for (var i = 0; i < Limits.attendanceBackDays; i++) {
        expect(isEnabled(tester, 'date-prev'), isTrue, reason: 'day $i');
        await tapKey(tester, 'date-prev');
      }
      expect(textOf(tester, 'date-label'), contains('19 Sep 2026'));
      expect(isEnabled(tester, 'date-prev'), isFalse);
      expect(isEnabled(tester, 'date-next'), isTrue);
      await tapKey(tester, 'date-next');
      expect(textOf(tester, 'date-label'), contains('20 Sep 2026'));
    });

    testWidgets('the date picker is limited to the same window', (
      tester,
    ) async {
      await open(tester);
      await tapKey(tester, 'date-pick');
      final cal = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(cal.lastDate, DateTime(2026, 9, 26));
      expect(cal.firstDate, DateTime(2026, 9, 19));
    });

    testWidgets("an earlier day shows that day's marks and saves to it", (
      tester,
    ) async {
      final (_, f) = await open(
        tester,
        seed: (f) => f.attendance.put(
          _record(
            'baker1',
            'Anita',
            AttendanceStatus.absent,
            date: '2026-09-24',
          ),
        ),
      );
      expect(selected(tester, 'baker1', 'absent'), isFalse);
      await tapKey(tester, 'date-prev');
      await tapKey(tester, 'date-prev');
      expect(selected(tester, 'baker1', 'absent'), isTrue);
      await tapKey(tester, 'att-baker1-present');
      await tapKey(tester, 'save-attendance');
      expect(f.attendance.markCalls.single.date, '2026-09-24');
      expect(f.attendance.markCalls.single.marks.single.staffId, 'baker1');
    });

    testWidgets('unsaved choices wait on their own day', (tester) async {
      final (_, f) = await open(tester);
      await tapKey(tester, 'att-baker1-present');
      await tapKey(tester, 'date-prev');
      expect(selected(tester, 'baker1', 'present'), isFalse);
      expect(isEnabled(tester, 'save-attendance'), isFalse);
      await tapKey(tester, 'date-next');
      expect(selected(tester, 'baker1', 'present'), isTrue);
      expect(f.attendance.markCalls, isEmpty);
    });

    testWidgets('follows the business date at the day boundary', (
      tester,
    ) async {
      // 00:05 IST on the 27th is still the 26th in UTC.
      final clock = TestClock(DateTime.utc(2026, 9, 26, 18, 35));
      final b = fakeBackend(clock: clock);
      final f = PreorderFakes(b, now: clock.call)..staff.all = _roster();
      await pumpPos(tester, backend: b, fakes: f);
      await openNav(tester, 'Attendance');
      expect(textOf(tester, 'date-label'), contains('27 Sep 2026'));
      await tapKey(tester, 'mark-all-present');
      await tapKey(tester, 'save-attendance');
      expect(f.attendance.markCalls.single.date, '2026-09-27');
    });
  });

  group('permission', () {
    testWidgets('the entry is hidden without attendance.mark', (tester) async {
      final b = fakeBackend(
        session: sessionWith([Permission.billCreate, Permission.reportOwn]),
      );
      await pumpPos(tester, backend: b);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-Attendance')), findsNothing);
    });

    test('the route needs attendance.mark', () {
      final withIt = AsyncData<SessionContext?>(
        sessionWith([Permission.billCreate, Permission.attendanceMark]),
      );
      final without = AsyncData<SessionContext?>(
        sessionWith([Permission.billCreate]),
      );
      expect(Routes.redirect(withIt, '/attendance'), isNull);
      expect(Routes.redirect(without, '/attendance'), '/');
    });
  });
}

final class _FailingStaff implements StaffRepository {
  @override
  Stream<List<StaffMember>> watchActive(String locationId) =>
      Stream.error(const DataFailure(FailureReason.offline));

  @override
  Stream<List<StaffMember>> watchAll(String locationId) =>
      Stream.error(const DataFailure(FailureReason.offline));
}
