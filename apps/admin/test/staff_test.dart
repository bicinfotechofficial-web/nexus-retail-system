import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_staff.dart';
import 'package:nexus_admin/fakes/overrides.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

StaffMember _member(
  String id,
  String name, {
  String role = '',
  bool active = true,
}) => StaffMember(id: id, name: name, role: role, active: active);

FakeStaffStore _store() => FakeStaffStore({
  'MNJ': [
    _member('a', 'Staff A', role: 'Baker'),
    _member('b', 'Staff B', role: 'Helper'),
    _member('c', 'Staff C', active: false),
  ],
});

Future<void> _openStaff(
  WidgetTester tester,
  FakeStaffStore store, {
  Size size = const Size(1400, 1000),
}) async {
  await pumpAdmin(
    tester,
    FakeBackend.seeded(today: testToday),
    size: size,
    overrides: newInterfaceOverrides(staff: store),
  );
  await signIn(tester);
  await goTo(tester, '/staff');
}

Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('staff-add')));
  await tester.pumpAndSettle();
}

List<String> _names(WidgetTester tester) => [
  for (final r
      in tester.widget<DataTable>(find.byKey(const Key('staff-table'))).rows)
    ((r.cells.first.child as Text).data!),
];

void main() {
  testWidgets('lists the store roster with role and status', (tester) async {
    await _openStaff(tester, _store());

    expect(_names(tester), ['Staff A', 'Staff B', 'Staff C']);
    expect(find.text('Baker'), findsOneWidget);
    expect(find.text('Helper'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('2 active of 3'), findsOneWidget);
    // Inactive people can be brought back, active ones deactivated.
    expect(find.byKey(const Key('staff-toggle-c')), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('staff-toggle-c'))).child,
      isA<Text>().having((t) => t.data, 'label', 'Reactivate'),
    );
  });

  testWidgets('a store with no staff shows an empty roster and can add', (
    tester,
  ) async {
    final store = _store();
    await _openStaff(tester, store);

    await tester.tap(find.byKey(const Key('staff-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pattambi (PTB)').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staff-empty')), findsOneWidget);
    expect(find.byKey(const Key('staff-table')), findsNothing);

    await _openAddDialog(tester);
    await tester.enterText(find.byKey(const Key('staff-name')), 'Staff D');
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staff-empty')), findsNothing);
    expect(_names(tester), ['Staff D']);
    // It went to PTB, not MNJ.
    expect(store.of('PTB').single.name, 'Staff D');
    expect(store.of('MNJ'), hasLength(3));
  });

  testWidgets(
    'add validates the name and the role before calling the service',
    (tester) async {
      final store = _store();
      await _openStaff(tester, store);
      await _openAddDialog(tester);

      // An empty name.
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the name.'), findsOneWidget);

      // A name over the limit, and a role over its limit.
      await tester.enterText(
        find.byKey(const Key('staff-name')),
        'x' * (Limits.staffNameMax + 1),
      );
      await tester.enterText(
        find.byKey(const Key('staff-role')),
        'y' * (Limits.staffRoleMax + 1),
      );
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('At most ${Limits.staffNameMax} characters.'),
        findsOneWidget,
      );
      expect(
        find.text('At most ${Limits.staffRoleMax} characters.'),
        findsOneWidget,
      );
      expect(store.calls, isEmpty);

      // Blanks around and inside the name are cleaned.
      await tester.enterText(
        find.byKey(const Key('staff-name')),
        '  Staff   D ',
      );
      await tester.enterText(find.byKey(const Key('staff-role')), ' Cashier ');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();

      expect(store.calls, ['create MNJ Staff D']);
      final added = store.of('MNJ').last;
      expect(added.name, 'Staff D');
      expect(added.role, 'Cashier');
      expect(added.active, isTrue);
      expect(_names(tester), contains('Staff D'));
      expect(find.text('Staff member added.'), findsOneWidget);
    },
  );

  testWidgets('adding while offline shows the failure and keeps the dialog', (
    tester,
  ) async {
    final store = _store()..offline = true;
    await _openStaff(tester, store);
    await _openAddDialog(tester);

    await tester.enterText(find.byKey(const Key('staff-name')), 'Staff D');
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('You are offline. The console needs a connection for this.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('staff-form-error')), findsOneWidget);
    // The dialog stays open with what was typed, and nothing was added.
    expect(find.byKey(const Key('staff-save')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('staff-name')))
          .controller!
          .text,
      'Staff D',
    );
    expect(store.of('MNJ'), hasLength(3));

    // Back online, the same dialog saves.
    store.offline = false;
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();
    expect(store.of('MNJ'), hasLength(4));
    expect(find.byKey(const Key('staff-save')), findsNothing);
  });

  testWidgets('edit changes the name and role', (tester) async {
    final store = _store();
    await _openStaff(tester, store);

    await tester.tap(find.byKey(const Key('staff-edit-b')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('staff-name')))
          .controller!
          .text,
      'Staff B',
    );
    await tester.enterText(find.byKey(const Key('staff-name')), 'Staff B2');
    await tester.enterText(find.byKey(const Key('staff-role')), 'Decorator');
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();

    final b = store.of('MNJ').firstWhere((s) => s.id == 'b');
    expect(b.name, 'Staff B2');
    expect(b.role, 'Decorator');
    expect(b.active, isTrue);
    expect(find.text('Staff B2'), findsOneWidget);
    expect(find.text('Decorator'), findsOneWidget);
  });

  testWidgets('edit validates, and an offline edit changes nothing', (
    tester,
  ) async {
    final store = _store();
    await _openStaff(tester, store);

    await tester.tap(find.byKey(const Key('staff-edit-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('staff-name')), '   ');
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the name.'), findsOneWidget);
    expect(store.calls, isEmpty);

    store.offline = true;
    await tester.enterText(find.byKey(const Key('staff-name')), 'Staff A2');
    await tester.tap(find.byKey(const Key('staff-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-form-error')), findsOneWidget);
    expect(store.of('MNJ').first.name, 'Staff A');
  });

  testWidgets('deactivate asks first, and reactivate brings a person back', (
    tester,
  ) async {
    final store = _store();
    await _openStaff(tester, store);

    // Cancelling the confirmation changes nothing.
    await tester.tap(find.byKey(const Key('staff-toggle-a')));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate Staff A?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(store.of('MNJ').first.active, isTrue);

    await tester.tap(find.byKey(const Key('staff-toggle-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(store.of('MNJ').first.active, isFalse);
    // Never deleted: the row stays, marked inactive.
    expect(_names(tester), ['Staff A', 'Staff B', 'Staff C']);
    expect(find.text('1 active of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('staff-toggle-c')));
    await tester.pumpAndSettle();
    expect(store.of('MNJ').last.active, isTrue);
    expect(find.text('2 active of 3'), findsOneWidget);
  });

  testWidgets('deactivating while offline shows the failure', (tester) async {
    final store = _store()..offline = true;
    await _openStaff(tester, store);

    await tester.tap(find.byKey(const Key('staff-toggle-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();

    expect(
      find.text('You are offline. The console needs a connection for this.'),
      findsOneWidget,
    );
    expect(store.of('MNJ').first.active, isTrue);
  });

  testWidgets('the Admin reaches Staff from the side nav', (tester) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      overrides: newInterfaceOverrides(staff: _store()),
    );
    await signIn(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Staff'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-table')), findsOneWidget);
  });

  testWidgets('a Store Manager has no Staff entry and is refused there', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      FakeBackend.seeded(today: testToday),
      overrides: newInterfaceOverrides(staff: _store()),
    );
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Staff'),
      ),
      findsNothing,
    );

    await goTo(tester, '/staff');
    expect(
      find.text('You do not have permission to view this page.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('staff-table')), findsNothing);
  });

  testWidgets('the roster page works at phone width', (tester) async {
    await _openStaff(tester, _store(), size: const Size(390, 800));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('staff-table')), findsOneWidget);
    await _openAddDialog(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('staff-name')), findsOneWidget);
  });
}
