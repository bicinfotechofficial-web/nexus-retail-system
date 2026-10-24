import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_attendance.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_staff.dart';
import 'package:nexus_admin/fakes/overrides.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

const _p = AttendanceStatus.present;
const _h = AttendanceStatus.halfDay;
const _a = AttendanceStatus.absent;

StaffMember _member(String id, String name, {bool active = true}) =>
    StaffMember(id: id, name: name, active: active);

/// PTB has three people, MNJ has two; nobody works at KTL (closed).
FakeStaffStore _roster() => FakeStaffStore({
  'PTB': [
    _member('a', 'Staff A'),
    _member('b', 'Staff B'),
    _member('c', 'Staff C'),
  ],
  'MNJ': [_member('d', 'Staff D'), _member('e', 'Staff E')],
});

Future<void> _open(
  WidgetTester tester, {
  required FakeStaffStore staff,
  required FakeAttendanceRepository attendance,
  Size size = const Size(1400, 1400),
}) async {
  await pumpAdmin(
    tester,
    FakeBackend.seeded(today: testToday),
    size: size,
    overrides: newInterfaceOverrides(staff: staff, attendance: attendance),
  );
  await signIn(tester);
  await goTo(tester, '/attendance');
}

Future<void> _monthly(WidgetTester tester) async {
  await tester.tap(find.text('Monthly'));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('daily', () {
    testWidgets('lists who is present, half-day and absent, with notes', (
      tester,
    ) async {
      final attendance = FakeAttendanceRepository([
        mark('PTB', testToday, 'a', 'Staff A', _p),
        mark('PTB', testToday, 'b', 'Staff B', _h, note: 'Left at noon'),
        mark('PTB', testToday, 'c', 'Staff C', _a, note: 'Unwell'),
      ]);
      await _open(tester, staff: _roster(), attendance: attendance);

      expect(find.text('Today, 26 Sep 2026'), findsOneWidget);
      expect(attendance.allLocationReads, [testToday]);
      expect(find.text('Present (1)'), findsOneWidget);
      expect(find.text('Half-day (1)'), findsOneWidget);
      expect(find.text('Absent (1)'), findsOneWidget);
      expect(_text(tester, 'att-person-PTB-a'), 'Staff A');
      expect(_text(tester, 'att-person-PTB-b'), 'Staff B — Left at noon');
      expect(_text(tester, 'att-person-PTB-c'), 'Staff C — Unwell');
      expect(_text(tester, 'att-count-PTB'), '3 of 3 marked');
      expect(find.byKey(const Key('att-notmarked-PTB')), findsNothing);
      // MNJ has staff and no marks, so the page flags it at the top too.
      expect(
        _text(tester, 'att-summary'),
        '1 store has not marked today: MNJ.',
      );
    });

    testWidgets('flags a store that has not marked today', (tester) async {
      final attendance = FakeAttendanceRepository([
        mark('PTB', testToday, 'a', 'Staff A', _p),
      ]);
      await _open(tester, staff: _roster(), attendance: attendance);

      // PTB marked one of three; MNJ marked nobody.
      expect(_text(tester, 'att-count-PTB'), '1 of 3 marked');
      expect(find.byKey(const Key('att-notmarked-PTB')), findsNothing);
      expect(find.byKey(const Key('att-notmarked-MNJ')), findsOneWidget);
      expect(find.text('Not marked yet'), findsOneWidget);
      expect(
        _text(tester, 'att-summary'),
        '1 store has not marked today: MNJ.',
      );
      expect(_text(tester, 'att-count-MNJ'), '0 of 2 marked');
      expect(find.byKey(const Key('att-all-marked')), findsNothing);
      // A closed store with no marks is left out.
      expect(find.byKey(const Key('att-store-KTL')), findsNothing);
    });

    testWidgets('a store with no staff is not flagged', (tester) async {
      final staff = FakeStaffStore({
        'PTB': [_member('a', 'Staff A')],
      });
      final attendance = FakeAttendanceRepository([
        mark('PTB', testToday, 'a', 'Staff A', _p),
      ]);
      await _open(tester, staff: staff, attendance: attendance);

      expect(find.byKey(const Key('att-nostaff-MNJ')), findsOneWidget);
      expect(find.byKey(const Key('att-notmarked-MNJ')), findsNothing);
      expect(find.byKey(const Key('att-count-MNJ')), findsNothing);
      // Nothing is missing, so the page says every store has marked.
      expect(find.byKey(const Key('att-all-marked')), findsOneWidget);
    });

    testWidgets('the day can be changed, and not past today', (tester) async {
      final attendance = FakeAttendanceRepository([
        mark('MNJ', '2026-09-25', 'd', 'Staff D', _a, note: 'On leave'),
      ]);
      await _open(tester, staff: _roster(), attendance: attendance);
      expect(find.byKey(const Key('att-notmarked-MNJ')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_right),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('25 Sep 2026'), findsOneWidget);
      expect(attendance.allLocationReads.last, '2026-09-25');
      expect(_text(tester, 'att-person-MNJ-d'), 'Staff D — On leave');
      expect(_text(tester, 'att-count-MNJ'), '1 of 2 marked');
      // PTB has no marks on the 25th.
      expect(find.byKey(const Key('att-notmarked-PTB')), findsOneWidget);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Today, 26 Sep 2026'), findsOneWidget);
    });

    testWidgets('the date picker jumps to a chosen day', (tester) async {
      final attendance = FakeAttendanceRepository([
        mark('PTB', '2026-09-24', 'a', 'Staff A', _p),
      ]);
      await _open(tester, staff: _roster(), attendance: attendance);

      await tester.tap(find.byKey(const Key('att-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('24 Sep 2026'), findsOneWidget);
      expect(_text(tester, 'att-person-PTB-a'), 'Staff A');
    });

    testWidgets('a closed store with marks that day is shown', (tester) async {
      final attendance = FakeAttendanceRepository([
        mark('KTL', testToday, 'k', 'Staff K', _p),
      ]);
      final staff = FakeStaffStore({
        'KTL': [_member('k', 'Staff K')],
      });
      await _open(tester, staff: staff, attendance: attendance);
      expect(find.byKey(const Key('att-store-KTL')), findsOneWidget);
      expect(find.text('Kottakkal (KTL) (inactive)'), findsOneWidget);
    });
  });

  group('monthly', () {
    FakeAttendanceRepository september() => FakeAttendanceRepository([
      // Staff A: 3 present and a half-day.
      mark('PTB', '2026-09-01', 'a', 'Staff A', _p),
      mark('PTB', '2026-09-02', 'a', 'Staff A', _p),
      mark('PTB', '2026-09-03', 'a', 'Staff A', _p),
      mark('PTB', '2026-09-04', 'a', 'Staff A', _h),
      // Staff B: 1 present, 2 half-days, 1 absent.
      mark('PTB', '2026-09-01', 'b', 'Staff B', _h, note: 'Dentist'),
      mark('PTB', '2026-09-02', 'b', 'Staff B', _h),
      mark('PTB', '2026-09-03', 'b', 'Staff B', _a),
      mark('PTB', '2026-09-05', 'b', 'Staff B', _p),
      // Someone no longer on the active roster, marked earlier in the month.
      mark('PTB', '2026-09-02', 'z', 'Staff Z', _p),
      // Another store, another month: must not leak in.
      mark('MNJ', '2026-09-01', 'd', 'Staff D', _p),
      mark('PTB', '2026-08-31', 'a', 'Staff A', _p),
    ]);

    testWidgets('shows a grid of marks and totals with half-days as 0.5', (
      tester,
    ) async {
      final attendance = september();
      await _open(tester, staff: _roster(), attendance: attendance);
      await _monthly(tester);

      // The default store is the first open one, MNJ; pick PTB.
      await tester.tap(find.byKey(const Key('att-month-store')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pattambi (PTB)').last);
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      // Marks, and blank where nothing was marked.
      Finder mark0(String id, int day) => find.descendant(
        of: find.byKey(Key('att-cell-$id-$day')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(mark0('a', 1)).data, 'P');
      expect(tester.widget<Text>(mark0('a', 4)).data, 'H');
      expect(tester.widget<Text>(mark0('b', 3)).data, 'A');
      expect(mark0('a', 5), findsNothing);
      expect(mark0('c', 1), findsNothing);
      expect(mark0('a', 30), findsNothing);

      // Totals: A is 3 + 0.5, B is 1 + 2 x 0.5.
      expect(_text(tester, 'att-total-a-present'), '3');
      expect(_text(tester, 'att-total-a-half'), '1');
      expect(_text(tester, 'att-total-a-absent'), '0');
      expect(_text(tester, 'att-total-a-worked'), '3.5');
      expect(_text(tester, 'att-total-b-present'), '1');
      expect(_text(tester, 'att-total-b-half'), '2');
      expect(_text(tester, 'att-total-b-absent'), '1');
      expect(_text(tester, 'att-total-b-worked'), '2');
      // A person with no marks still has a row of zeros.
      expect(_text(tester, 'att-total-c-present'), '0');
      expect(_text(tester, 'att-total-c-worked'), '0');
      // A mark for someone off the active roster still counts, by the name
      // stored with it.
      expect(find.text('Staff Z'), findsOneWidget);
      expect(_text(tester, 'att-total-z-worked'), '1');
      // All staff: present 3+1+0+1, half 1+2, absent 1, days 3.5+2+0+1.
      expect(_text(tester, 'att-total-all-present'), '5');
      expect(_text(tester, 'att-total-all-half'), '3');
      expect(_text(tester, 'att-total-all-absent'), '1');
      expect(_text(tester, 'att-total-all-worked'), '6.5');
      // Column group labels carry no role or personal names.
      for (final label in ['Present', 'Half-days', 'Absent', 'Days worked']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('loads one store and one month at a time', (tester) async {
      final attendance = september();
      await _open(tester, staff: _roster(), attendance: attendance);
      await _monthly(tester);
      // Opening the tab reads the default store's current month only.
      expect(attendance.monthReads, ['MNJ 2026-09']);
      expect(_text(tester, 'att-total-d-present'), '1');
      expect(find.text('Staff A'), findsNothing);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      expect(attendance.monthReads.last, 'MNJ 2026-08');
      expect(_text(tester, 'att-total-d-present'), '0');
      // Every read named exactly one store, never all of them.
      expect(attendance.monthReads.every((r) => r.startsWith('MNJ ')), isTrue);

      // Next month is the latest allowed.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_right),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a store with no staff shows a short message', (tester) async {
      final staff = FakeStaffStore({
        'PTB': [_member('a', 'Staff A')],
      });
      await _open(tester, staff: staff, attendance: FakeAttendanceRepository());
      await _monthly(tester);

      expect(find.byKey(const Key('att-month-empty')), findsOneWidget);
      expect(find.byKey(const Key('att-grid')), findsNothing);
    });

    testWidgets('the grid scrolls sideways on a phone', (tester) async {
      await _open(
        tester,
        staff: _roster(),
        attendance: september(),
        size: const Size(390, 800),
      );
      await _monthly(tester);
      expect(tester.takeException(), isNull);

      final grid = find.byKey(const Key('att-grid'));
      expect(grid, findsOneWidget);
      // Wider than the screen, inside a horizontal scroller.
      expect(tester.getSize(grid).width, greaterThan(390));
      expect(
        find.ancestor(
          of: grid,
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a Store Manager has no Attendance entry and is refused', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      overrides: newInterfaceOverrides(
        staff: _roster(),
        attendance: FakeAttendanceRepository(),
      ),
    );
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Attendance'),
      ),
      findsNothing,
    );
    await goTo(tester, '/attendance');
    expect(
      find.text('You do not have permission to view this page.'),
      findsOneWidget,
    );
  });
}
