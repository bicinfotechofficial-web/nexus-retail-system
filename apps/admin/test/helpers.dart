import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/app.dart';
import 'package:nexus_admin/data/providers.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/router.dart';

/// Every widget test runs on 2026-09-26 (IST).
const String testToday = '2026-09-26';
final DateTime testNow = DateTime.utc(2026, 9, 26, 6);

/// Pumps the whole console on [backend] at a desktop-sized window.
Future<void> pumpAdmin(
  WidgetTester tester,
  FakeBackend backend, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...backend.overrides,
        clockProvider.overrideWithValue(() => testNow),
        ...overrides,
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Signs in through the login screen.
Future<void> signIn(
  WidgetTester tester, {
  String email = FakeBackend.adminEmail,
  String password = FakeBackend.demoPassword,
}) async {
  await tester.enterText(find.byKey(const Key('login-email')), email);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

/// Navigates the console's router to [path], as typing the URL would.
Future<void> goTo(WidgetTester tester, String path) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  );
  container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
}
