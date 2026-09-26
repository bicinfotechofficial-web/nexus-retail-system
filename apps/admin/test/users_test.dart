import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_admin/data/providers.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_admin/users/users_screen.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'helpers.dart';

class _OfflineUsers extends Mock implements UserService {}

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  await tester.tap(find.text('Users'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _fill(WidgetTester tester, {String email = 'new.ktm@x.in'}) async {
  await tester.enterText(find.byKey(const Key('user-name')), 'Store Manager 2');
  await tester.enterText(find.byKey(const Key('user-email')), email);
  await tester.enterText(find.byKey(const Key('user-password')), 'secret99');
  await tester.tap(find.byKey(const Key('user-location')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Manjeri (MNJ)').last);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('lists users and filters them by location', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester);
    await _open(tester, backend);

    expect(find.byKey(const Key('user-admin-0001')), findsOneWidget);
    expect(find.byKey(const Key('user-sm-PTB')), findsOneWidget);
    expect(find.byKey(const Key('user-sm-MNJ')), findsOneWidget);
    expect(_text(tester, 'user-status-sm-PTB-relief'), 'Disabled');
    // The Admin can't disable their own account here.
    expect(find.byKey(const Key('toggle-admin-0001')), findsNothing);

    await tester.tap(find.byKey(const Key('users-location-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pattambi (PTB)').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-sm-PTB')), findsOneWidget);
    expect(find.byKey(const Key('user-sm-PTB-relief')), findsOneWidget);
    expect(find.byKey(const Key('user-sm-MNJ')), findsNothing);
    expect(find.byKey(const Key('user-admin-0001')), findsNothing);
  });

  testWidgets('creates a Store Manager and the Admin stays signed in', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester);
    await _open(tester, backend);

    await tester.tap(find.byKey(const Key('user-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('user-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    expect(find.text('Choose a location'), findsOneWidget);

    await _fill(tester, email: 'Manager.MNJ@caramelcottage.in');
    await tester.tap(find.byKey(const Key('user-save')));
    await tester.pumpAndSettle();
    expect(find.text('A user with this email already exists'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('user-email')),
      'Relief.MNJ@caramelcottage.in',
    );
    await tester.tap(find.byKey(const Key('user-save')));
    await tester.pumpAndSettle();

    final created = backend.users.users.singleWhere(
      (u) => u.email == 'relief.mnj@caramelcottage.in',
    );
    expect(created.roleId, SeedRoles.storeManagerId);
    expect(created.locationId, 'MNJ');
    expect(created.active, isTrue);
    expect(backend.audit.actions, [AuditAction.userCreate]);
    expect(find.byKey(Key('user-${created.uid}')), findsOneWidget);
    expect(
      find.text(
        'Store Manager 2 can now sign in to the POS with '
        'relief.mnj@caramelcottage.in.',
      ),
      findsOneWidget,
    );

    // D-018: creating the account does not replace the Admin's session.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UsersScreen)),
    );
    expect(container.read(sessionProvider)!.user.email, FakeBackend.adminEmail);
  });

  testWidgets('disabling and enabling ask for confirmation', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester);
    await _open(tester, backend);

    await _tapVisible(tester, 'toggle-sm-MNJ');
    expect(find.text('Disable Store Manager MNJ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'user-status-sm-MNJ'), 'Active');
    expect(backend.audit.actions, isEmpty);

    await _tapVisible(tester, 'toggle-sm-MNJ');
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'user-status-sm-MNJ'), 'Disabled');
    expect(
      backend.users.users.singleWhere((u) => u.uid == 'sm-MNJ').active,
      isFalse,
    );
    expect(backend.audit.actions, [AuditAction.userDisable]);

    await _tapVisible(tester, 'toggle-sm-PTB-relief');
    expect(find.text('Enable Relief Store Manager PTB?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'user-status-sm-PTB-relief'), 'Active');
  });

  testWidgets('a disabled Store Manager can no longer sign in', (tester) async {
    await backend.userService.setActive('sm-PTB', active: false);
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.byType(UsersScreen), findsNothing);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('an offline create shows why and keeps the dialog open', (
    tester,
  ) async {
    final offline = _OfflineUsers();
    when(
      () => offline.createStoreManager(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        locationId: any(named: 'locationId'),
      ),
    ).thenThrow(const DataFailure(FailureReason.offline));
    backend.userService = offline;
    await pumpAdmin(tester, backend);
    await signIn(tester);
    await _open(tester, backend);

    await tester.tap(find.byKey(const Key('user-add')));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.byKey(const Key('user-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('You are offline. The console needs a connection for this.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('user-save')), findsOneWidget);
  });

  testWidgets('a Store Manager cannot open users', (tester) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Users'), findsNothing);
    await goTo(tester, '/users');
    expect(find.byType(NotPermitted), findsOneWidget);
  });

  test('UserRules', () {
    expect(UserRules.email('a@b.in', []), isNull);
    expect(UserRules.email('a@b', []), 'Enter a valid email address');
    expect(
      UserRules.email('A@B.in', ['a@b.in']),
      'A user with this email already exists',
    );
    expect(UserRules.password('12345'), 'Use at least 6 characters');
    expect(UserRules.password('123456'), isNull);
  });
}
