// Startup on the real wiring: the app is pumped with `PosServices.overrides`
// (the list main.dart installs for the Firestore backend), filled with the
// fakes, and walks restored session → device registered? → billing, or
// sign-in → device setup.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/app.dart';
import 'package:nexus_pos/app/emulator_switch.dart';
import 'package:nexus_pos/app/providers.dart';
import 'package:nexus_pos/app/services.dart';
import 'package:nexus_pos/app/startup_error.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

/// Firebase Auth restoring a saved session: nothing on [session] until
/// [restore], as `FirebaseAuthService` holds back its first value until the
/// profile docs are loaded.
final class RestoringAuth implements AuthService {
  RestoringAuth(this.inner);

  final FakeAuthService inner;
  final Completer<void> _restored = Completer<void>();

  void restore() => _restored.complete();

  @override
  Stream<SessionContext?> get session async* {
    await _restored.future;
    yield* inner.session;
  }

  @override
  SessionContext? get current => _restored.isCompleted ? inner.current : null;

  @override
  Future<SessionContext> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<void> signOut() => inner.signOut();
}

/// [b]'s fakes behind the production override list, with [auth] in place
/// of the fake's own.
PosServices servicesOf(FakeBackend b, {AuthService? auth}) {
  final s = b.services;
  return PosServices(
    auth: auth ?? s.auth,
    devices: s.devices,
    catalogRepo: s.catalogRepo,
    catalog: s.catalog,
    salesRepo: s.salesRepo,
    sales: s.sales,
    summaries: s.summaries,
    stockRepo: s.stockRepo,
    stock: s.stock,
    sync: s.sync,
    offlineGuard: s.offlineGuard,
    printer: s.printer,
    customers: s.customers,
    phoneStore: s.phoneStore,
    linkLauncher: s.linkLauncher,
    receiptSharer: s.receiptSharer,
  );
}

Future<void> pumpStartup(WidgetTester tester, PosServices services) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...services.overrides,
        clockProvider.overrideWithValue(() => testNow),
      ],
      child: const PosApp(),
    ),
  );
  await tester.pump();
}

Finder appBar(String title) => find.widgetWithText(AppBar, title);

void main() {
  group('startup routing', () {
    testWidgets('restored session on a registered device opens billing', (
      tester,
    ) async {
      final b = FakeBackend(now: () => testNow);
      final auth = RestoringAuth(b.auth);
      await pumpStartup(tester, servicesOf(b, auth: auth));

      expect(find.text('Starting…'), findsOneWidget);
      expect(find.byKey(const Key('login-email')), findsNothing);

      auth.restore();
      await tester.pumpAndSettle();
      expect(appBar('Billing'), findsOneWidget);
    });

    testWidgets('restored session on an unregistered device opens setup', (
      tester,
    ) async {
      final b = FakeBackend(now: () => testNow, registered: false);
      final auth = RestoringAuth(b.auth);
      await pumpStartup(tester, servicesOf(b, auth: auth));
      auth.restore();
      await tester.pumpAndSettle();

      expect(appBar('Set up this device'), findsOneWidget);
      expect(appBar('Billing'), findsNothing);
    });

    testWidgets('no saved session: sign in, set up the device, then bill', (
      tester,
    ) async {
      final b = FakeBackend(
        now: () => testNow,
        signedIn: false,
        registered: false,
      );
      final auth = RestoringAuth(b.auth);
      await pumpStartup(tester, servicesOf(b, auth: auth));
      auth.restore();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-email')), findsOneWidget);

      await enterKey(tester, 'login-email', Seed.storeManager.email);
      await enterKey(tester, 'login-password', FakeAuthService.demoPassword);
      await tapKey(tester, 'sign-in');
      expect(appBar('Set up this device'), findsOneWidget);

      await enterKey(tester, 'device-label', 'Counter 1');
      await tapKey(tester, 'register');
      await tapKey(tester, 'skip-printer');
      expect(appBar('Billing'), findsOneWidget);
      expect(b.device.deviceId, Seed.deviceId);
    });

    testWidgets('no saved session on a registered device: sign in, bill', (
      tester,
    ) async {
      final b = FakeBackend(now: () => testNow, signedIn: false);
      await pumpStartup(tester, servicesOf(b));
      await tester.pumpAndSettle();
      await enterKey(tester, 'login-email', Seed.storeManager.email);
      await enterKey(tester, 'login-password', FakeAuthService.demoPassword);
      await tapKey(tester, 'sign-in');
      expect(appBar('Billing'), findsOneWidget);
    });
  });

  test('PosServices overrides every provider without an implementation', () {
    final c = ProviderContainer(overrides: FakeBackend().services.overrides);
    addTearDown(c.dispose);
    final reads = <String, Object Function()>{
      'authServiceProvider': () => c.read(authServiceProvider),
      'deviceServiceProvider': () => c.read(deviceServiceProvider),
      'catalogRepositoryProvider': () => c.read(catalogRepositoryProvider),
      'catalogServiceProvider': () => c.read(catalogServiceProvider),
      'salesRepositoryProvider': () => c.read(salesRepositoryProvider),
      'salesServiceProvider': () => c.read(salesServiceProvider),
      'summaryRepositoryProvider': () => c.read(summaryRepositoryProvider),
      'stockRepositoryProvider': () => c.read(stockRepositoryProvider),
      'stockServiceProvider': () => c.read(stockServiceProvider),
      'syncServiceProvider': () => c.read(syncServiceProvider),
      'offlineGuardProvider': () => c.read(offlineGuardProvider),
      'printerServiceProvider': () => c.read(printerServiceProvider),
      'customerRepositoryProvider': () => c.read(customerRepositoryProvider),
      'phoneStoreProvider': () => c.read(phoneStoreProvider),
      'linkLauncherProvider': () => c.read(linkLauncherProvider),
      'receiptSharerProvider': () => c.read(receiptSharerProvider),
    };
    for (final e in reads.entries) {
      expect(e.value, returnsNormally, reason: e.key);
    }
    expect(FakeBackend().services.overrides, hasLength(reads.length));
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
        contains('Check that the phone is connected to the internet'),
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
        contains('built for testing'),
      );
      expect(find.byKey(const Key('startup-retry')), findsNothing);
    });
  });
}
