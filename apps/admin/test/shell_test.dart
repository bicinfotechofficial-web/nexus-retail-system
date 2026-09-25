import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/shell/admin_shell.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'helpers.dart';

Finder inSwitcher(String text) => find.descendant(
  of: find.byKey(const Key('location-switcher')),
  matching: find.text(text),
);

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('signed out, the console shows the login screen', (tester) async {
    await pumpAdmin(tester, backend);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byType(AdminShell), findsNothing);
  });

  testWidgets('a wrong password shows an error and stays on login', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, password: 'wrong');
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.byType(AdminShell), findsNothing);
  });

  testWidgets('the Admin signs in to the side nav and can sign out', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester);

    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text(LocationSwitcher.allLabel), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('the Admin can switch between All and a single location', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester);

    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('Pattambi (PTB)'), findsWidgets);
    expect(find.text('Manjeri (MNJ)'), findsWidgets);
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();
    expect(find.text(LocationSwitcher.allLabel), findsNothing);
    expect(inSwitcher('Manjeri (MNJ)'), findsOneWidget);
  });

  testWidgets('a Store Manager sees only their location, without "All"', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);

    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.text(LocationSwitcher.allLabel), findsNothing);
    expect(inSwitcher('Pattambi (PTB)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('Manjeri (MNJ)'), findsNothing);
  });

  testWidgets('pages are guarded by permission, not role name', (tester) async {
    // A role called "Admin" but without any report permission.
    const noReports = SessionContext(
      user: AppUser(
        uid: 'u1',
        name: 'Admin',
        email: 'viewer@caramelcottage.in',
        roleId: 'ADMIN',
        locationId: null,
        active: true,
        createdBy: 'seed',
      ),
      role: Role(
        id: 'ADMIN',
        name: 'Admin',
        permissions: [Permission.catalogView],
        allLocations: true,
      ),
      location: null,
    );
    final guarded = FakeBackend(
      auth: FakeAuthService({
        'viewer@caramelcottage.in': (password: 'pw', session: noReports),
      }),
      locations: backend.locations,
      summaries: backend.summaries,
      stock: backend.stock,
      catalog: backend.catalog,
    );
    await pumpAdmin(tester, guarded);
    await signIn(tester, email: 'viewer@caramelcottage.in', password: 'pw');

    expect(find.byType(NotPermitted), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
  });

  testWidgets('a narrow window uses a drawer instead of the side nav', (
    tester,
  ) async {
    await pumpAdmin(tester, backend, size: const Size(700, 900));
    await signIn(tester);

    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsNothing);
  });
}
