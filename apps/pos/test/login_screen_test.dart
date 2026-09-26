import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_pos/features/billing/cart.dart';

import 'helpers.dart';

FakeBackend signedOut({bool registered = true, TestClock? clock}) =>
    FakeBackend(
      signedIn: false,
      registered: registered,
      now: clock?.call ?? () => testNow,
    );

Future<void> signIn(
  WidgetTester tester,
  String email, {
  String password = FakeAuthService.demoPassword,
}) async {
  await enterKey(tester, 'login-email', email);
  await enterKey(tester, 'login-password', password);
  await tapKey(tester, 'sign-in');
}

String get _sm => Seed.storeManager.email;

void main() {
  testWidgets('signs in, shows the prefetch, then opens billing', (
    tester,
  ) async {
    final clock = TestClock();
    final b = signedOut(clock: clock);
    b.sync.lastSyncAt = null;
    await pumpPos(tester, backend: b);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(isEnabled(tester, 'sign-in'), isFalse);

    b.auth.gate = Completer<void>();
    await enterKey(tester, 'login-email', ' SM.PTB@example.com ');
    await enterKey(tester, 'login-password', FakeAuthService.demoPassword);
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pump();
    expect(find.byKey(const Key('login-busy')), findsOneWidget);
    expect(isEnabled(tester, 'sign-in'), isFalse); // one sign-in at a time

    b.auth.gate!.complete();
    b.auth.gate = null;
    await tester.pumpAndSettle();
    expect(b.auth.signInCalls, hasLength(1));
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
    expect(find.byKey(const Key('product-bf-500')), findsOneWidget);
    // An interactive online sign-in counts as a sync (03-SYNC §6).
    expect(b.sync.lastSyncAt, clock.now);
  });

  group('friendly sign-in errors', () {
    Future<void> expectError(
      WidgetTester tester,
      FakeBackend b,
      String email,
      String message, {
      String password = FakeAuthService.demoPassword,
    }) async {
      await pumpPos(tester, backend: b);
      await signIn(tester, email, password: password);
      expect(textOf(tester, 'login-error'), message);
      expect(find.byKey(const Key('login-email')), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('login-password')),
      );
      expect(field.controller!.text, isEmpty);
      expect(b.auth.current, isNull);
    }

    testWidgets('invalidCredentials', (tester) async {
      await expectError(
        tester,
        signedOut(),
        _sm,
        'Wrong email or password.',
        password: 'not-it',
      );
    });

    testWidgets('userDisabled', (tester) async {
      await expectError(
        tester,
        signedOut(),
        FakeAuthService.disabledEmail,
        'This login has been disabled. Contact the Admin.',
      );
    });

    testWidgets('noProfile', (tester) async {
      await expectError(
        tester,
        signedOut(),
        FakeAuthService.noProfileEmail,
        "This login isn't set up for a store yet. Contact the Admin.",
      );
    });

    testWidgets('offline', (tester) async {
      final b = signedOut();
      b.auth.online = false;
      await expectError(
        tester,
        b,
        _sm,
        'Signing in on this device needs an internet connection the first '
        'time. Connect to Wi-Fi or mobile data and try again.',
      );
    });
  });

  testWidgets('after an error, a correct sign-in works', (tester) async {
    final b = signedOut();
    await pumpPos(tester, backend: b);
    await signIn(tester, _sm, password: 'wrong');
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    await enterKey(tester, 'login-password', FakeAuthService.demoPassword);
    await tapKey(tester, 'sign-in');
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
  });

  testWidgets('sign out from the drawer clears the cart', (tester) async {
    final b = await pumpPos(tester);
    await tapKey(tester, 'product-bf-500');
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'sign-out');
    expect(b.auth.current, isNull);
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('login-email'))),
    );
    expect(container.read(cartProvider), isEmpty);
  });

  testWidgets('first run: sign in, then device setup', (tester) async {
    final b = signedOut(registered: false);
    await pumpPos(tester, backend: b);
    await signIn(tester, _sm);
    expect(find.widgetWithText(AppBar, 'Set up this device'), findsOneWidget);
    await enterKey(tester, 'device-label', 'Counter 1');
    await tapKey(tester, 'register');
    await tapKey(tester, 'skip-printer');
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
  });
}
