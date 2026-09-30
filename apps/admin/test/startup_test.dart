// Startup on the real wiring: the console is pumped with
// `AdminServices.overrides` (the list main.dart installs for the Firestore
// backend), filled with the fakes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/app.dart';
import 'package:nexus_admin/data/emulator_switch.dart';
import 'package:nexus_admin/data/firebase_start.dart';
import 'package:nexus_admin/data/providers.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/login/login_screen.dart';
import 'package:nexus_admin/shell/admin_shell.dart';
import 'package:nexus_data/nexus_data.dart';

import 'helpers.dart';

/// Firebase Auth restoring a saved session: [session] emits nothing until
/// [restore], and then the session, as `FirebaseAuthService` does.
final class RestoringAuth implements AuthService {
  RestoringAuth(this.restored);

  final SessionContext? restored;
  final _first = Completer<void>();
  SessionContext? _current;

  void restore() {
    _current = restored;
    _first.complete();
  }

  @override
  Stream<SessionContext?> get session async* {
    await _first.future;
    yield _current;
  }

  @override
  SessionContext? get current => _current;

  @override
  Future<SessionContext> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

Future<void> pumpServices(WidgetTester tester, FakeBackend b) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...b.services.overrides,
        clockProvider.overrideWithValue(() => testNow),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('startup routing', () {
    testWidgets('a restored Admin session opens the dashboard', (tester) async {
      final b = FakeBackend.seeded(today: testToday);
      // Restored before the console is shown, as startConsole waits for it.
      await b.auth.signIn(
        email: FakeBackend.adminEmail,
        password: FakeBackend.demoPassword,
      );
      await pumpServices(tester, b);
      expect(find.byType(AdminShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('no saved session opens the login page, then the console', (
      tester,
    ) async {
      final b = FakeBackend.seeded(today: testToday);
      await pumpServices(tester, b);
      expect(find.byType(LoginScreen), findsOneWidget);
      await signIn(tester);
      expect(find.byType(AdminShell), findsOneWidget);
    });
  });

  group('restoredSession', () {
    test('waits for the first session event', () async {
      final auth = RestoringAuth(FakeBackend.adminSession());
      var done = false;
      final f = restoredSession(auth).then((s) {
        done = true;
        return s;
      });
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      auth.restore();
      expect((await f)?.user.email, FakeBackend.adminEmail);
    });

    test('gives up after the timeout and starts signed out', () async {
      final auth = RestoringAuth(null);
      final s = await restoredSession(
        auth,
        timeout: const Duration(milliseconds: 10),
      );
      expect(s, isNull);
    });
  });

  test('AdminServices overrides every provider without an implementation', () {
    final b = FakeBackend.seeded(today: testToday);
    final c = ProviderContainer(overrides: b.services.overrides);
    addTearDown(c.dispose);
    final reads = <String, Object Function()>{
      'authServiceProvider': () => c.read(authServiceProvider),
      'locationRepositoryProvider': () => c.read(locationRepositoryProvider),
      'locationServiceProvider': () => c.read(locationServiceProvider),
      'summaryRepositoryProvider': () => c.read(summaryRepositoryProvider),
      'stockRepositoryProvider': () => c.read(stockRepositoryProvider),
      'catalogRepositoryProvider': () => c.read(catalogRepositoryProvider),
      'catalogServiceProvider': () => c.read(catalogServiceProvider),
      'userRepositoryProvider': () => c.read(userRepositoryProvider),
      'userServiceProvider': () => c.read(userServiceProvider),
      'deviceServiceProvider': () => c.read(deviceServiceProvider),
      'expenseRepositoryProvider': () => c.read(expenseRepositoryProvider),
      'expenseServiceProvider': () => c.read(expenseServiceProvider),
      'auditRepositoryProvider': () => c.read(auditRepositoryProvider),
    };
    for (final e in reads.entries) {
      expect(e.value, returnsNormally, reason: e.key);
    }
    expect(b.services.overrides, hasLength(reads.length));
  });

  group('startup error screen', () {
    testWidgets('says what to do and retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupErrorApp(
          error: Exception('firebase down'),
          onRetry: () => retries++,
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('startup-error'))).data,
        contains('Check the internet connection'),
      );
      expect(find.textContaining('firebase down'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-retry')));
      expect(retries, 1);
    });

    testWidgets('a release build with USE_EMULATOR cannot be retried', (
      tester,
    ) async {
      await tester.pumpWidget(
        StartupErrorApp(error: const EmulatorInReleaseError(), onRetry: () {}),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('startup-error'))).data,
        contains('made for testing'),
      );
      expect(find.byKey(const Key('startup-retry')), findsNothing);
    });
  });
}
